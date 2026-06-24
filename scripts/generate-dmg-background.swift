#!/usr/bin/env swift
import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "dist/dmg-background.png"
let size = NSSize(width: 760, height: 460)
let image = NSImage(size: size)

image.lockFocus()

NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1)
]
let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1)
]

("拖动安装" as NSString).draw(at: CGPoint(x: 314, y: 365), withAttributes: titleAttributes)
("将 DMG安装器 拖入 Applications 文件夹" as NSString).draw(at: CGPoint(x: 242, y: 337), withAttributes: subtitleAttributes)
("安装后请从“应用程序”文件夹打开，推出磁盘映像后 App 仍会保留。" as NSString).draw(at: CGPoint(x: 177, y: 62), withAttributes: hintAttributes)

let arrowPath = NSBezierPath()
arrowPath.move(to: CGPoint(x: 275, y: 230))
arrowPath.curve(to: CGPoint(x: 485, y: 230), controlPoint1: CGPoint(x: 350, y: 282), controlPoint2: CGPoint(x: 410, y: 282))
arrowPath.lineWidth = 13
arrowPath.lineCapStyle = .round
NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.95, alpha: 0.28).setStroke()
arrowPath.stroke()

let head = NSBezierPath()
head.move(to: CGPoint(x: 495, y: 230))
head.line(to: CGPoint(x: 454, y: 257))
head.line(to: CGPoint(x: 466, y: 230))
head.line(to: CGPoint(x: 454, y: 203))
head.close()
NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.95, alpha: 0.28).setFill()
head.fill()

drawLandingCircle(center: CGPoint(x: 220, y: 230), title: "App")
drawLandingCircle(center: CGPoint(x: 540, y: 230), title: "Applications")

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    throw BackgroundError.renderFailed
}

try png.write(to: URL(filePath: outputPath))

private func drawLandingCircle(center: CGPoint, title: String) {
    let circleRect = CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124)
    let circle = NSBezierPath(ovalIn: circleRect)
    NSColor.white.setFill()
    circle.fill()
    NSColor(calibratedWhite: 0.90, alpha: 1).setStroke()
    circle.lineWidth = 2
    circle.stroke()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.48, alpha: 1)
    ]
    let text = title as NSString
    let textSize = text.size(withAttributes: attributes)
    text.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - 88), withAttributes: attributes)
}

private enum BackgroundError: Error {
    case renderFailed
}
