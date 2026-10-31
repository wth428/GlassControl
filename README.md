# 澄控 · GlassControl

**[中文](#中文) · [English](#english)**

A native macOS menu bar app for external monitor brightness and speaker volume.  
用键盘亮度键和音量键，直接控制外接显示器背光与显示器音响。

**[下载安装包 / Download app](https://github.com/wth428/GlassControl/releases/latest)** · [MIT License](LICENSE)

## 中文

### 下载与安装（无需编译）

1. 从 [GitHub Releases](https://github.com/wth428/GlassControl/releases/latest) 下载 **`GlassControl-1.0.0-arm64.zip`**。请选择这个安装包，而不是 GitHub 自动生成的 `Source code`。
2. 双击解压，将 **「澄控.app」拖到「应用程序」**，然后打开。
3. 点击菜单栏的显示器图标，即可用两个滑块调亮度和音量。
4. 如需使用键盘控制，点面板中的「授权」，在 **系统设置 → 隐私与安全性 → 辅助功能** 中打开「澄控」。授权后自动生效。

**系统要求：Apple Silicon（M 系列芯片），macOS 14 或更新版本。Intel Mac 不支持。** 显示器及连接线、转接器需要支持 DDC/CI；请在显示器菜单中开启 DDC/CI。无需安装开发工具或虚拟声卡。当前应用界面为中文。

安装包使用本地 ad-hoc 签名，**尚未经过 Apple Developer ID 签名或公证**。首次打开可能被 macOS 拦截；确认下载来自本仓库后，可按 [Apple 的说明](https://support.apple.com/en-us/102445)，在 **系统设置 → 隐私与安全性 → 仍要打开** 中手动允许这款应用。无需关闭系统安全检查。

### 功能与操作

- 两个滑块：显示器硬件背光、显示器音响音量。
- 支持亮度键、音量键、静音键，以及 Shift + Option 微调。
- 音量键只在系统声音输出为所选显示器时接管；切到耳机或内置扬声器后交由系统处理。
- 支持选择显示器、唤醒后重连、可选登录启动。
- macOS 26 使用原生 Liquid Glass；旧系统使用半透明玻璃材质。
- 离线运行，不更改显示器色彩曲线。

| 按键 | 操作 |
| --- | --- |
| 亮度键 / F1、F2 | 降低 / 提高显示器背光 |
| F10 | 静音 / 恢复静音前音量 |
| F11、F12 | 降低 / 提高显示器音响音量 |
| Shift + Option + 媒体键 | 每次微调 1% |

若顶排按键设置为标准功能键，请同时按 fn。关闭窗口后应用继续常驻菜单栏，从「⋯ → 退出澄控」退出。

### 兼容性与验证范围

已在 M1 Pro、macOS 15.6.1、Mi Monitor / DisplayPort 上验证硬件亮度和音量读写、界面滑块及退出后重新打开。构建包含 7 项控制逻辑检查和本地代码签名验证。

其他显示器、macOS 26 外观、实体媒体键端到端操作、登录启动与实际插拔显示器仍待实机验证。

- HDR、显示器预设、扩展坞或转接器可能限制 DDC。无法确认设置时界面会提示错误，请刷新重试。
- 音频路由按当前输出设备名称匹配显示器；多台同名显示器的匹配尚未验证。
- 请避免与 MonitorControl 等同类工具同时运行，以免重复接管媒体键。

### 从源码构建（可选）

需要 Swift 6.2 和 macOS 26 SDK 或更新版本，以编译 Liquid Glass API；部署目标为 macOS 14。可使用包含相应 SDK 的 Xcode Command Line Tools 或 Xcode。仅有旧版 SDK 时无法编译。

```sh
git clone https://github.com/wth428/GlassControl.git
cd GlassControl
zsh build.sh
open build/澄控.app
```

m1ddc 源码已随仓库提供，无需额外下载第三方依赖。产物为 Apple Silicon arm64。

诊断与逻辑检查：

```sh
build/澄控.app/Contents/MacOS/GlassControl --diagnose
build/澄控.app/Contents/MacOS/GlassControl --self-test
```

诊断输出包含显示器名称和 UUID，分享前请按需移除设备标识。可选的 `hardware_check.py <m1ddc路径> <显示器UUID>` 会分别降低亮度、音量一格并读回，在 `finally` 中恢复原值；它会暂时改变真实硬件设置。

### 隐私与许可

应用不收集数据。事件监听器只处理亮度和音量媒体键，不记录普通键盘输入。

MIT License，© 2026 Sky Wu。显示器通信使用 [waydabber/m1ddc](https://github.com/waydabber/m1ddc)，MIT License，© 2021 waydabber。原始许可保留在 [`vendor/m1ddc/LICENSE`](vendor/m1ddc/LICENSE)，上游版本及本地修改见 [THIRD_PARTY.md](THIRD_PARTY.md)。

## English

### Download and install — no compilation required

1. Download **`GlassControl-1.0.0-arm64.zip`** from [GitHub Releases](https://github.com/wth428/GlassControl/releases/latest). Choose this app archive, not the automatically generated `Source code` downloads.
2. Double-click the ZIP, drag **`澄控.app` to Applications**, and open it.
3. Click the monitor icon in the menu bar to adjust brightness and volume with the two sliders.
4. For keyboard controls, click **授权** (Authorize) in the panel, then enable **澄控** in **System Settings → Privacy & Security → Accessibility**. The app detects permission automatically.

**Requires an Apple Silicon Mac (M-series chip) running macOS 14 or later. Intel Macs are not supported.** Your monitor and connection path must support DDC/CI; enable DDC/CI in the monitor's on-screen menu. No developer tools or virtual audio driver are needed. The app interface is currently in Chinese.

The app is ad-hoc signed and **does not yet have an Apple Developer ID signature or notarization**. macOS may block the first launch. After verifying that the download came from this repository, follow [Apple's instructions](https://support.apple.com/en-us/102445) to allow this app using **System Settings → Privacy & Security → Open Anyway**. You do not need to disable system security checks.

### Features and controls

- Two sliders: hardware monitor backlight and monitor speaker volume.
- Brightness, volume, and mute keys, with Shift + Option for fine adjustment.
- Volume keys are intercepted only when the selected monitor is the current audio output. Headphones and built-in speakers remain under system control.
- Monitor selection, reconnection after wake, and optional launch at login.
- Native Liquid Glass on macOS 26; translucent glass materials on earlier systems.
- Works offline without changing display color curves.

| Key | Action |
| --- | --- |
| Brightness keys / F1, F2 | Decrease / increase monitor backlight |
| F10 | Mute / restore the previous volume |
| F11, F12 | Decrease / increase monitor speaker volume |
| Shift + Option + media key | Adjust by 1% |

If your keyboard uses the top row as standard function keys, hold fn as well. Closing the window leaves the app running in the menu bar. Choose **⋯ → 退出澄控** (Quit GlassControl) to quit.

### Compatibility and verification

Hardware brightness and volume read/write, both sliders, and quitting and reopening have been tested on an M1 Pro with macOS 15.6.1 and a Mi Monitor using DisplayPort. The build runs seven control-logic checks and verifies local code signatures.

Other monitors, the macOS 26 appearance, end-to-end physical media-key input, launch at login, and physical display hot-plugging still require testing.

- HDR, monitor presets, docks, and adapters may restrict DDC. If a setting cannot be confirmed, the app reports an error; refresh and retry.
- Audio routing matches the output device name to the monitor name. Multiple monitors with identical names have not been verified.
- Avoid running alongside MonitorControl or other media-key tools to prevent conflicting key handling.

### Build from source — optional

Building requires Swift 6.2 and the macOS 26 SDK or newer to compile the Liquid Glass APIs. The deployment target is macOS 14. Use Xcode Command Line Tools or Xcode with a suitable SDK; older SDKs cannot compile this project.

```sh
git clone https://github.com/wth428/GlassControl.git
cd GlassControl
zsh build.sh
open build/澄控.app
```

The m1ddc source is vendored, so no additional third-party dependencies need to be downloaded. The output is an Apple Silicon arm64 app.

Diagnostics and logic checks:

```sh
build/澄控.app/Contents/MacOS/GlassControl --diagnose
build/澄控.app/Contents/MacOS/GlassControl --self-test
```

Diagnostic output includes display names and UUIDs; remove device identifiers before sharing if needed. The optional `hardware_check.py <m1ddc-path> <display-UUID>` temporarily lowers brightness and volume by one step, reads them back, and restores their original values in `finally`. It changes real hardware settings during the check.

### Privacy and license

The app collects no data. Its event listener handles brightness and volume media keys only and does not record normal typing.

MIT License, © 2026 Sky Wu. Display communication uses [waydabber/m1ddc](https://github.com/waydabber/m1ddc), MIT License, © 2021 waydabber. The original license is retained in [`vendor/m1ddc/LICENSE`](vendor/m1ddc/LICENSE). See [THIRD_PARTY.md](THIRD_PARTY.md) for the upstream revision and local changes.
