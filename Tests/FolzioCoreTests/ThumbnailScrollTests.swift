import Testing
@testable import FolzioCore

@Suite("ThumbnailScroll")
struct ThumbnailScrollTests {
    @Test("Scrolls minimally for an item below the viewport")
    func scrollsDownToItemBelowViewport() {
        let offset = ThumbnailScroll.offsetY(
            itemMinY: 120,
            itemMaxY: 220,
            visibleMinY: 0,
            visibleHeight: 100,
            contentHeight: 500
        )
        #expect(offset == 120)
        #expect(offset != 0)
    }

    @Test("Aligns an item above the viewport to the top")
    func scrollsUpToItemAboveViewport() {
        let offset = ThumbnailScroll.offsetY(
            itemMinY: 30,
            itemMaxY: 80,
            visibleMinY: 40,
            visibleHeight: 100,
            contentHeight: 500
        )
        #expect(offset == 30)
    }

    @Test("Scrolls until an item whose lower part is visible is fully visible")
    func scrollsDownForPartiallyVisibleItem() {
        let offset = ThumbnailScroll.offsetY(
            itemMinY: 80,
            itemMaxY: 130,
            visibleMinY: 0,
            visibleHeight: 100,
            contentHeight: 500
        )
        #expect(offset == 30)
    }

    @Test("Scrolls until an item whose upper part is visible is fully visible")
    func scrollsUpForPartiallyVisibleItem() {
        let offset = ThumbnailScroll.offsetY(
            itemMinY: 20,
            itemMaxY: 60,
            visibleMinY: 40,
            visibleHeight: 100,
            contentHeight: 500
        )
        #expect(offset == 20)
    }

    @Test("Does not scroll when the item is already fully visible")
    func keepsOffsetForVisibleItem() {
        let offset = ThumbnailScroll.offsetY(
            itemMinY: 30,
            itemMaxY: 80,
            visibleMinY: 0,
            visibleHeight: 100,
            contentHeight: 500
        )
        #expect(offset == 0)
    }

    @Test("Clamps to the maximum scroll position at the end")
    func clampsAtBottom() {
        let offset = ThumbnailScroll.offsetY(
            itemMinY: 190,
            itemMaxY: 220,
            visibleMinY: 0,
            visibleHeight: 100,
            contentHeight: 200
        )
        #expect(offset == 100)
    }

    @Test("Clamps to 0 at the start")
    func clampsAtTop() {
        let offset = ThumbnailScroll.offsetY(
            itemMinY: 0,
            itemMaxY: 40,
            visibleMinY: 70,
            visibleHeight: 100,
            contentHeight: 200
        )
        #expect(offset == 0)
    }

    @Test("Aligns the top of an item taller than the viewport")
    func alignsTopForTallerItem() {
        let offset = ThumbnailScroll.offsetY(
            itemMinY: 10,
            itemMaxY: 310,
            visibleMinY: 0,
            visibleHeight: 100,
            contentHeight: 400
        )
        #expect(offset == 10)
    }

    @Test("Returns the current origin for invalid dimensions")
    func returnsCurrentOriginForInvalidValues() {
        #expect(ThumbnailScroll.offsetY(
            itemMinY: 10,
            itemMaxY: 20,
            visibleMinY: 5,
            visibleHeight: 0,
            contentHeight: 100
        ) == 5)
        #expect(ThumbnailScroll.offsetY(
            itemMinY: 10,
            itemMaxY: 20,
            visibleMinY: 5,
            visibleHeight: -1,
            contentHeight: 100
        ) == 5)
        #expect(ThumbnailScroll.offsetY(
            itemMinY: 10,
            itemMaxY: 20,
            visibleMinY: 5,
            visibleHeight: Double.nan,
            contentHeight: 100
        ) == 5)
        #expect(ThumbnailScroll.offsetY(
            itemMinY: 10,
            itemMaxY: 20,
            visibleMinY: 5,
            visibleHeight: 100,
            contentHeight: .infinity
        ) == 5)
        #expect(ThumbnailScroll.offsetY(
            itemMinY: 10,
            itemMaxY: 20,
            visibleMinY: 5,
            visibleHeight: 100,
            contentHeight: -1
        ) == 5)
    }
}
