import Testing
@testable import FolzioCore

@Suite("ThumbnailGridLayout")
struct ThumbnailGridLayoutTests {
    @Test("Never scrolls horizontally for any width, size, or spacing")
    func fitsWithinAvailableWidth() {
        let tolerance = 0.0001
        var firstFailure: String?

        for width in 0...2000 where firstFailure == nil {
            for thumbnailSize in 48...512 where firstFailure == nil {
                for spacing in [0.0, 8.0, 20.0] where firstFailure == nil {
                    let availableWidth = Double(width)
                    let size = Double(thumbnailSize)
                    let layout = ThumbnailGridLayout.columns(
                        availableWidth: availableWidth,
                        thumbnailSize: size,
                        spacing: spacing
                    )
                    let usedWidth = Double(layout.count) * layout.cellWidth
                        + Double(layout.count - 1) * spacing

                    if layout.count < 1
                        || layout.cellWidth < 0
                        || layout.cellWidth > availableWidth + tolerance
                        || usedWidth > availableWidth + tolerance {
                        firstFailure = """
                            width=\(width), thumbnailSize=\(thumbnailSize), spacing=\(spacing), \
                            count=\(layout.count), cellWidth=\(layout.cellWidth), used=\(usedWidth)
                            """
                    }
                }
            }
        }

        #expect(firstFailure == nil, Comment(rawValue: firstFailure ?? ""))
    }

    @Test("Uses one column and shrinks cell width for narrow widths")
    func shrinksSingleCellToFitNarrowWidth() {
        let layout = ThumbnailGridLayout.columns(availableWidth: 10, thumbnailSize: 100, spacing: 20)
        #expect(layout.count == 1)
        #expect(layout.cellWidth == 10)
    }

    @Test("Fits even when spacing exceeds the width")
    func handlesSpacingWiderThanAvailableWidth() {
        let layout = ThumbnailGridLayout.columns(availableWidth: 10, thumbnailSize: 10, spacing: 50)
        #expect(layout.count == 1)
        #expect(layout.cellWidth == 10)
        #expect(Double(layout.count) * layout.cellWidth <= 10)
    }

    @Test("Uses zero cell width for a width of 0 or less")
    func returnsZeroCellWidthForNonPositiveWidth() {
        let zero = ThumbnailGridLayout.columns(availableWidth: 0, thumbnailSize: 100, spacing: 8)
        #expect(zero.count == 1)
        #expect(zero.cellWidth == 0)

        let negative = ThumbnailGridLayout.columns(availableWidth: -50, thumbnailSize: 100, spacing: 8)
        #expect(negative.count == 1)
        #expect(negative.cellWidth == 0)
    }

    @Test("Uses one full-width column for a thumbnail size of 0 or less")
    func returnsFullWidthForNonPositiveThumbnailSize() {
        let zero = ThumbnailGridLayout.columns(availableWidth: 300, thumbnailSize: 0, spacing: 8)
        #expect(zero.count == 1)
        #expect(zero.cellWidth == 300)

        let negative = ThumbnailGridLayout.columns(availableWidth: 300, thumbnailSize: -10, spacing: 8)
        #expect(negative.count == 1)
        #expect(negative.cellWidth == 300)
    }

    @Test("Treats negative spacing as 0")
    func treatsNegativeSpacingAsZero() {
        let layout = ThumbnailGridLayout.columns(availableWidth: 1000, thumbnailSize: 200, spacing: -10)
        #expect(layout.count == 5)
        #expect(layout.cellWidth == 200)
    }

    @Test("Computes the column count including spacing")
    func computesColumnCountWithSpacing() {
        let layout = ThumbnailGridLayout.columns(availableWidth: 1000, thumbnailSize: 200, spacing: 20)
        #expect(layout.count == 4)
        #expect(layout.cellWidth == 200)
        #expect(Double(layout.count) * layout.cellWidth + Double(layout.count - 1) * 20 <= 1000)
    }

    @Test("Uses the maximum column count when the width fits exactly")
    func fitsExactColumns() {
        let layout = ThumbnailGridLayout.columns(availableWidth: 1000, thumbnailSize: 200, spacing: 0)
        #expect(layout.count == 5)
        #expect(layout.cellWidth == 200)
    }

    @Test("Returns safe values for non-finite inputs")
    func handlesNonFiniteValues() {
        let infinity = ThumbnailGridLayout.columns(availableWidth: .infinity, thumbnailSize: 100, spacing: 8)
        #expect(infinity.count == 1)
        #expect(infinity.cellWidth == 0)

        let nan = ThumbnailGridLayout.columns(availableWidth: .nan, thumbnailSize: 100, spacing: 8)
        #expect(nan.count == 1)
        #expect(nan.cellWidth == 0)

        let nanSpacing = ThumbnailGridLayout.columns(availableWidth: 1000, thumbnailSize: 200, spacing: .nan)
        #expect(nanSpacing.count == 5)
        #expect(nanSpacing.cellWidth == 200)
    }
}
