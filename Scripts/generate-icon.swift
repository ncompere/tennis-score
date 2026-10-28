// Run with: xcrun swift Scripts/generate-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
context.setFillColor(CGColor(red: 0.025, green: 0.07, blue: 0.09, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let ball = CGRect(x: 222, y: 222, width: 580, height: 580)
context.setFillColor(CGColor(red: 0.64, green: 0.95, blue: 0.34, alpha: 1))
context.fillEllipse(in: ball)
context.saveGState()
context.addEllipse(in: ball)
context.clip()
context.setStrokeColor(CGColor(red: 0.97, green: 1, blue: 0.91, alpha: 1))
context.setLineWidth(24)
for x in [60.0, 630.0] {
    context.strokeEllipse(in: CGRect(x: x, y: 170, width: 330, height: 680))
}
context.restoreGState()
let output = URL(fileURLWithPath: "WatchApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write the app icon") }
