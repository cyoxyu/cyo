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
