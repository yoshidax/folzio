import Foundation
import FolzioCore
import FolzioLocalization
import Testing

@Suite("Core Value Text")
struct CoreTextTests {
    private let ja = LocalizationTestSupport.localizer("ja")
    private let en = LocalizationTestSupport.localizer("en")

    @Test("Search root reasons")
    func searchRoot() {
        let cases: [(SearchRootError, String)] = [
            (.empty, "検索起点ディレクトリを入力してください"),
            (.notAbsolute, "/ または ~ で始まるパスを入力してください"),
            (.notFound, "フォルダが見つかりません"),
            (.notAFolder, "フォルダではありません"),
            (.accessDenied, "フォルダを読み取れません"),
        ]
        for (error, expected) in cases {
            #expect(ja.text(for: error) == expected)
            #expect(!en.text(for: error).isEmpty)
        }
        #expect(ja.text(for: SearchFolderInitialLocationError.noUsableFolder) == "利用できるフォルダが見つかりません")
        #expect(en.text(for: SearchFolderInitialLocationError.noUsableFolder) == "No available folder was found")
    }

    @Test("Zip reasons (all cases)")
    func archiveErrors() {
        let corruptions: [(ArchiveCorruption, String)] = [
            (.cannotStartInflate, "展開を始められません"),
            (.compressedDataDamaged, "圧縮データが壊れています"),
            (.dataTruncated, "項目のデータが途中で終わっています"),
            (.compressedDataTruncated, "圧縮データが途中で終わっています"),
            (.headerDamaged, "項目のヘッダが壊れています"),
            (.invalidOffset, "項目の位置が不正です"),
            (.centralDirectoryTooLarge, "中央ディレクトリが大きすぎます"),
            (.invalidLocation, "項目の場所が不正です"),
            (.entryNotFound, "zip の中に項目が見つかりません"),
            (.sizeMismatch, "項目のサイズが一致しません"),
            (.dataOutsideFile, "項目のデータがファイルの外にあります"),
            (.readCancelled, "読み込みを中止しました"),
            (.readFailed, "zip の読み出しに失敗しました"),
            (.unreadable, "zip を読み込めません"),
        ]
        for (corruption, expected) in corruptions {
            #expect(ja.text(for: corruption) == expected)
            #expect(ja.text(for: ArchiveError.corrupted(corruption)) == "zip を開けません: \(expected)")
            #expect(!en.text(for: corruption).isEmpty)
        }

        #expect(ja.text(for: ArchiveError.notFound) == "zip を開けません: zip ファイルが見つかりません")
        #expect(ja.text(for: ArchiveError.accessDenied) == "zip を開けません: アクセスできません")
        #expect(ja.text(for: ArchiveError.notAZip) == "zip を開けません: zip ファイルとして読めません")
        #expect(ja.text(for: ArchiveError.multiDisk) == "zip を開けません: 分割された zip には対応していません")
        #expect(ja.text(for: ArchiveError.entryEncrypted) == "暗号化されているため表示できません")
        #expect(ja.text(for: ArchiveError.unsupportedMethod(12)) == "対応していない圧縮方式です")
        #expect(ja.text(for: ArchiveError.tooLarge) == "zip の中の画像が大きすぎるため表示できません")
    }

    @Test("Name validation reasons (all cases)")
    func nameValidation() {
        let cases: [(NameValidationFailure, String)] = [
            (.empty, "名前を入力してください"),
            (.forbiddenCharacter, "名前に「/」または「:」は使用できません"),
            (.leadingDot, "名前の先頭に「.」は使用できません"),
            (.duplicate, "同じ名前の項目がすでに存在します"),
            (.becomesPackage, "この名前にするとフォルダがパッケージとして扱われ、表示されなくなります"),
        ]
        for (failure, expected) in cases {
            #expect(ja.text(for: failure) == expected)
            #expect(!en.text(for: failure).isEmpty)
        }
    }

    @Test("File operation failure reasons (all cases)")
    func operationFailures() {
        #expect(ja.text(for: OperationFailureReason.noDestination) == "操作先のフォルダが指定されていません")
        #expect(ja.text(for: OperationFailureReason.destinationNotFound) == "操作先のフォルダが見つかりません")
        #expect(ja.text(for: OperationFailureReason.sourceNotFound) == "対象のファイルが見つかりません")
        #expect(ja.text(for: OperationFailureReason.intoItself)
            == "フォルダを自分自身またはその配下へ移動・コピーすることはできません")
        #expect(ja.text(for: OperationFailureReason.invalidName(.empty)) == "名前を入力してください")
        #expect(ja.text(for: OperationFailureReason.sameNameExists) == "同じ名前の項目があるため中止しました")
        #expect(ja.text(for: OperationFailureReason.sameNameAtDestination)
            == "操作先に同じ名前の項目があるため中止しました")
        #expect(ja.text(for: OperationFailureReason.trashExistingFailed(systemReason: "理由"))
            == "既存の項目をゴミ箱へ移動できませんでした: 理由")
        #expect(ja.text(for: OperationFailureReason.systemFailure(systemReason: "理由")) == "理由")

        for reason: OperationFailureReason in [
            .noDestination, .destinationNotFound, .sourceNotFound, .intoItself,
            .invalidName(.duplicate), .sameNameExists, .sameNameAtDestination,
            .trashExistingFailed(systemReason: "reason"), .systemFailure(systemReason: "reason"),
        ] {
            #expect(!en.text(for: reason).isEmpty)
        }
    }

    @Test("Listing and preview reasons")
    func listingAndPreview() {
        #expect(ja.text(for: ListingFailure.folderNotFound) == "フォルダが見つかりません")
        #expect(ja.text(for: ListingFailure.systemFailure(systemReason: "理由")) == "理由")
        #expect(ja.text(for: ListingFailure.archive(.notAZip)) == "zip を開けません: zip ファイルとして読めません")
        #expect(ja.text(for: PreviewFailure.unreadable) == "ファイルを読み込めません")
        #expect(ja.text(for: PreviewFailure.unsupportedFormat) == "対応していない形式です")
        #expect(ja.text(for: PreviewFailure.corrupted) == "ファイルが壊れています")
        #expect(ja.text(for: PreviewFailure.archive(.entryEncrypted)) == "暗号化されているため表示できません")

        #expect(en.text(for: ListingFailure.folderNotFound) == "Folder not found")
        #expect(en.text(for: PreviewFailure.unreadable) == "Can’t read the file")
        #expect(en.text(for: PreviewFailure.unsupportedFormat) == "Unsupported format")
        #expect(en.text(for: PreviewFailure.corrupted) == "The file is damaged")
    }

    @Test("Kind names and empty states")
    func kindNamesAndEmptyStates() {
        #expect(ja.kindNames == KindNames(folder: "フォルダ", zipArchive: "ZIP アーカイブ"))
        #expect(en.kindNames == KindNames(folder: "Folder", zipArchive: "ZIP archive"))
        #expect(ja.text(.emptyFilterImages) == "画像のみ表示中: 該当するファイルはありません")
        #expect(ja.text(.emptyFilterVideos) == "動画のみ表示中: 該当するファイルはありません")
        #expect(en.text(.emptyFilterImages) == "Showing images only: No matching files")
        #expect(en.text(.emptyFilterVideos) == "Showing videos only: No matching files")
    }

    @Test("Changing kind names does not change Duplicate or Keep Both names (EC-113)")
    func namesDoNotDependOnKindNames() {
        #expect(uniqueName(for: "a.jpg", existingNames: ["a.jpg"]) == "a 2.jpg")
        #expect(uniqueName(for: "a 2.jpg", existingNames: ["a.jpg", "a 2.jpg"]) == "a 3.jpg")
        #expect(uniqueName(for: "photo", existingNames: ["photo"]) == "photo 2")
    }
}
