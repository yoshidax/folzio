import Foundation

/// File-system checks belong off the UI thread. The result applies to the entire selection.
public enum InternalDropValidation {
    public enum Kind: Sendable { case move, copy }
    public enum Result: Equatable, Sendable {
        case valid, empty, missingSource, invalidDestination, sameParent, intoItself, overlappingSources
    }

    public static func validate(sources: [URL], destination: URL, kind: Kind) -> Result {
        guard !sources.isEmpty else { return .empty }
        let fm = FileManager.default
        var destinationIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &destinationIsDirectory),
              destinationIsDirectory.boolValue else { return .invalidDestination }
        let destinationPath = canonical(destination)
        var sourcePaths: Set<String> = []
        var directoryPaths: Set<String> = []
        for source in sources {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else { return .missingSource }
            let sourcePath = canonical(source)
            guard sourcePaths.insert(sourcePath).inserted else { return .overlappingSources }
            if isDirectory.boolValue { directoryPaths.insert(sourcePath) }
            if case .move = kind, canonical(source.deletingLastPathComponent()) == destinationPath {
                return .sameParent
            }
            if isDirectory.boolValue {
                if destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath == "/" ? "/" : sourcePath + "/") {
                    return .intoItself
                }
            }
        }
        for path in sourcePaths {
            var parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            while parent != "/" {
                if directoryPaths.contains(parent) { return .overlappingSources }
                let next = URL(fileURLWithPath: parent).deletingLastPathComponent().path
                guard next != parent else { break }
                parent = next
            }
            if path != "/", directoryPaths.contains("/") { return .overlappingSources }
        }
        return .valid
    }

    private static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
