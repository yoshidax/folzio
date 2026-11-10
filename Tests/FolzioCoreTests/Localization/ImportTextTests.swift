import FolzioCore
import FolzioLocalization
import Testing

@Suite("Import localized text")
struct ImportTextTests {
    @Test func receivingText() {
        let ja = LocalizationTestSupport.localizer("ja")
        let en = LocalizationTestSupport.localizer("en")
        #expect(ja.importedImageNamePrefix == "画像")
        #expect(en.importedImageNamePrefix == "Image")
        #expect(ja.cancelReceivingTitle == "受け取りを取り消す")
        #expect(en.receivingCancelTitle == "Cancel")
        #expect(ja.receivingStageText(isChecking: true) == "確認中")
        #expect(en.receivingStageText(isChecking: false) == "Receiving")
        #expect(ja.receivingProgressText(total: 2, completed: 1, size: "5 MB") == "受け取り中…（2 件中 1 件、5 MB）")
        #expect(en.receivingProgressText(total: 2, completed: 1, size: "5 MB") == "Receiving… (1 of 2, 5 MB)")
    }

    @Test func failuresInBothLanguages() {
        let ja = LocalizationTestSupport.localizer("ja")
        let en = LocalizationTestSupport.localizer("en")
        for seconds in [60, 600] {
            #expect(ja.text(for: ImportRejection.timedOut(seconds: seconds)) == "\(seconds) 秒以内に書き出されませんでした")
            #expect(en.text(for: ImportRejection.timedOut(seconds: seconds)) == "Not provided within \(seconds) seconds")
        }
        for failure in [ImportRejection.notImageOrVideo, .unsupportedImageFormat, .unsupportedVideoFormat, .notRegularFile, .tooLarge(limit: 256_000_000), .tooLarge(limit: 4_000_000_000), .tooManyPixels, .sourceFailed] {
            #expect(!ja.text(for: failure).isEmpty)
            #expect(!en.text(for: failure).isEmpty)
            #expect(ja.text(for: OperationFailureReason.importRejected(failure)) == ja.text(for: failure))
        }
        #expect(ja.text(for: ImportRejection.tooLarge(limit: 256_000_000)) == "256 MB を超えるため保存できません")
        #expect(en.text(for: ImportRejection.tooLarge(limit: 4_000_000_000)) == "Larger than 4 GB")
    }
}
