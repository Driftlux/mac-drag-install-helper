#!/usr/bin/env swift
import AppKit
import Foundation

let outputURL = URL(filePath: CommandLine.arguments.dropFirst().first ?? "dist/MacDragInstallHelper.iconset", directoryHint: .isDirectory)
let fileManager = FileManager.default

try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let iconFiles: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in iconFiles {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    drawIcon(in: CGRect(x: 0, y: 0, width: size, height: size), scale: size / 1024)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.renderFailed(filename)
    }

    try png.write(to: outputURL.appending(path: filename))
}

private func drawIcon(in rect: CGRect, scale: CGFloat) {
    func value(_ raw: CGFloat) -> CGFloat { raw * scale }

    NSGraphicsContext.current?.imageInterpolation = .high

    let outer = NSBezierPath(roundedRect: rect.insetBy(dx: value(64), dy: value(64)), xRadius: value(210), yRadius: value(210))
    NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.72, alpha: 1).setFill()
    outer.fill()

    let glow = NSBezierPath(ovalIn: CGRect(x: value(114), y: value(548), width: value(800), height: value(340)))
    NSColor(calibratedRed: 0.33, green: 0.72, blue: 1.0, alpha: 0.28).setFill()
    glow.fill()

    let diskRect = CGRect(x: value(212), y: value(214), width: value(600), height: value(600))
    let disk = NSBezierPath(ovalIn: diskRect)
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    disk.fill()

    NSColor(calibratedRed: 0.77, green: 0.84, blue: 0.93, alpha: 1).setStroke()
    disk.lineWidth = value(28)
    disk.stroke()

    let innerDisk = NSBezierPath(ovalIn: diskRect.insetBy(dx: value(204), dy: value(204)))
    NSColor(calibratedRed: 0.10, green: 0.31, blue: 0.82, alpha: 1).setFill()
    innerDisk.fill()

    let slot = NSBezierPath(roundedRect: CGRect(x: value(354), y: value(384), width: value(316), height: value(76)), xRadius: value(38), yRadius: value(38))
    NSColor(calibratedRed: 0.82, green: 0.90, blue: 0.99, alpha: 1).setFill()
    slot.fill()

    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: value(512), y: value(770)))
    arrow.line(to: CGPoint(x: value(512), y: value(566)))
    arrow.lineWidth = value(66)
    arrow.lineCapStyle = .round
    NSColor.white.setStroke()
    arrow.stroke()

    let head = NSBezierPath()
    head.move(to: CGPoint(x: value(378), y: value(602)))
    head.line(to: CGPoint(x: value(512), y: value(468)))
    head.line(to: CGPoint(x: value(646), y: value(602)))
    head.close()
    NSColor.white.setFill()
    head.fill()

    let base = NSBezierPath(roundedRect: CGRect(x: value(346), y: value(276), width: value(332), height: value(76)), xRadius: value(38), yRadius: value(38))
    NSColor.white.setFill()
    base.fill()
}

private enum IconError: Error {
    case renderFailed(String)
}
