public enum MemoryLimits {
    public static let previewCacheBytes = 256 * 1024 * 1024
    public static let thumbnailCacheBytes = 128 * 1024 * 1024
    /// Maximum inflated size for one image entry inside a zip (research.md R24)
    public static let archiveImageBytes = 512 * 1024 * 1024
    /// Total size of inflated chunks cached for ranged reads of videos inside a zip (research.md R25)
    public static let archiveStreamCacheBytes = 32 * 1024 * 1024
}
