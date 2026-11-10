import Testing
@testable import FolzioCore

@Suite("Import payload policy")
struct ImportPayloadPolicyTests {
    @Test func priorityAndTypes() {
        #expect(ImportPayloadPolicy.select(hasFileURLs: true, promiseDeclaredTypes: [["com.adobe.pdf"]], imageDataTypes: [["public.png"]]) == .fileURLs)
        #expect(ImportPayloadPolicy.select(promiseDeclaredTypes: [["public.jpeg"]], imageDataTypes: [["public.png"]]) == .promises([.image]))
        #expect(ImportPayloadPolicy.select(imageDataTypes: [["public.tiff", "public.jpeg", "public.png"], ["public.tiff", "public.jpeg"], ["public.tiff"]]) == .imageData(["public.png", "public.jpeg", "public.tiff"]))
        #expect(ImportPayloadPolicy.select(imageDataTypes: [["public.heic", "public.url"]]) == nil)
        #expect(ImportPayloadPolicy.select() == nil)
    }

    @Test func promiseConformance() {
        for type in ["public.png", "public.jpeg", "public.heic", "org.webmproject.webp", "com.compuserve.gif"] {
            #expect(ImportPayloadPolicy.expectedKind(declaredTypes: [type]) == .image)
        }
        for type in ["public.mpeg-4", "com.apple.quicktime-movie"] {
            #expect(ImportPayloadPolicy.expectedKind(declaredTypes: [type]) == .video)
        }
        for types in [[], ["public.data"], ["public.item"], ["public.movie"], ["unregistered.test-format"]] {
            #expect(ImportPayloadPolicy.expectedKind(declaredTypes: types) == .unknown)
        }
        for type in ["com.adobe.pdf", "public.svg-image", "public.plain-text", "public.avi"] {
            #expect(ImportPayloadPolicy.expectedKind(declaredTypes: [type]) == nil)
        }
        #expect(ImportPayloadPolicy.expectedKind(declaredTypes: ["com.adobe.pdf", "public.png"]) == .image)
        #expect(ImportPayloadPolicy.expectedKind(declaredTypes: ["public.jpeg", "public.mpeg-4"]) == .video)
        #expect(ImportPayloadPolicy.select(promiseDeclaredTypes: [["com.adobe.pdf"]], imageDataTypes: [["public.png"]]) == nil)
    }
}


extension ImportPayloadPolicyTests {
    @Test(arguments: ["com.apple.quicktime-movie", "public.mpeg-4", "public.jpeg", "public.heic"])
    func photosDragPrefersUsablePromises(type: String) {
        let kind = ImportPayloadPolicy.expectedKind(declaredTypes: [type])!
        #expect(ImportPayloadPolicy.select(hasFileURLs: true, isPhotosDrag: true,
            promiseDeclaredTypes: [[type]], imageDataTypes: [["public.jpeg"]]) == .promises([kind]))
        #expect(ImportPayloadPolicy.select(hasFileURLs: true,
            promiseDeclaredTypes: [[type]], imageDataTypes: [["public.jpeg"]]) == .fileURLs)
    }

    @Test func photosDragWithoutUsablePromisesKeepsFileURLs() {
        #expect(ImportPayloadPolicy.select(hasFileURLs: true, isPhotosDrag: true) == .fileURLs)
        #expect(ImportPayloadPolicy.select(hasFileURLs: true, isPhotosDrag: true,
            promiseDeclaredTypes: [["com.adobe.pdf"]]) == .fileURLs)
        #expect(ImportPayloadPolicy.select(isPhotosDrag: true, promiseDeclaredTypes: [["com.adobe.pdf"]],
            imageDataTypes: [["public.png"]]) == nil)
    }
}
