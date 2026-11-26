import CoreGraphics
import FolzioCore
import Testing

@Suite("Video badge layout")
struct VideoBadgeLayoutTests {
    /// Image view sides of the thumbnail mode at the thumbnail sizes 48, 128, and 512 pt (the item width minus 8 pt).
    static let viewSides: [Double] = [40, 120, 504]
    /// Width-to-height ratios: 16:9, 9:16, 1:1, 1:4.
    static let aspectRatios: [Double] = [16.0 / 9.0, 9.0 / 16.0, 1, 1.0 / 4.0]

    private static func drawnRect(side: Double, aspect: Double) -> CGRect {
        VideoBadgeLayout.imageRect(
            imageSize: CGSize(width: aspect * 1000, height: 1000),
            in: CGSize(width: side, height: side),
            allowsUpscaling: true
        )
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    @Test(
        "The frame follows the documented formula in both coordinate orientations (FR-415, FR-416)",
        arguments: VideoBadgeLayoutTests.viewSides, VideoBadgeLayoutTests.aspectRatios
    )
    func formula(side: Double, aspect: Double) throws {
        let rect = Self.drawnRect(side: side, aspect: aspect)
        let metrics = VideoBadgeLayout.thumbnail
        let long = Double(max(rect.width, rect.height))
        let short = Double(min(rect.width, rect.height))
        let diameter = min(
            Self.clamp(long * metrics.diameterRatio, metrics.minDiameter, metrics.maxDiameter),
            short * 0.5
        )
        let margin = min(Self.clamp(long * metrics.marginRatio, metrics.minMargin, metrics.maxMargin), short * 0.25)

        let unflipped = try #require(VideoBadgeLayout.badgeFrame(imageRect: rect, metrics: metrics, flipped: false))
        #expect(abs(Double(unflipped.width) - diameter) < 1e-9)
        #expect(abs(Double(unflipped.height) - diameter) < 1e-9)
        #expect(abs(Double(unflipped.minX) - (Double(rect.maxX) - margin - diameter)) < 1e-9)
        #expect(abs(Double(unflipped.minY) - (Double(rect.minY) + margin)) < 1e-9)

        let flipped = try #require(VideoBadgeLayout.badgeFrame(imageRect: rect, metrics: metrics, flipped: true))
        #expect(abs(Double(flipped.minX) - Double(unflipped.minX)) < 1e-9)
        #expect(abs(Double(flipped.minY) - (Double(rect.maxY) - margin - diameter)) < 1e-9)
    }

    @Test(
        "The badge stays inside the drawn frame and covers at most 20% of it (SC-239, EC-286)",
        arguments: VideoBadgeLayoutTests.viewSides, VideoBadgeLayoutTests.aspectRatios
    )
    func insideAndSmall(side: Double, aspect: Double) throws {
        let rect = Self.drawnRect(side: side, aspect: aspect)
        for flipped in [false, true] {
            let frame = try #require(
                VideoBadgeLayout.badgeFrame(imageRect: rect, metrics: .thumbnail, flipped: flipped)
            )
            #expect(rect.contains(frame))
            let circleArea = Double.pi * Double(frame.width * frame.width) / 4
            #expect(circleArea <= 0.2 * Double(rect.width * rect.height))
            #expect(frame.width <= min(rect.width, rect.height) / 2 + 1e-9)
        }
    }

    @Test(
        "Videos between 1:2 and 2:1 get a diameter within 10–40 pt when the view side is at least 40 pt (SC-240)",
        arguments: VideoBadgeLayoutTests.viewSides, [0.5, 9.0 / 16.0, 1, 16.0 / 9.0, 2]
    )
    func diameterBounds(side: Double, aspect: Double) throws {
        let rect = Self.drawnRect(side: side, aspect: aspect)
        let frame = try #require(VideoBadgeLayout.badgeFrame(imageRect: rect, metrics: .thumbnail, flipped: false))
        #expect(frame.width >= 10 - 1e-9)
        #expect(frame.width <= 40 + 1e-9)
    }

    @Test("Representative values from plan.md")
    func representativeValues() throws {
        let cases: [(side: Double, aspect: Double, diameter: Double)] = [
            (40, 16.0 / 9.0, 10), (120, 16.0 / 9.0, 24), (504, 16.0 / 9.0, 40),
            (40, 0.25, 5), (120, 0.25, 15), (504, 0.25, 40),
        ]
        for item in cases {
            let rect = Self.drawnRect(side: item.side, aspect: item.aspect)
            let frame = try #require(VideoBadgeLayout.badgeFrame(imageRect: rect, metrics: .thumbnail, flipped: false))
            #expect(abs(Double(frame.width) - item.diameter) < 1e-9, "\(item)")
        }
    }

    @Test("The list icon gets an 8 pt badge at its bottom-right corner (FR-418)")
    func listIcon() throws {
        let rect = CGRect(x: 0, y: 0, width: 16, height: 16)
        let frame = try #require(VideoBadgeLayout.badgeFrame(imageRect: rect, metrics: .listIcon, flipped: false))
        #expect(frame == CGRect(x: 8, y: 0, width: 8, height: 8))
        let flipped = try #require(VideoBadgeLayout.badgeFrame(imageRect: rect, metrics: .listIcon, flipped: true))
        #expect(flipped == CGRect(x: 8, y: 8, width: 8, height: 8))
    }

    @Test("Empty or non-finite rectangles give no frame")
    func invalidRects() {
        let invalid: [CGRect] = [
            .zero,
            CGRect(x: 0, y: 0, width: 0, height: 10),
            CGRect(x: 0, y: 0, width: 10, height: -1),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10),
            CGRect(x: 0, y: 0, width: 10, height: CGFloat.nan),
        ]
        for rect in invalid {
            #expect(VideoBadgeLayout.badgeFrame(imageRect: rect, metrics: .thumbnail, flipped: false) == nil)
        }
    }

    @Test("Upscaling follows FitCalculator, and no upscaling keeps a small image at its size in the center")
    func imageRect() {
        let container = CGSize(width: 16, height: 16)
        let large = CGSize(width: 64, height: 36)
        #expect(
            VideoBadgeLayout.imageRect(imageSize: large, in: container, allowsUpscaling: true)
                == FitCalculator.fit(imageSize: large, in: container)
        )
        #expect(
            VideoBadgeLayout.imageRect(imageSize: large, in: container, allowsUpscaling: false)
                == FitCalculator.fit(imageSize: large, in: container)
        )
        let small = CGSize(width: 12, height: 7)
        #expect(
            VideoBadgeLayout.imageRect(imageSize: small, in: container, allowsUpscaling: true)
                == FitCalculator.fit(imageSize: small, in: container)
        )
        #expect(
            VideoBadgeLayout.imageRect(imageSize: small, in: container, allowsUpscaling: false)
                == CGRect(x: 2, y: 4.5, width: 12, height: 7)
        )
    }

    @Test("Only videos showing a generated frame get a badge (FR-415, FR-417)")
    func isShown() {
        var kinds: [ListItemKind] = [.archive, .folder, .directory, .parent]
        kinds += MediaKind.allCases.map { ListItemKind.media($0) }
        for kind in kinds {
            #expect(VideoBadgeLayout.isShown(kind: kind, showingRepresentativeFrame: false) == false)
            let expected: Bool
            switch kind {
            case .media(.mp4), .media(.mov):
                expected = true
            default:
                expected = false
            }
            #expect(VideoBadgeLayout.isShown(kind: kind, showingRepresentativeFrame: true) == expected)
        }
    }
}
