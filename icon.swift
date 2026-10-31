import AppKit
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let rect = NSRect(x: 32, y: 32, width: 960, height: 960)
let base = NSBezierPath(roundedRect: rect, xRadius: 215, yRadius: 215)
NSGradient(colors: [NSColor(calibratedRed: 0.29, green: 0.69, blue: 0.80, alpha: 1), NSColor(calibratedRed: 0.07, green: 0.17, blue: 0.29, alpha: 1)])!.draw(in: base, angle: -75)
NSColor.white.withAlphaComponent(0.22).setStroke(); base.lineWidth = 4; base.stroke()
let screen = NSBezierPath(roundedRect: NSRect(x: 208, y: 338, width: 608, height: 420), xRadius: 52, yRadius: 52)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.77), NSColor.white.withAlphaComponent(0.16)])!.draw(in: screen, angle: -70)
NSColor.white.withAlphaComponent(0.88).setStroke(); screen.lineWidth = 12; screen.stroke()
let stand = NSBezierPath(); stand.move(to: NSPoint(x: 512, y: 330)); stand.line(to: NSPoint(x: 512, y: 252)); stand.move(to: NSPoint(x: 398, y: 250)); stand.line(to: NSPoint(x: 626, y: 250)); stand.lineWidth = 16; stand.lineCapStyle = .round; stand.stroke()
let sun = NSBezierPath(ovalIn: NSRect(x: 461, y: 495, width: 102, height: 102)); NSColor.white.setFill(); sun.fill()
for i in 0..<8 {
    let a = Double(i) * .pi / 4
    let ray = NSBezierPath(); ray.move(to: NSPoint(x: 512 + cos(a)*78, y: 546 + sin(a)*78)); ray.line(to: NSPoint(x: 512 + cos(a)*100, y: 546 + sin(a)*100)); ray.lineWidth = 11; ray.lineCapStyle = .round; ray.stroke()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
