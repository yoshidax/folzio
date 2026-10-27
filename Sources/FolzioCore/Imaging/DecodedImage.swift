import CoreGraphics

public struct DecodedImage: Sendable {
    public var cgImage: CGImage
    public var pixelSize: CGSize
    public var originalPixelSize: CGSize
    public var byteCost: Int

    public init(cgImage: CGImage, pixelSize: CGSize, originalPixelSize: CGSize, byteCost: Int) {
        self.cgImage = cgImage
        self.pixelSize = pixelSize
        self.originalPixelSize = originalPixelSize
        self.byteCost = byteCost
    }
}
