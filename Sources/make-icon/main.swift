import CoreGraphics
import Darwin
import Foundation
import ImageIO

private let designSize: CGFloat = 1024
private let renderSizes = [16, 32, 64, 128, 256, 512, 1024]

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func fillRounded(_ context: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor) {
    context.addPath(roundedPath(rect, radius: radius))
    context.setFillColor(color)
    context.fillPath()
}

private func strokeRounded(_ context: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor, width: CGFloat) {
    context.addPath(roundedPath(rect, radius: radius))
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.strokePath()
}

private func drawIcon(pixelSize: Int) throws -> CGImage {
    let scale = CGFloat(pixelSize) / designSize
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: pixelSize,
              height: pixelSize,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw IconError.contextCreationFailed(pixelSize)
    }

    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.setLineJoin(.round)
    context.setLineCap(.round)

    let square = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squarePath = roundedPath(square, radius: 185)

    context.saveGState()
    context.addPath(squarePath)
    context.clip()

    let background = CGGradient(
        colorsSpace: space,
        colors: [color(0.21, 0.31, 0.56), color(0.06, 0.09, 0.17)] as CFArray,
        locations: [0, 1]
    )
    if let background {
        context.drawLinearGradient(
            background,
            start: CGPoint(x: square.midX, y: square.maxY),
            end: CGPoint(x: square.midX, y: square.minY),
            options: []
        )
    }

    let glow = CGGradient(
        colorsSpace: space,
        colors: [color(0.55, 0.72, 1.0, 0.28), color(0.55, 0.72, 1.0, 0)] as CFArray,
        locations: [0, 1]
    )
    if let glow {
        context.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: square.midX, y: square.maxY),
            startRadius: 0,
            endCenter: CGPoint(x: square.midX, y: square.maxY),
            endRadius: 620,
            options: []
        )
    }
    context.restoreGState()

    strokeRounded(
        context,
        square,
        radius: 185,
        color: color(1, 1, 1, 0.16),
        width: max(3, 1 / scale)
    )

    let card = CGRect(x: 168, y: 168, width: 688, height: 688)
    fillRounded(context, card, radius: 64, color: color(1, 1, 1, 0.08))
    strokeRounded(
        context,
        card,
        radius: 64,
        color: color(1, 1, 1, 0.18),
        width: max(4, 1 / scale)
    )

    let paneTop: CGFloat = 194
    let paneHeight: CGFloat = 636
    let paneGap: CGFloat = 14
    let availableWidth = 636 - paneGap * 2
    let leftWidth = (availableWidth * 0.26).rounded()
    let middleWidth = (availableWidth * 0.34).rounded()
    let rightWidth = availableWidth - leftWidth - middleWidth

    let leftPane = CGRect(x: 194, y: paneTop, width: leftWidth, height: paneHeight)
    let middlePane = CGRect(
        x: leftPane.maxX + paneGap,
        y: paneTop,
        width: middleWidth,
        height: paneHeight
    )
    let rightPane = CGRect(
        x: middlePane.maxX + paneGap,
        y: paneTop,
        width: rightWidth,
        height: paneHeight
    )
    let paneStroke = max(3, 1 / scale)

    fillRounded(context, leftPane, radius: 26, color: color(0.20, 0.38, 0.68, 0.95))
    strokeRounded(context, leftPane, radius: 26, color: color(1, 1, 1, 0.14), width: paneStroke)

    fillRounded(context, middlePane, radius: 26, color: color(0.09, 0.13, 0.21, 0.95))
    strokeRounded(context, middlePane, radius: 26, color: color(1, 1, 1, 0.12), width: paneStroke)

    fillRounded(context, rightPane, radius: 26, color: color(0.07, 0.11, 0.19, 0.95))
    strokeRounded(context, rightPane, radius: 26, color: color(1, 1, 1, 0.12), width: paneStroke)

    drawFolder(in: context, pane: leftPane)
    drawThumbnailGrid(in: context, pane: middlePane)
    drawPreview(in: context, pane: rightPane)

    guard let image = context.makeImage() else {
        throw IconError.imageCreationFailed(pixelSize)
    }
    return image
}

private func drawFolder(in context: CGContext, pane: CGRect) {
    let width = pane.width * 0.60
    let height = width * 0.72
    let originX = pane.midX - width / 2
    let originY = pane.midY - height / 2
    let folderColor = color(0.94, 0.97, 1.0, 0.96)

    let tab = CGRect(
        x: originX,
        y: originY + height * 0.60,
        width: width * 0.48,
        height: height * 0.30
    )
    fillRounded(context, tab, radius: height * 0.08, color: folderColor)

    let body = CGRect(
        x: originX,
        y: originY,
        width: width,
        height: height * 0.72
    )
    fillRounded(context, body, radius: height * 0.10, color: folderColor)

    let slot = CGRect(
        x: originX + width * 0.16,
        y: originY + height * 0.22,
        width: width * 0.68,
        height: max(6, height * 0.08)
    )
    fillRounded(context, slot, radius: slot.height / 2, color: color(0.20, 0.38, 0.68, 0.55))
}

private func drawThumbnailGrid(in context: CGContext, pane: CGRect) {
    let inset: CGFloat = 24
    let gap: CGFloat = 14
    let gridWidth = pane.width - inset * 2
    let gridHeight = pane.height - inset * 2
    let cellWidth = (gridWidth - gap) / 2
    let cellHeight = (gridHeight - gap) / 2
    let colors = [
        color(0.33, 0.62, 0.95),
        color(0.30, 0.80, 0.64),
        color(0.97, 0.67, 0.23),
        color(0.91, 0.43, 0.56),
    ]

    for index in 0..<4 {
        let column = CGFloat(index % 2)
        let row = CGFloat(index / 2)
        let rect = CGRect(
            x: pane.minX + inset + column * (cellWidth + gap),
            y: pane.minY + inset + row * (cellHeight + gap),
            width: cellWidth,
            height: cellHeight
        )
        fillRounded(context, rect, radius: 16, color: colors[index])
        let highlight = rect.insetBy(dx: 10, dy: 10)
        fillRounded(context, highlight, radius: 10, color: color(1, 1, 1, 0.18))
    }
}

private func drawPreview(in context: CGContext, pane: CGRect) {
    let photo = pane.insetBy(dx: 20, dy: 20)
    let photoPath = roundedPath(photo, radius: 18)

    context.saveGState()
    context.addPath(photoPath)
    context.clip()

    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let sky = CGGradient(
           colorsSpace: space,
           colors: [color(0.37, 0.67, 0.88), color(0.10, 0.31, 0.47)] as CFArray,
           locations: [0, 1]
       ) {
        context.drawLinearGradient(
            sky,
            start: CGPoint(x: photo.midX, y: photo.maxY),
            end: CGPoint(x: photo.midX, y: photo.minY),
            options: []
        )
    }

    let sunRadius = min(photo.width, photo.height) * 0.10
    let sunCenter = CGPoint(
        x: photo.minX + photo.width * 0.72,
        y: photo.minY + photo.height * 0.70
    )
    context.setFillColor(color(1.0, 0.85, 0.38))
    context.fillEllipse(
        in: CGRect(
            x: sunCenter.x - sunRadius,
            y: sunCenter.y - sunRadius,
            width: sunRadius * 2,
            height: sunRadius * 2
        )
    )

    let mountains = CGMutablePath()
    mountains.move(to: CGPoint(x: photo.minX, y: photo.minY))
    mountains.addLine(to: CGPoint(
        x: photo.minX + photo.width * 0.32,
        y: photo.minY + photo.height * 0.42
    ))
    mountains.addLine(to: CGPoint(
        x: photo.minX + photo.width * 0.55,
        y: photo.minY + photo.height * 0.22
    ))
    mountains.addLine(to: CGPoint(
        x: photo.minX + photo.width * 0.76,
        y: photo.minY + photo.height * 0.38
    ))
    mountains.addLine(to: CGPoint(
        x: photo.maxX,
        y: photo.minY + photo.height * 0.18
    ))
    mountains.addLine(to: CGPoint(x: photo.maxX, y: photo.minY))
    mountains.closeSubpath()
    context.addPath(mountains)
    context.setFillColor(color(0.07, 0.24, 0.28, 0.95))
    context.fillPath()
    context.restoreGState()

    let badgeRadius = min(photo.width, photo.height) * 0.20
    let badgeCenter = CGPoint(x: photo.midX, y: photo.midY)
    context.setFillColor(color(1, 1, 1, 0.94))
    context.fillEllipse(
        in: CGRect(
            x: badgeCenter.x - badgeRadius,
            y: badgeCenter.y - badgeRadius,
            width: badgeRadius * 2,
            height: badgeRadius * 2
        )
    )

    let play = CGMutablePath()
    play.move(to: CGPoint(
        x: badgeCenter.x - badgeRadius * 0.34,
        y: badgeCenter.y - badgeRadius * 0.52
    ))
    play.addLine(to: CGPoint(
        x: badgeCenter.x + badgeRadius * 0.52,
        y: badgeCenter.y
    ))
    play.addLine(to: CGPoint(
        x: badgeCenter.x - badgeRadius * 0.34,
        y: badgeCenter.y + badgeRadius * 0.52
    ))
    play.closeSubpath()
    context.addPath(play)
    context.setFillColor(color(0.07, 0.10, 0.18))
    context.fillPath()
}

private enum IconError: Error, CustomStringConvertible {
    case usage
    case contextCreationFailed(Int)
    case imageCreationFailed(Int)
    case destinationCreationFailed(URL)
    case writeFailed(URL)

    var description: String {
        switch self {
        case .usage:
            return "usage: make-icon <output-directory>"
        case .contextCreationFailed(let size):
            return "failed to create a \(size)x\(size) drawing context"
        case .imageCreationFailed(let size):
            return "failed to render the \(size)x\(size) icon"
        case .destinationCreationFailed(let url):
            return "failed to create the PNG destination at \(url.path)"
        case .writeFailed(let url):
            return "failed to write \(url.path)"
        }
    }
}

private func generateIcons(into directory: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    for pixelSize in renderSizes {
        let image = try drawIcon(pixelSize: pixelSize)
        let url = directory.appendingPathComponent("icon_\(pixelSize)x\(pixelSize).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw IconError.destinationCreationFailed(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw IconError.writeFailed(url)
        }
    }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("\(IconError.usage)\n".utf8))
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

do {
    try generateIcons(into: outputDirectory)
} catch {
    try? FileManager.default.removeItem(at: outputDirectory)
    FileHandle.standardError.write(Data("make-icon: \(error)\n".utf8))
    exit(1)
}
