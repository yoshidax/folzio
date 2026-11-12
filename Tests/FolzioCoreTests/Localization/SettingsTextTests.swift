import Foundation
import FolzioLocalization
import Testing

@Suite("Settings Window Text")
struct SettingsTextTests {
    @Test("Preview interaction options are available in both languages")
    func previewInteractionOptions() {
        let ja = LocalizationTestSupport.localizer("ja")
        let en = LocalizationTestSupport.localizer("en")
        #expect(ja.text(.settingsPreview) == "プレビュー")
        #expect(ja.text(.settingsPreviewInteraction) == "画像の操作")
        #expect(ja.text(.settingsPreviewWheelPan) == "ホイールズームとドラッグ")
        #expect(ja.text(.settingsPreviewScroll) == "スクロール")
        #expect(en.text(.settingsPreview) == "Preview")
        #expect(en.text(.settingsPreviewInteraction) == "Image interaction")
        #expect(en.text(.settingsPreviewWheelPan) == "Wheel zoom and drag")
        #expect(en.text(.settingsPreviewScroll) == "Scroll")
    }
    @Test("The confirmation checkbox and its note are separate sentences in both languages (FR-223)")
    func confirmationCheckboxAndNote() {
        let ja = LocalizationTestSupport.localizer("ja")
        let en = LocalizationTestSupport.localizer("en")

        #expect(ja.text(.settingsConfirm) == "コピー・ゴミ箱に入れる・お気に入りから削除する前に確認する")
        #expect(ja.text(.settingsConfirmNote) == "名前の変更・移動と、ツリーのフォルダをゴミ箱に入れる操作は、この設定に関わらず常に確認します")
        #expect(en.text(.settingsConfirm) == "Confirm before copying, moving to the Trash, or removing from Favorites")
        #expect(en.text(.settingsConfirmNote) == "Renaming, moving, and moving folders in the directory tree to the Trash are always confirmed, regardless of this setting")
    }

    @Test("The confirmation checkbox no longer carries the always-confirmed operations in parentheses")
    func confirmationCheckboxHasNoParenthesizedNote() {
        for language in LocalizationTestSupport.languages {
            let text = LocalizationTestSupport.localizer(language).text(.settingsConfirm)
            #expect(!text.contains("（") && !text.contains("("), "\(language): \(text)")
        }
    }
}
