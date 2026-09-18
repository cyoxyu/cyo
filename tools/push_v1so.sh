#!/usr/bin/env bash
# 把编译好的 v1.so 推送到指定仓库
# 用法:  REPO=<owner>/<repo> TOKEN=<ghp_xxx> bash push_v1so.sh
# 源文件: /tmp/v1.so.amd64 -> amd64/v1.so   /tmp/v1.so.arm64 -> arm64/v1.so
# TOKEN 通过环境变量传入（建议 read -rs 输入），不写文件、不进命令历史
set -euo pipefail

REPO="${REPO:?用法: REPO=<owner>/<repo> TOKEN=<ghp_xxx> bash push_v1so.sh}"
TOKEN="${TOKEN:?缺少 TOKEN 环境变量}"

for f in /tmp/v1.so.amd64 /tmp/v1.so.arm64; do
  [ -s "$f" ] || { echo "缺少 $f，请先运行 build_v1so.sh"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 优先匿名克隆（公开仓库），失败再带 token 克隆（私有仓库）
git clone --depth 1 --branch main "https://github.com/${REPO}.git" "$WORK/repo" 2>/dev/null \
  || git clone --depth 1 --branch main "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "$WORK/repo"

cp /tmp/v1.so.amd64 "$WORK/repo/amd64/v1.so"
cp /tmp/v1.so.arm64 "$WORK/repo/arm64/v1.so"

cd "$WORK/repo"
git config user.name  "${REPO%%/*}"
git config user.email "${REPO%%/*}@users.noreply.github.com"
git add -A

if git diff --cached --quiet; then
  echo "v1.so 无变化，无需推送"
  exit 0
fi

git commit -m "rebuild v1.so: agent logs follow config debug flag (silent by default), version 5.5.5"
git push "https://x-access-token:${TOKEN}@github.com/${REPO}.git" HEAD:main
echo "已推送: https://github.com/${REPO}"
