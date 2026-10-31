# 澄控 · GlassControl

A small native macOS menu bar app for external monitor brightness and speaker volume.

一个简单的 macOS 菜单栏工具：用键盘亮度键和音量键，直接控制外接显示器背光与接在显示器上的音响。

## 功能

- 两个滑块：显示器背光、显示器音响音量。
- 支持亮度键、音量键、静音键；Shift + Option 每次微调 1%。
- 音量键仅在系统声音输出为所选显示器时接管，切到耳机或内置扬声器时由系统处理。
- 支持选择显示器、唤醒后重连、可选登录启动。
- macOS 26 使用原生 Liquid Glass；旧系统使用半透明玻璃材质。
- 离线工作，无虚拟声卡，不更改显示器色彩曲线。

## 系统要求

- Apple Silicon Mac，macOS 14 或更新版本。
- 显示器和连接链路需要支持 DDC/CI。请在显示器菜单中开启 DDC/CI。
- 已在 M1 Pro、macOS 15.6.1、Mi Monitor / DisplayPort 上验证硬件亮度和音量读写及界面滑块。其他显示器的兼容性未经实测。
- macOS 26 外观、实体媒体键端到端操作、登录启动与实际插拔显示器仍待实机验证。

## 使用

将构建生成的「澄控.app」移到「应用程序」目录并打开，点击菜单栏的显示器图标。

滑块无需辅助功能权限。要使用键盘控制，请点「授权」，在「系统设置 → 隐私与安全性 → 辅助功能」中打开「澄控」。授权后自动生效。

| 按键 | 操作 |
| --- | --- |
| 亮度键 / F1、F2 | 降低 / 提高显示器背光 |
| F10 | 静音 / 恢复静音前音量 |
| F11、F12 | 降低 / 提高显示器音响音量 |
| Shift + Option + 媒体键 | 每次微调 1% |

若顶排按键设置为标准功能键，请同时按 fn。关闭窗口后应用继续常驻菜单栏，从「⋯ → 退出澄控」退出。

## 构建

需要 Swift 6.2 和 macOS 26 SDK 或更新版本（用于编译 Liquid Glass API）；部署目标为 macOS 14。可使用包含相应 SDK 的 Xcode Command Line Tools 或 Xcode。仅有旧版 SDK 时无法编译。

```sh
zsh build.sh
open build/澄控.app
```

无需额外下载第三方依赖，m1ddc 源码已随仓库提供。构建会执行 7 项控制逻辑检查和本地签名验证，产物为 Apple Silicon arm64。

诊断和逻辑检查：

```sh
build/澄控.app/Contents/MacOS/GlassControl --diagnose
build/澄控.app/Contents/MacOS/GlassControl --self-test
```

诊断输出包含显示器名称和 UUID，分享前请按需移除设备标识。

`hardware_check.py <m1ddc路径> <显示器UUID>` 是可选的硬件回环检查：分别降低亮度、音量一格，读回后在 finally 中恢复原值。运行会暂时改变真实硬件设置，不是纯只读诊断。

## 已知限制

- Intel Mac 不支持。
- HDR、显示器预设、转接器或扩展坞可能限制 DDC。无法确认设置时，界面会提示错误，请刷新重试。
- 音量键通过当前音频设备名称匹配所选显示器；多台同名显示器的路由匹配尚未验证。
- 请避免与 MonitorControl 等其他媒体键控制工具同时运行。
- 构建产物使用本地 ad-hoc 签名，未做 Developer ID 签名或 Apple 公证；其他 Mac 可能需要在系统设置中允许打开。

## 隐私

应用不收集数据。事件监听器只处理亮度/音量媒体键，不记录普通键盘输入。

## 许可证

MIT License，© 2026 Sky Wu。

显示器通信使用 [waydabber/m1ddc](https://github.com/waydabber/m1ddc)，MIT License，© 2021 waydabber。原始许可保留在 `vendor/m1ddc/LICENSE`，版本及本地修改说明见 [THIRD_PARTY.md](THIRD_PARTY.md)。
