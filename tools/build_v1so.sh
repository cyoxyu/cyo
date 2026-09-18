#!/usr/bin/env bash
# 在 Linux VPS 上编译自注入版本号的 v1.so（哪吒 v1 agent 的 c-shared 变体）
# 产物：amd64/v1.so 和 arm64/v1.so，后台版本显示 5.5.5，agent 日志按配置静默
set -euo pipefail

AGENT_TAG="v1.9.0"          # 想要对齐的官方 agent 源码版本（与现网裸 v1 行为一致即可）
INJECT_VERSION="5.5.5"      # 注入 monitor.Version —— 这是哪吒后台显示的版本
WORK=/tmp/nezha-v1so
mkdir -p "$WORK"
cd "$WORK"

# 1) 拉取官方 agent 源码
if [ ! -d agent ]; then
  git clone --depth 1 --branch "$AGENT_TAG" https://github.com/nezhahq/agent.git agent
fi
cd agent

# 2) 写入 c-shared 包装层（导出 Start/Stop，与 sbx.so/bot.so 同接口约定）
cat > cmd/agent/lib_shared.go <<'EOF'
package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"encoding/json"
	"sync"

	"github.com/nezhahq/agent/pkg/logger"
)

var (
	libOnce sync.Once
	libDone = make(chan struct{})
)

//export StartNezhaAgent
func StartNezhaAgent(payload *C.char) C.int {
	raw := C.GoString(payload)
	var in struct {
		Config string `json:"config"`
	}
	_ = json.Unmarshal([]byte(raw), &in)
	path := in.Config
	if path != "" {
		if err := preRun(path); err != nil {
			return C.int(1)
		}
	} else {
		if err := preRun(""); err != nil {
			return C.int(1)
		}
	}
	// 包装层跳过了 runService()，官方在那里用 agentConfig.Debug 初始化日志；
	// 不补这一步的话 pkg/logger 默认 enabled=true，NEZHA@ 日志会全量打进宿主进程
	logger.SetEnable(agentConfig.Debug)
	go run()
	return C.int(0)
}

//export StopNezhaAgent
func StopNezhaAgent() C.int {
	libOnce.Do(func() { close(libDone) })
	return C.int(0)
}
EOF

# 3) 给 run() 加停止钩子：内层 select 增加 libDone 分支
#    用 perl 多行匹配插入，失败即中止（不静默）
grep -q 'case <-libDone:' cmd/agent/main.go || {
  perl -0pi -e 's/(select \{\n\t+)(case <-reloadSigChan:)/${1}case <-libDone:\n\t\t\treturn\n\t\t\t${2}/' cmd/agent/main.go
  grep -q 'case <-libDone:' cmd/agent/main.go || { echo "patch run() failed"; exit 1; }
}

# 3.5) 生成配置方法（Apply 等）。agent 仓库不带生成产物，缺这步会报
#      "agentConfig.Apply undefined"，必须先 go generate
go generate ./...

# 4) 内存保护：无 swap 时尝试挂 2G swapfile；容器环境 swapon 常被禁止，失败不中止
ensure_swap() {
  if [ "$(awk 'NR>1' /proc/swaps | wc -l)" -gt 0 ]; then
    return 0
  fi
  echo "未检测到 swap，尝试创建 2G swapfile ..."
  if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
  fi
  if swapon /swapfile 2>/dev/null; then
    echo "swap 已启用："
    awk 'NR>1' /proc/swaps
  else
    echo "!! swapon 失败（容器环境常见），删除 swapfile，改用低内存编译参数继续"
    rm -f /swapfile
  fi
}
ensure_swap

# 5) 交叉编译两个架构（c-shared 需要对应 gcc）
# -p 1 串行编译 + GOMEMLIMIT/GOGC 压内存峰值，无 swap 的小内存容器也能编
export CGO_ENABLED=1
export GOMAXPROCS=1
export GOGC=50
export GOMEMLIMIT="${GOMEMLIMIT:-300MiB}"
BUILD_LDFLAGS="-s -w -X github.com/nezhahq/agent/pkg/monitor.Version=${INJECT_VERSION}"

# amd64（本机）
GOOS=linux GOARCH=amd64 CGO_ENABLED=1 \
  go build -buildmode=c-shared -p 1 -trimpath -ldflags "$BUILD_LDFLAGS" -o v1_amd64.so ./cmd/agent

# arm64（需装交叉 gcc：apt install gcc-aarch64-linux-gnu）
if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
  echo "!! 未找到 aarch64-linux-gnu-gcc。arm64 需要它。请先安装：apt-get install -y gcc-aarch64-linux-gnu 再重跑"
  exit 2
fi
GOOS=linux GOARCH=arm64 CGO_ENABLED=1 CC=aarch64-linux-gnu-gcc \
  go build -buildmode=c-shared -p 1 -trimpath -ldflags "$BUILD_LDFLAGS" -o v1_arm64.so ./cmd/agent

cp v1_amd64.so /tmp/v1.so.amd64
cp v1_arm64.so /tmp/v1.so.arm64
echo "完成："
ls -la /tmp/v1.so.amd64 /tmp/v1.so.arm64
