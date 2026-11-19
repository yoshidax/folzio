import Foundation
import FolzioLocalization
import Testing

@Suite("Settings Window Text")
struct SettingsTextTests {
    @Test("Favorites restoration is described in both languages")
    func favoritesRestoration() {
        let ja = LocalizationTestSupport.localizer("ja")
        let en = LocalizationTestSupport.localizer("en")
        #expect(ja.text(.settingsFavorites) == "お気に入り")
        #expect(ja.text(.settingsRestoreFavoritesExpansion) == "起動時に前回の開閉状態を復元する")
        #expect(en.text(.settingsFavorites) == "Favorites")
        #expect(en.text(.settingsRestoreFavoritesExpansion) == "Restore previous expansion state on launch")
    }

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
    @Test("Each operation has its own confirmation checkbox (FR-223)")
    func confirmationCheckboxes() {
        let ja = LocalizationTestSupport.localizer("ja")
        let en = LocalizationTestSupport.localizer("en")

        #expect(ja.text(.settingsConfirmCopy) == "コピーする前に確認する")
        #expect(ja.text(.settingsConfirmMove) == "移動する前に確認する")
        #expect(ja.text(.settingsConfirmRename) == "名前を変更する前に確認する")
        #expect(ja.text(.settingsConfirmRemoveFavorite) == "お気に入りから削除する前に確認する")
        #expect(ja.text(.settingsConfirmTrash) == "ゴミ箱に入れる前に確認する")
        #expect(en.text(.settingsConfirmCopy) == "Confirm before copying")
        #expect(en.text(.settingsConfirmMove) == "Confirm before moving")
        #expect(en.text(.settingsConfirmRename) == "Confirm before renaming")
        #expect(en.text(.settingsConfirmRemoveFavorite) == "Confirm before removing from Favorites")
        #expect(en.text(.settingsConfirmTrash) == "Confirm before moving to the Trash")
    }

    @Test("The confirmation checkboxes do not carry the always-confirmed operation in parentheses")
    func confirmationCheckboxesHaveNoParenthesizedNote() {
        let keys: [TextKey] = [
            .settingsConfirmCopy, .settingsConfirmMove, .settingsConfirmRename, .settingsConfirmRemoveFavorite,
            .settingsConfirmTrash,
        ]
        for language in LocalizationTestSupport.languages {
            for key in keys {
                let text = LocalizationTestSupport.localizer(language).text(key)
                #expect(!text.contains("（") && !text.contains("("), "\(language): \(text)")
            }
        }
    }
}
