import CoreGraphics
import Testing
@testable import FolzioCore

@Suite("FitCalculator")
struct FitCalculatorTests {
    @Test("Fits a landscape image inside the container")
    func fitsLandscapeImage() {
        let rect = FitCalculator.fit(
            imageSize: CGSize(width: 2000, height: 1000),
            in: CGSize(width: 500, height: 500)
        )
        #expect(rect == CGRect(x: 0, y: 125, width: 500, height: 250))
    }

    @Test("Fits a portrait image inside the container")
    func fitsPortraitImage() {
        let rect = FitCalculator.fit(
            imageSize: CGSize(width: 1000, height: 2000),
            in: CGSize(width: 500, height: 500)
        )
        #expect(rect == CGRect(x: 125, y: 0, width: 250, height: 500))
    }

    @Test("Scales up and centers a landscape image smaller than the container")
    func enlargesSmallLandscapeImage() {
        let rect = FitCalculator.fit(
            imageSize: CGSize(width: 200, height: 80),
            in: CGSize(width: 500, height: 500)
        )
        #expect(rect == CGRect(x: 0, y: 150, width: 500, height: 200))
    }

    @Test("Scales up and centers a portrait image smaller than the container")
    func enlargesSmallPortraitImage() {
        let rect = FitCalculator.fit(
            imageSize: CGSize(width: 80, height: 200),
            in: CGSize(width: 500, height: 500)
        )
        #expect(rect == CGRect(x: 150, y: 0, width: 200, height: 500))
    }

    @Test("Scales up even a 1x1 image to fit the container")
    func enlargesSinglePixelImage() {
        let rect = FitCalculator.fit(
            imageSize: CGSize(width: 1, height: 1),
            in: CGSize(width: 500, height: 500)
        )
        #expect(rect == CGRect(x: 0, y: 0, width: 500, height: 500))
    }

    @Test("Centers an exactly fitting image at its original size")
    func keepsExactFitImageUnchanged() {
        let rect = FitCalculator.fit(
            imageSize: CGSize(width: 500, height: 250),
            in: CGSize(width: 500, height: 500)
        )
        #expect(rect == CGRect(x: 0, y: 125, width: 500, height: 250))
    }

    @Test("Returns an empty rectangle for nonpositive dimensions", arguments: [
        (CGSize(width: 0, height: 100), CGSize(width: 500, height: 500)),
        (CGSize(width: 100, height: 100), CGSize(width: 0, height: 0)),
        (CGSize(width: -1, height: 100), CGSize(width: 500, height: 500)),
    ])
    func returnsZeroForInvalidSizes(imageSize: CGSize, container: CGSize) {
        #expect(FitCalculator.fit(imageSize: imageSize, in: container) == .zero)
    }

    // MARK: - Applying Zoom (frame(imageSize:in:zoom:))

    @Test("100% produces the same rectangle as fit", arguments: [
        (CGSize(width: 2000, height: 1000), CGSize(width: 500, height: 500)),
        (CGSize(width: 1000, height: 2000), CGSize(width: 500, height: 500)),
        (CGSize(width: 200, height: 80), CGSize(width: 500, height: 500)),
        (CGSize(width: 1, height: 1), CGSize(width: 500, height: 500)),
        (CGSize(width: 500, height: 250), CGSize(width: 500, height: 500)),
    ])
    func fitZoomMatchesFit(imageSize: CGSize, container: CGSize) {
        #expect(
            FitCalculator.frame(imageSize: imageSize, in: container, zoom: .fit)
                == FitCalculator.fit(imageSize: imageSize, in: container)
        )
    }

    @Test("125% scales by 1.25 around the fitted center with a negative origin when overflowing")
    func zoomsInAroundCenter() throws {
        let rect = FitCalculator.frame(
            imageSize: CGSize(width: 2000, height: 1000),
            in: CGSize(width: 500, height: 500),
            zoom: try #require(PreviewZoom(percentage: 125))
        )
        #expect(rect == CGRect(x: -62.5, y: 93.75, width: 625, height: 312.5))
    }

    @Test("50% centers the image at half the fitted size")
    func zoomsOutAroundCenter() throws {
        let rect = FitCalculator.frame(
            imageSize: CGSize(width: 2000, height: 1000),
            in: CGSize(width: 500, height: 500),
            zoom: try #require(PreviewZoom(percentage: 50))
        )
        #expect(rect == CGRect(x: 125, y: 187.5, width: 250, height: 125))
    }

    @Test("800% multiplies width and height by eight with a negative origin")
    func zoomsToMaximum() throws {
        let rect = FitCalculator.frame(
            imageSize: CGSize(width: 2000, height: 1000),
            in: CGSize(width: 500, height: 500),
            zoom: try #require(PreviewZoom(percentage: 800))
        )
        #expect(rect.width == 4000)
        #expect(rect.height == 2000)
        #expect(rect.minX < 0)
        #expect(rect.minY < 0)
        #expect(rect.midX == 250)
        #expect(rect.midY == 250)
    }

    @Test("800% also scales a 1x1 image around its center")
    func zoomsSinglePixelImage() throws {
        let rect = FitCalculator.frame(
            imageSize: CGSize(width: 1, height: 1),
            in: CGSize(width: 500, height: 500),
            zoom: try #require(PreviewZoom(percentage: 800))
        )
        #expect(rect == CGRect(x: -1750, y: -1750, width: 4000, height: 4000))
    }

    @Test("Zoom still returns an empty rectangle for nonpositive dimensions", arguments: [
        (CGSize(width: 0, height: 100), CGSize(width: 500, height: 500)),
        (CGSize(width: 100, height: 100), CGSize(width: 0, height: 0)),
        (CGSize(width: -1, height: 100), CGSize(width: 500, height: 500)),
    ])
    func zoomedFrameIsZeroForInvalidSizes(imageSize: CGSize, container: CGSize) throws {
        let zoom = try #require(PreviewZoom(percentage: 200))
        #expect(FitCalculator.frame(imageSize: imageSize, in: container, zoom: zoom) == .zero)
    }
}
