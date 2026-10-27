public struct ThumbnailGridLayout {
    public static func columns(availableWidth: Double, thumbnailSize: Double, spacing: Double) -> (count: Int, cellWidth: Double) {
        guard availableWidth.isFinite, thumbnailSize.isFinite,
              availableWidth > 0, thumbnailSize > 0 else {
            let width = availableWidth.isFinite ? max(0, availableWidth) : 0
            return (1, width)
        }

        let spacing = spacing.isFinite ? max(0, spacing) : 0
        let rawCount = ((availableWidth + spacing) / (thumbnailSize + spacing)).rounded(.down)
        let count = max(1, Int(min(rawCount, 9_007_199_254_740_992.0)))
        let availablePerCell = (availableWidth - Double(count - 1) * spacing) / Double(count)

        return (count, max(0, min(thumbnailSize, availablePerCell)))
    }
}
