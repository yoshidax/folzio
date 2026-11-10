import UniformTypeIdentifiers

public enum ExpectedKind: Sendable, Equatable {
    case image, video, unknown

    public var byteLimit: UInt64 { self == .video ? 4_000_000_000 : 256_000_000 }
    public var timeout: Double { self == .video ? 600 : 60 }
}

public enum ImportPayload: Sendable, Equatable {
    case fileURLs
    case promises([ExpectedKind])
    case imageData([String])
}

public enum ImportPayloadPolicy {
    public static let imageDataTypes = ["public.png", "public.jpeg", "public.tiff"]

    public static func select(
        hasFileURLs: Bool = false, isPhotosDrag: Bool = false, promiseDeclaredTypes: [[String]] = [], imageDataTypes: [[String]] = []
    ) -> ImportPayload? {
        if hasFileURLs && !isPhotosDrag { return .fileURLs }
        if !promiseDeclaredTypes.isEmpty {
            let kinds = promiseDeclaredTypes.compactMap { expectedKind(declaredTypes: $0) }
            if kinds.count == promiseDeclaredTypes.count { return .promises(kinds) }
            return hasFileURLs ? .fileURLs : nil
        }
        if hasFileURLs { return .fileURLs }
        let chosen = imageDataTypes.compactMap { available in Self.imageDataTypes.first { available.contains($0) } }
        return chosen.isEmpty ? nil : .imageData(chosen)
    }

    public static func expectedKind(declaredTypes: [String]) -> ExpectedKind? {
        if declaredTypes.isEmpty { return .unknown }
        var kinds: [ExpectedKind] = []
        for identifier in declaredTypes {
            guard let type = UTType(identifier), type.isDeclared, ![UTType.item, .content, .data, .movie].contains(type) else {
                kinds.append(.unknown)
                continue
            }
            if type.conforms(to: .mpeg4Movie) || type.conforms(to: .quickTimeMovie) { kinds.append(.video) }
            else if isRasterImage(type) { kinds.append(.image) }
        }
        if kinds.contains(.video) { return .video }
        if kinds.contains(.image) { return .image }
        return kinds.contains(.unknown) ? .unknown : nil
    }

    public static func isRasterImage(_ type: UTType) -> Bool {
        let excluded: [UTType] = [.svg, .pdf] + ["com.adobe.encapsulated-postscript", "com.adobe.postscript"].compactMap { UTType($0) }
        return type.conforms(to: .image) && !excluded.contains { type.conforms(to: $0) }
    }
}
