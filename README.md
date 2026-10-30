<div align="center">

# ESAI Impulse

**DataImpulse 流量还剩多少？抬头看一眼状态栏。**

原生 macOS 状态栏应用，实时显示 DataImpulse 代理套餐的剩余流量，余量不足时自动提醒。

![macOS](https://img.shields.io/badge/macOS-13%2B-333333)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-288653)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

</div>

## 亮点

- **常驻状态栏**：图标 + 剩余流量（例如 `128.4 GB`），不占 Dock，不打扰工作。
- **一眼看清用量**：点开面板查看剩余、总量、已用、已用百分比进度条和上次刷新时间；支持手动刷新，获取失败时显示错误原因。
- **超额也能正确显示**：剩余为负时状态栏显示红色 `0 GB`，面板标出具体超额量。
- **低流量提醒**：剩余低于阈值（默认 200 GB）时数字变橙并发送一次系统通知；用尽时变红并再通知一次。每次跨越阈值只提醒一次，通知仅作信息展示。
- **自定义刷新**：5 / 15 / 30 / 60 分钟自动刷新，默认 15 分钟；唤醒后自动刷新。
- **账号安全**：DataImpulse 登录名和密码只保存在 macOS 钥匙串，不写入文件、偏好设置或日志。
- **与 esai 一致的界面**：Liquid Glass 面板（macOS 26+，旧系统使用兼容样式）、六种经典强调色与自定义 HEX、浅色/深色/跟随系统、3 pt 细滚动条、小号开关。
- **双语**：简体中文、English，默认跟随系统语言。
- **登录时启动**：基于 `SMAppService`，可在「设置 → 通用」开关。

## 安装

1. 从 [Releases](../../releases) 下载 `ESAI-Impulse.zip`，解压后拖入「应用程序」。
2. 应用为 ad-hoc 签名（无 Developer ID），首次打开如被 Gatekeeper 拦截，请在 Finder 中右键 → 打开，或到「系统设置 → 隐私与安全性」中允许。
3. 打开后点状态栏图标 → 设置 → 账号，填写代理套餐（Plan）的登录名和密码，点「保存并刷新」。

## 数据来源

调用 `GET https://gw.dataimpulse.com:777/api/stats`（HTTP Basic 认证），读取 `total_traffic`、`traffic_used`、`traffic_left`（单位字节）。显示按 1 GB = 10⁹ 字节换算，保留一位小数。

## 从源码构建

需要 Apple Silicon Mac 和 Command Line Tools（Swift 5.9+），无需完整 Xcode：

```sh
./build.sh          # swift build -c release + 组装并 ad-hoc 签名 build/ESAI Impulse.app
```

## 许可

AGPL-3.0。界面组件复用自 [esai](https://github.com/fitzsmith2000/esai)，部分代码改编自 [Licoy/Quosparr](https://github.com/Licoy/Quosparr)，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
