public struct ThumbnailScroll {
    public static func offsetY(
        itemMinY: Double,
        itemMaxY: Double,
        visibleMinY: Double,
        visibleHeight: Double,
        contentHeight: Double
    ) -> Double {
        let values = [itemMinY, itemMaxY, visibleMinY, visibleHeight, contentHeight]
        guard values.allSatisfy(\.isFinite),
              itemMaxY >= itemMinY,
              visibleHeight > 0,
              contentHeight >= 0 else {
            return visibleMinY.isFinite ? visibleMinY : 0
        }

        let visibleMaxY = visibleMinY + visibleHeight
        guard visibleMaxY.isFinite else {
            return visibleMinY
        }

        let target: Double
        if itemMaxY - itemMinY > visibleHeight {
            target = itemMinY
        } else if itemMinY >= visibleMinY, itemMaxY <= visibleMaxY {
            target = visibleMinY
        } else if itemMinY < visibleMinY {
            target = itemMinY
        } else {
            target = itemMaxY - visibleHeight
        }

        let maximum = max(0, contentHeight - visibleHeight)
        return min(max(0, target), maximum)
    }
}
