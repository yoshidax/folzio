import Testing
@testable import FolzioCore

@Suite("PreviewZoomAvailability")
struct PreviewZoomAvailabilityTests {
    @Test("All three zoom actions are available at 100% when an image is shown and the preview is visible")
    func availableAtFit() {
        let availability = PreviewZoomAvailability(isImageDisplayed: true, isPreviewVisible: true, level: .fit)
        #expect(availability.isAvailable)
        #expect(availability.canZoomIn)
        #expect(availability.canZoomOut)
        #expect(availability.canFit)
    }

    @Test("Only zoom in is disabled at 800%, and only zoom out at 25%")
    func limits() throws {
        let maximum = PreviewZoomAvailability(
            isImageDisplayed: true,
            isPreviewVisible: true,
            level: try #require(PreviewZoom(percentage: 800))
        )
        #expect(maximum.canZoomIn == false)
        #expect(maximum.canZoomOut)
        #expect(maximum.canFit)

        let minimum = PreviewZoomAvailability(
            isImageDisplayed: true,
            isPreviewVisible: true,
            level: try #require(PreviewZoom(percentage: 25))
        )
        #expect(minimum.canZoomOut == false)
        #expect(minimum.canZoomIn)
        #expect(minimum.canFit)
    }

    @Test("All three actions are disabled without an image or when the preview is not visible, regardless of zoom", arguments: [
        (false, true, 100),
        (true, false, 100),
        (false, false, 100),
        (false, true, 800),
        (true, false, 25),
        (false, true, 250),
    ])
    func unavailable(isImageDisplayed: Bool, isPreviewVisible: Bool, percentage: Int) throws {
        let availability = PreviewZoomAvailability(
            isImageDisplayed: isImageDisplayed,
            isPreviewVisible: isPreviewVisible,
            level: try #require(PreviewZoom(percentage: percentage))
        )
        #expect(availability.isAvailable == false)
        #expect(availability.canZoomIn == false)
        #expect(availability.canZoomOut == false)
        #expect(availability.canFit == false)
    }
}
