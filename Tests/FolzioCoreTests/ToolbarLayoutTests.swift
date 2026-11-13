import FolzioCore
import Testing

@Suite("Toolbar Layout")
struct ToolbarLayoutTests {
    @Test("The default order lists the eight button sets, a flexible space, and the name filter field at the right end")
    func defaultOrderMatchesApprovedOrder() {
        #expect(ToolbarLayout.defaultOrder == [
            "history", "paneLayout", "slideshow", "previewZoom",
            "mediaTypeFilter", "zipVisibility", "viewMode", "thumbnailSize",
            "NSToolbarFlexibleSpaceItem", "nameFilter",
        ])
    }

    @Test("Every set appears once in the default order, and the default order is allowed")
    func defaultOrderCoversEverySet() {
        #expect(Set(ToolbarLayout.setIdentifiers) == Set(ToolbarLayout.defaultOrder).subtracting([
            ToolbarLayout.flexibleSpaceIdentifier,
        ]))
        #expect(ToolbarLayout.defaultOrder.allSatisfy(ToolbarLayout.allowed.contains))
        #expect(ToolbarLayout.normalized(saved: ToolbarLayout.defaultOrder) == ToolbarLayout.defaultOrder)
    }

    @Test("A saved order from before the name filter field existed is kept, without adding the field (FR-393)")
    func olderSavedOrderDoesNotGainNameFilter() {
        let saved = [
            "thumbnailSize", "history", "paneLayout", "slideshow", "previewZoom",
            "mediaTypeFilter", "zipVisibility", "viewMode", "NSToolbarFlexibleSpaceItem",
        ]
        #expect(ToolbarLayout.normalized(saved: saved) == saved)
    }

    @Test("A saved order with the name filter field is kept, and a repeated field keeps its first occurrence")
    func savedOrderWithNameFilter() {
        let saved = ["nameFilter", "history", "NSToolbarFlexibleSpaceItem"]
        #expect(ToolbarLayout.normalized(saved: saved) == saved)
        #expect(ToolbarLayout.normalized(saved: ["history", "nameFilter", "nameFilter"]) == ["history", "nameFilter"])
    }

    @Test("A valid saved order is kept as it is")
    func keepsValidOrder() {
        let saved = ["thumbnailSize", "history", "NSToolbarSpaceItem", "paneLayout", "NSToolbarFlexibleSpaceItem"]
        #expect(ToolbarLayout.normalized(saved: saved) == saved)
    }

    @Test("A set the user removed stays removed")
    func keepsRemovedSets() {
        let saved = ["history", "viewMode"]
        #expect(ToolbarLayout.normalized(saved: saved) == saved)
    }

    @Test("Space items may repeat")
    func keepsRepeatedSpaces() {
        let saved = ["history", "NSToolbarSpaceItem", "NSToolbarSpaceItem", "NSToolbarFlexibleSpaceItem", "viewMode"]
        #expect(ToolbarLayout.normalized(saved: saved) == saved)
    }

    @Test("An order with an unknown identifier is broken and gives the default order")
    func unknownIdentifierGivesDefaultOrder() {
        #expect(ToolbarLayout.normalized(saved: ["history", "futureItem", "viewMode"]) == ToolbarLayout.defaultOrder)
        #expect(ToolbarLayout.normalized(saved: ["unknown", "history"]) == ToolbarLayout.defaultOrder)
    }

    @Test("A repeated button set keeps only its first occurrence")
    func dropsRepeatedSets() {
        let saved = ["history", "viewMode", "history", "viewMode"]
        #expect(ToolbarLayout.normalized(saved: saved) == ["history", "viewMode"])
    }

    @Test("An empty order stays empty, because the user may remove every set")
    func keepsEmptyOrder() {
        #expect(ToolbarLayout.normalized(saved: [String]()).isEmpty)
    }

    @Test("A missing value and values of other types give the default order")
    func invalidValuesGiveDefaultOrder() {
        #expect(ToolbarLayout.normalized(saved: nil) == ToolbarLayout.defaultOrder)
        #expect(ToolbarLayout.normalized(saved: "history") == ToolbarLayout.defaultOrder)
        #expect(ToolbarLayout.normalized(saved: 42) == ToolbarLayout.defaultOrder)
        #expect(ToolbarLayout.normalized(saved: ["history", 1] as [Any]) == ToolbarLayout.defaultOrder)
    }

}
