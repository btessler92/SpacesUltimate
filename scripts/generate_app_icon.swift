#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let sourcePNG = resources.appendingPathComponent("SpacesUltimateIconSource.png")
let iconset = resources.appendingPathComponent("SpacesUltimate.iconset", isDirectory: true)
let icns = resources.appendingPathComponent("SpacesUltimate.icns")

try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: Int) throws -> CGImage {
    let width = size
    let height = size
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconError.contextFailed
    }

    let scale = CGFloat(size) / 1024.0
    func r(_ value: CGFloat) -> CGFloat { value * scale }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: r(x), y: r(y), width: r(w), height: r(h))
    }

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let bounds = rect(56, 56, 912, 912)
    let basePath = CGPath(roundedRect: bounds, cornerWidth: r(210), cornerHeight: r(210), transform: nil)
    context.addPath(basePath)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.15, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.24, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1).cgColor
        ] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: bounds.minX, y: bounds.maxY),
        end: CGPoint(x: bounds.maxX, y: bounds.minY),
        options: []
    )

    context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    context.setLineWidth(r(18))
    context.addPath(basePath)
    context.strokePath()

    let panels: [(CGRect, NSColor)] = [
        (rect(246, 262, 300, 250), NSColor(calibratedRed: 0.18, green: 0.50, blue: 0.93, alpha: 1)),
        (rect(478, 326, 300, 250), NSColor(calibratedRed: 0.15, green: 0.68, blue: 0.38, alpha: 1)),
        (rect(314, 514, 300, 250), NSColor(calibratedRed: 0.93, green: 0.35, blue: 0.35, alpha: 1))
    ]

    for (index, panel) in panels.enumerated() {
        let panelRect = panel.0
        let shadowOffset = CGSize(width: r(0), height: r(-18))
        context.saveGState()
        context.setShadow(offset: shadowOffset, blur: r(36), color: NSColor.black.withAlphaComponent(0.34).cgColor)
        let panelPath = CGPath(roundedRect: panelRect, cornerWidth: r(54), cornerHeight: r(54), transform: nil)
        context.setFillColor(panel.1.cgColor)
        context.addPath(panelPath)
        context.fillPath()
        context.restoreGState()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        context.setLineWidth(r(8))
        context.addPath(panelPath)
        context.strokePath()

        context.setFillColor(NSColor.white.withAlphaComponent(index == 1 ? 0.28 : 0.22).cgColor)
        context.fillEllipse(in: CGRect(x: panelRect.minX + r(44), y: panelRect.maxY - r(76), width: r(26), height: r(26)))
        context.fillEllipse(in: CGRect(x: panelRect.minX + r(82), y: panelRect.maxY - r(76), width: r(26), height: r(26)))
        context.fillEllipse(in: CGRect(x: panelRect.minX + r(120), y: panelRect.maxY - r(76), width: r(26), height: r(26)))
    }

    context.setLineCap(.round)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.88).cgColor)
    context.setLineWidth(r(34))
    context.move(to: CGPoint(x: r(286), y: r(690)))
    context.addLine(to: CGPoint(x: r(738), y: r(690)))
    context.strokePath()

    context.setStrokeColor(NSColor.white.withAlphaComponent(0.72).cgColor)
    context.setLineWidth(r(28))
    context.move(to: CGPoint(x: r(286), y: r(616)))
    context.addLine(to: CGPoint(x: r(594), y: r(616)))
    context.strokePath()

    guard let image = context.makeImage() else {
        throw IconError.imageFailed
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw IconError.destinationFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconError.writeFailed(url.path)
    }
}

let sourceImage = try drawIcon(size: 1024)
try writePNG(sourceImage, to: sourcePNG)

let iconSizes: [(String, Int)] = [
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

for (name, size) in iconSizes {
    try writePNG(try drawIcon(size: size), to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", iconset.path, "--output", icns.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw IconError.iconutilFailed(process.terminationStatus)
}

print(icns.path)

enum IconError: LocalizedError {
    case contextFailed
    case imageFailed
    case destinationFailed
    case writeFailed(String)
    case iconutilFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .contextFailed:
            "Could not create icon drawing context."
        case .imageFailed:
            "Could not render icon image."
        case .destinationFailed:
            "Could not create PNG destination."
        case .writeFailed(let path):
            "Could not write PNG at \(path)."
        case .iconutilFailed(let status):
            "iconutil failed with exit status \(status)."
        }
    }
}
