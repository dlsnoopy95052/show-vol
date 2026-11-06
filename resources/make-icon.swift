import AppKit
// Usage: swiftc make-icon.swift -o make-icon && ./make-icon out.png
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
// background squircle
let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.20, green: 0.62, blue: 1.0, alpha: 1), NSColor(red: 0.30, green: 0.25, blue: 0.85, alpha: 1)])!.draw(in: bg, angle: -60)
// drive body
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
let body = NSBezierPath(roundedRect: NSRect(x: 212, y: 330, width: 600, height: 300), xRadius: 50, yRadius: 50)
NSColor.white.setFill(); body.fill()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
// usage bar
let track = NSBezierPath(roundedRect: NSRect(x: 262, y: 400, width: 380, height: 46), xRadius: 23, yRadius: 23)
NSColor(white: 0.85, alpha: 1).setFill(); track.fill()
let fill = NSBezierPath(roundedRect: NSRect(x: 262, y: 400, width: 250, height: 46), xRadius: 23, yRadius: 23)
NSColor(red: 0.20, green: 0.62, blue: 1.0, alpha: 1).setFill(); fill.fill()
// activity LED
NSColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 702, y: 400, width: 46, height: 46)).fill()
// magnifier
let ring = NSBezierPath(ovalIn: NSRect(x: 520, y: 520, width: 230, height: 230))
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.white.withAlphaComponent(0.0).setFill()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
NSColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 1).setStroke()
ring.lineWidth = 34; ring.stroke()
let h = NSBezierPath(); h.move(to: NSPoint(x: 722, y: 548)); h.line(to: NSPoint(x: 795, y: 475))
h.lineWidth = 44; h.lineCapStyle = .round; h.stroke()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
