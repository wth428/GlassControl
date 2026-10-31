import AppKit
import SwiftUI
import CoreAudio
import ApplicationServices
import ServiceManagement

// All hardware IO is serialized off the main thread. The helper is bundled,
// MIT licensed, and selected by the display UUID, never by enumeration order.
struct DDC {
    static var helper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/m1ddc") }
    static func run(_ args: [String]) -> String? {
        let p = Process(), pipe = Pipe()
        p.executableURL = helper; p.arguments = args
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        if done.wait(timeout: .now() + 4) == .timedOut {
            p.terminate()
            // Do not leave a stuck helper blocking the UI or the serial IO queue.
            if done.wait(timeout: .now() + 0.3) == .timedOut { kill(p.processIdentifier, SIGKILL) }
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func read(_ uuid: String, _ name: String, max: Bool = false) -> Int? {
        guard let s = run(["display", uuid, max ? "max" : "get", name]), let value = Int(s), value >= 0 else { return nil }
        return value
    }
    static func set(_ uuid: String, _ name: String, _ value: Int) -> Bool {
        run(["display", uuid, "set", name, String(value)]) != nil
    }
}
struct Display: Identifiable, Equatable {
    let id: String
    let cgID: CGDirectDisplayID
    let name: String
    static func connected() -> [Display] {
        NSScreen.screens.compactMap { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = n.uint32Value
            guard CGDisplayIsBuiltin(id) == 0, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            return Display(id: CFUUIDCreateString(nil, uuid) as String, cgID: id, name: s.localizedName)
        }
    }
}
struct Level: Equatable {
    var current: Int
    let maximum: Int
    var percent: Double { Double(current) / Double(maximum) * 100 }
    static func scaled(_ percent: Double, maximum: Int) -> Int {
        Int((min(100, max(0, percent)) / 100 * Double(maximum)).rounded())
    }
}
struct AudioOutput {
    let name: String
    let transport: UInt32
    static func current() -> AudioOutput? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr, device != 0 else { return nil }
        addr.mSelector = kAudioObjectPropertyName
        var rawName: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rawName) == noErr, let name = rawName?.takeRetainedValue() else { return nil }
        addr.mSelector = kAudioDevicePropertyTransportType
        var transport: UInt32 = 0; size = 4
        _ = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport)
        return AudioOutput(name: name as String, transport: transport)
    }
    var isDisplay: Bool { transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI }
}

final class Controls: ObservableObject {
    @Published var displays: [Display] = []
    @Published var selected = ""
    @Published var brightness: Level?
    @Published var volume: Level?
    @Published var busy = false
    @Published var message = "正在连接显示器…"
    @Published var keyboardReady = false
    @Published var audioName = ""
    @Published var routeMatches = false
    @Published var login = SMAppService.mainApp.status == .enabled
    @Published var conflict = ""
    var selectedDisplay: Display? { displays.first { $0.id == selected } }
    var keys: MediaKeys?
    var hud: HUD?
    private let io = DispatchQueue(label: "studio.skywu.glasscontrol.hardware", qos: .userInitiated)
    private var pending: [String: DispatchWorkItem] = [:]
    private var revision: [String: Int] = [:]
    private var generation = 0
    private var lastVolume = 30.0
    private var timer: Timer?
    private var lastRead = Date.distantPast
    init() {
        selected = UserDefaults.standard.string(forKey: "selectedDisplay") ?? ""
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateRoute()
            if AXIsProcessTrusted() { self.keys?.start() }
            self.keyboardReady = AXIsProcessTrusted() && (self.keys?.active ?? false)
            let names = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            self.conflict = names.contains("me.guillaumeb.MonitorControl") ? "MonitorControl 正在运行，建议退出它以避免按键冲突。" : ""
            // Re-read physical OSD changes periodically, without overwriting edits.
            if Date().timeIntervalSince(self.lastRead) > 25 && self.pending.isEmpty && !self.busy { self.refresh() }
        }
    }
    func boot() {
        hud = HUD()
        keys = MediaKeys { [weak self] key, small, down in
            guard let self, self.canHandle(key) else { return false }
            if down { self.adjust(key, small: small) }
            return true
        }
        keys?.start(); keyboardReady = keys?.active ?? false
        refresh()
    }
    func updateRoute() {
        let output = AudioOutput.current()
        audioName = output?.name ?? "未检测到输出设备"
        // Do not steal volume keys from headphones, built-in speakers, or another display.
        routeMatches = output?.isDisplay == true && output?.name == selectedDisplay?.name
    }
    func refresh() {
        guard !busy, pending.isEmpty else { return }
        displays = Display.connected()
        if !displays.contains(where: { $0.id == selected }) { selected = displays.first?.id ?? "" }
        updateRoute()
        guard let display = selectedDisplay else {
            generation += 1; brightness = nil; volume = nil
            message = "接上显示器后，亮度和音量会出现在这里。"; return
        }
        UserDefaults.standard.set(selected, forKey: "selectedDisplay")
        busy = true; generation += 1
        let token = generation
        io.async { [weak self] in
            func level(_ key: String) -> Level? {
                guard let current = DDC.read(display.id, key), let maximum = DDC.read(display.id, key, max: true), maximum > 0, current <= maximum else { return nil }
                return Level(current: current, maximum: maximum)
            }
            let b = level("luminance"), v = level("volume")
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.brightness = b; self.volume = v; self.busy = false; self.lastRead = Date()
                self.message = b != nil && v != nil ? "已连接 · 硬件直控" : "部分控制未响应，请在显示器菜单中开启 DDC/CI 后重试。"
            }
        }
    }
    func select(_ uuid: String) {
        for work in pending.values { work.cancel() }; pending.removeAll()
        generation += 1; busy = false; brightness = nil; volume = nil
        selected = uuid; refresh()
    }
    func set(_ key: String, percent: Double) {
        guard let display = selectedDisplay, let old = key == "luminance" ? brightness : volume, !busy else { return }
        let raw = Level.scaled(percent, maximum: old.maximum)
        let level = Level(current: raw, maximum: old.maximum)
        if key == "luminance" { brightness = level } else { volume = level }
        pending[key]?.cancel()
        revision[key, default: 0] += 1
        let rev = revision[key]!, token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.io.async { [weak self] in
                let sent = DDC.set(display.id, key, raw)
                Thread.sleep(forTimeInterval: 0.08)
                let actual = sent ? DDC.read(display.id, key) : nil
                DispatchQueue.main.async {
                    guard let self, self.generation == token, self.revision[key] == rev else { return }
                    self.pending.removeValue(forKey: key)
                    if let actual, actual <= old.maximum {
                        let checked = Level(current: actual, maximum: old.maximum)
                        if key == "luminance" { self.brightness = checked } else { self.volume = checked }
                        self.message = abs(actual - raw) <= 1 ? "已连接 · 硬件直控" : "显示器返回了不同的数值，已显示实际设置。"
                    } else {
                        // A successful I2C write alone does not prove that the monitor accepted it.
                        if key == "luminance" { self.brightness = nil } else { self.volume = nil }
                        self.message = "无法确认显示器是否接受设置，请重新连接并刷新。"
                    }
                }
            }
        }
        pending[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
    }
    func canHandle(_ key: Int) -> Bool {
        guard !busy, selectedDisplay != nil else { return false }
        if key == 2 || key == 3 { return brightness != nil }
        updateRoute()
        return [0, 1, 7].contains(key) && volume != nil && routeMatches
    }
    func adjust(_ key: Int, small: Bool) {
        let isBrightness = key == 2 || key == 3
        guard let value = isBrightness ? brightness : volume else { return }
        var target: Double
        if key == 7 {
            if value.percent > 0 { lastVolume = value.percent; target = 0 } else { target = lastVolume }
        } else {
            let sign = (key == 0 || key == 2) ? 1.0 : -1.0
            target = min(100, max(0, value.percent + sign * (small ? 1 : 6.25)))
        }
        set(isBrightness ? "luminance" : "volume", percent: target)
        hud?.show(title: isBrightness ? "显示器亮度" : "音响音量", symbol: isBrightness ? "sun.max.fill" : (target == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"), percent: target, display: selectedDisplay)
    }
    func authorize() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func toggleLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            login = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                message = "请在系统设置的登录项中允许「澄控」。"
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { message = "登录启动未设置成功：\(error.localizedDescription)"; login = SMAppService.mainApp.status == .enabled }
    }
}

// The NX system-defined media keys include separate key-down/up events.
// Consume both only when the corresponding external hardware is available.
final class MediaKeys {
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var active: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    let handler: (Int, Bool, Bool) -> Bool
    init(handler: @escaping (Int, Bool, Bool) -> Bool) { self.handler = handler }
    static func decode(_ data: Int) -> (key: Int, down: Bool)? {
        let key = (data >> 16) & 0xffff, state = (data >> 8) & 0xff
        guard [0, 1, 2, 3, 7].contains(key), state == 0x0a || state == 0x0b else { return nil }
        return (key, state == 0x0a)
    }
    func start() {
        if let tap { if AXIsProcessTrusted() { CGEvent.tapEnable(tap: tap, enable: true) }; return }
        guard AXIsProcessTrusted() else { return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<MediaKeys>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard let e = NSEvent(cgEvent: event), e.type == .systemDefined, e.subtype.rawValue == 8,
                  let decoded = MediaKeys.decode(e.data1) else { return Unmanaged.passUnretained(event) }
            let small = e.modifierFlags.contains(.shift) && e.modifierFlags.contains(.option)
            return me.handler(decoded.key, small, decoded.down) ? nil : Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue), callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

struct Frost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active; return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.36), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
        }
    }
}
struct ControlCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let value: Level?
    let disabled: Bool
    let change: (Double) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 23, weight: .medium)).frame(width: 34).foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value.map { String(Int($0.percent.rounded())) } ?? "—").font(.system(size: 29, weight: .light, design: .rounded)).monospacedDigit()
                    if value != nil { Text("%").font(.system(size: 12)).foregroundStyle(.secondary) }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: title == "亮度" ? "sun.min" : "speaker").font(.system(size: 12)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { value?.percent ?? 0 }, set: change), in: 0...100)
                    .tint(Color.primary.opacity(0.85)).disabled(value == nil || disabled)
                    .accessibilityLabel(title).accessibilityValue(value.map { "\(Int($0.percent))%" } ?? "不可用")
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }.padding(20).modifier(GlassCard())
    }
}
struct PanelView: View {
    @ObservedObject var model: Controls
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [.white.opacity(0.75), .cyan.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "display").font(.system(size: 23, weight: .light))
                }.frame(width: 49, height: 49).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.6), lineWidth: 0.6))
                VStack(alignment: .leading, spacing: 3) {
                    Text("澄控").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("屏幕与声音，随手掌控").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 25, height: 25) }
                    .buttonStyle(.plain).help("重新读取显示器").disabled(model.busy)
            }
            VStack(alignment: .leading, spacing: 7) {
                if model.displays.count > 1 {
                    Picker("显示器", selection: Binding(get: { model.selected }, set: { model.select($0) })) {
                        ForEach(model.displays) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                } else {
                    Text(model.selectedDisplay?.name ?? "等待外接显示器").font(.system(size: 14, weight: .semibold))
                }
                HStack(spacing: 6) {
                    Circle().fill(model.brightness != nil && model.volume != nil ? Color.green : Color.orange).frame(width: 5, height: 5)
                    Text(model.message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 3)
            ControlCard(title: "亮度", subtitle: model.brightness == nil ? "等待显示器响应" : "显示器背光 · F1 / F2", symbol: "sun.max.fill", value: model.brightness, disabled: model.busy) { model.set("luminance", percent: $0) }
            ControlCard(title: "音量", subtitle: model.volume == nil ? "等待显示器响应" : "显示器音响 · F10 / F11 / F12", symbol: "speaker.wave.2.fill", value: model.volume, disabled: model.busy) { model.set("volume", percent: $0) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: model.keyboardReady ? "keyboard.badge.ellipsis" : "keyboard")
                    Text(model.keyboardReady ? "键盘控制已开启" : "开启亮度键和音量键").font(.system(size: 12, weight: .medium))
                    Spacer()
                    if !model.keyboardReady { Button("授权") { model.authorize() }.controlSize(.small) }
                    else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                if !model.keyboardReady {
                    Text("在系统设置 → 隐私与安全性 → 辅助功能中打开「澄控」。授权后自动生效，滑块现在即可使用。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !model.routeMatches && model.selectedDisplay != nil {
                    Text("当前声音输出：\(model.audioName)。音量滑块控制显示器；音量键随系统输出。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !model.conflict.isEmpty { Text(model.conflict).font(.system(size: 11)).foregroundStyle(.orange) }
            }.padding(.horizontal, 4)
            Divider().opacity(0.4)
            HStack {
                Toggle("登录时启动", isOn: Binding(get: { model.login }, set: model.toggleLogin)).toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                Menu {
                    Button("使用说明") { AppDelegate.shared.showHelp() }
                    Button("辅助功能设置") { model.authorize() }
                    Divider()
                    Button("退出澄控", role: .destructive) { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 16)) }.menuStyle(.borderlessButton).fixedSize()
            }
        }
        .padding(24).frame(width: 416)
        .background {
            ZStack {
                Frost()
                LinearGradient(colors: [.cyan.opacity(0.09), .clear, .indigo.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

struct HUDView: View {
    let title: String, symbol: String
    let percent: Double
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 23)).frame(width: 30)
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(title).font(.system(size: 12, weight: .medium)); Spacer(); Text("\(Int(percent.rounded()))%").monospacedDigit().font(.system(size: 12)) }
                ProgressView(value: percent, total: 100).tint(.primary)
            }
        }.padding(20).frame(width: 260).modifier(GlassCard())
    }
}
final class HUD {
    let panel: NSPanel
    var dismissal: DispatchWorkItem?
    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 90), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.ignoresMouseEvents = true; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    func show(title: String, symbol: String, percent: Double, display: Display?) {
        dismissal?.cancel()
        panel.contentView = NSHostingView(rootView: HUDView(title: title, symbol: symbol, percent: percent))
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display?.cgID } ?? NSScreen.main
        if let f = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: f.midX - 150, y: f.minY + 74)) }
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }; dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppDelegate!
    let model = Controls()
    var status: NSStatusItem!
    let popover = NSPopover()
    var welcome: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "澄控：亮度和音量")
        status.button?.target = self; status.button?.action = #selector(togglePanel)
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model)); popover.behavior = .transient; popover.delegate = self
        model.boot()
        if !UserDefaults.standard.bool(forKey: "launched") {
            UserDefaults.standard.set(true, forKey: "launched"); showWindow()
        }
        if CommandLine.arguments.contains("--show") { showWindow() }
    }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = status.button { model.refresh(); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    func showWindow() {
        if welcome == nil {
            let host = NSHostingView(rootView: PanelView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 416, height: 590), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "澄控"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.isOpaque = false; window.backgroundColor = .clear; window.isReleasedWhenClosed = false
            window.contentView = host; window.setContentSize(host.fittingSize); window.center(); welcome = window
        }
        welcome?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return false }
    func showHelp() {
        let alert = NSAlert()
        alert.messageText = "澄控 · GlassControl"
        alert.informativeText = "用菜单栏滑块或键盘控制外接显示器。\n\n• F1 / F2 调背光，F11 / F12 调音量，F10 静音。若键盘设置为标准功能键，请同时按 fn。\n• 按住 ⇧⌥ 可每次微调 1%。\n• 音量键仅在声音输出为当前显示器时接管。\n• 首次使用按键需授予辅助功能权限。\n• 需要显示器与连接线支持 DDC/CI。\n• 不同音响请在系统设置 → 声音中选择输出。\n\n当前 Mac 使用磨砂玻璃界面；macOS 26 使用原生 Liquid Glass。\n\n显示器通信组件 m1ddc © 2021 waydabber，MIT License。应用离线工作，不收集数据。"
        alert.addButton(withTitle: "知道了"); alert.runModal()
    }
    func applicationWillTerminate(_ notification: Notification) { if let tap = model.keys?.tap { CGEvent.tapEnable(tap: tap, enable: false) } }
}

if CommandLine.arguments.contains("--self-test") {
    func check(_ condition: @autoclosure () -> Bool, _ name: String) { if !condition() { fputs("FAIL: \(name)\n", stderr); exit(1) } }
    check(Level.scaled(-10, maximum: 100) == 0, "lower clamp")
    check(Level.scaled(110, maximum: 100) == 100, "upper clamp")
    check(Level.scaled(50, maximum: 255) == 128, "non-100 DDC range")
    check(MediaKeys.decode((2 << 16) | (0x0a << 8))?.down == true, "brightness key down")
    check(MediaKeys.decode((7 << 16) | (0x0b << 8))?.down == false, "mute key up")
    check(MediaKeys.decode((16 << 16) | (0x0a << 8)) == nil, "unrelated media key passthrough")
    check(MediaKeys.decode((2 << 16) | (0x03 << 8)) == nil, "invalid key state passthrough")
    print("PASS: 7 control logic checks"); exit(0)
}
if CommandLine.arguments.contains("--diagnose") {
    let d = Display.connected()
    let report: [[String: Any]] = d.map { display in
        var row: [String: Any] = ["name": display.name, "uuid": display.id]
        row["brightness"] = DDC.read(display.id, "luminance") ?? -1
        row["brightnessMax"] = DDC.read(display.id, "luminance", max: true) ?? -1
        row["volume"] = DDC.read(display.id, "volume") ?? -1
        row["volumeMax"] = DDC.read(display.id, "volume", max: true) ?? -1
        return row
    }
    let object: [String: Any] = ["displays": report, "audioOutput": AudioOutput.current()?.name ?? "", "accessibility": AXIsProcessTrusted()]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!); exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
