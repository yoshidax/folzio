import Foundation
import FolzioLocalization
import Testing

@Suite("Value Sentences")
struct ValueSentenceTests {
    @Test("Values are inserted verbatim and are not interpreted as format specifiers")
    func valuesAreLiteral() {
        let samples = ["%@", "%d", "{0}", "%1$@", "نص", "טקסט", "100%"]
        for language in LocalizationTestSupport.languages {
            let localizer = LocalizationTestSupport.localizer(language)
            for key in TextKey.allCases where key.arguments.contains(.text) {
                for sample in samples {
                    let values = key.arguments.map { argument -> TextValue in
                        switch argument {
                        case .text: return .text(sample)
                        case .count: return .count(3)
                        case .number: return .number(3)
                        }
                    }
                    let output = localizer.text(key, values)
                    #expect(output.contains(sample), "\(language): \(sample) is not in \(key.rawValue): \(output)")
                }
            }
        }
    }
}
