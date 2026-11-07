import AppKit
// Usage: swiftc make-icon.swift -o make-icon && ./make-icon out.png
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
// background squircle
let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.20, green: 0.62, blue: 1.0, alpha: 1), NSColor(red: 0.30, green: 0.25, blue: 0.85, alpha: 1)])!.draw(in: bg, angle: -60)
// bold "V"
let v = NSBezierPath()
v.move(to: NSPoint(x: 300, y: 705)); v.line(to: NSPoint(x: 512, y: 325)); v.line(to: NSPoint(x: 724, y: 705))
v.lineWidth = 120; v.lineCapStyle = .round; v.lineJoinStyle = .round
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.white.setStroke(); v.stroke()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
