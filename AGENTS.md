# AGENTS.md

Folzio は Swift 6・AppKit・SwiftPM で作る、ネイティブ macOS（15 以降、Apple silicon）向けの画像・動画ブラウザ。
外部依存はなく、ネットワークにアクセスしない。セットアップと構成は `docs/development.md`、
ユーザーから見た現在の動作は `docs/usage.md` を参照する。

## コマンド

- ビルド: `swift build`
- テストゲート: `swift test --no-parallel --skip FolzioPerformanceTests`
- 1 つのスイート: `swift test --filter <SuiteName>`
- 性能テストは単独で実行する: `swift test --filter FolzioPerformanceTests`。
  デコード・キャッシュ・ディレクトリ列挙・プレビューの切り替えに関わる変更では実行し、結果を報告する
- ガードレール: `scripts/check-no-network.sh`、`scripts/check-no-archive-writes.sh`、`scripts/check-readme-sync.sh`
- アプリの起動: `scripts/make-app.sh && open .build/Folzio.app`

## 作業の範囲

- Issue が求めることだけを実装する。求められていない機能・設定項目・抽象化・依存は加えない
- Issue が動作を決めていない点は、既存の動作に最も近い方を選び、置いた仮定を最後の報告に列挙する

## 設計

- 状態と判断ロジックは `FolzioCore` に置き、AppKit を import しない。描画と入力は `FolzioApp`（AppKit）が扱う。
  新しいロジックは UI なしでテストできるよう Core に置く
- デコード・ディレクトリ列挙・ファイル操作はメインスレッド以外で行う
- デコード済み画像のキャッシュには明示的なメモリ上限を設ける
- `Sources/FolzioCore/Archive` のコードは zip を読むだけにする
- `Sources` にある URL リテラルは `AboutInfo.swift` のリポジトリへのリンクだけ。アプリは通信を開始しない

## ユーザーのファイル

- ユーザーのファイルは、ユーザーの明示的な操作があったときだけ変更する。破壊的な操作はゴミ箱へ移すか、実行前に確認する
- 非対応のファイルや壊れたファイルは、ユーザーに分かるメッセージを出し、アプリは動作を続ける

## キーボードとアクセシビリティ

- 新しい操作には、キーボードから実行できる手段（ショートカット、またはフォーカスできるコントロール）を用意する
- 新しい UI 要素にはアクセシビリティラベルを付ける

## AppKit の不変条件（起動不能の事故から）

- `NSSplitViewController` では `splitView(_:constrainMinCoordinate:ofSubviewAt:)`・
  `splitView(_:constrainMaxCoordinate:ofSubviewAt:)`・`splitView(_:shouldCollapseSubview:forDoubleClickOnDividerAt:)`
  をデフォルトのまま使う。override すると Auto Layout と両立せず、起動時に例外になる
- ペインの最小幅は `NSSplitViewItem.minimumThickness` で守る。`canCollapse` は隠すペインだけ `true` にし、
  `isCollapsed` を設定する前に `true` にしておく。それ以外のペインは `false` のままにする
- 制約は、対象ビューを `addSubview` した後に有効化し、同じ view hierarchy のアンカー同士だけで張る
- ウインドウの表示と `contentViewController` の設定は MainActor で行う

## ローカライズ

- ユーザーに見える文字列はすべて `Sources/FolzioLocalization/TextKey.swift` の `TextKey` にする
- キーは `en.lproj` と `ja.lproj` の両方に追加する（`Localizable.strings`。数を含む文字列は `.stringsdict` にも）

## テスト

- Swift Testing（`import Testing`、`@Test`、`#expect`）を使う
- Core のロジックと異常系は `FolzioCoreTests`、AppKit の振る舞いは `FolzioAppTests` に置く
- テストで使うメディアは `FixtureKit` で生成する
- バグ修正には、そのバグを再現するテストを含める
- 異常系の入力（破損・非対応・巨大・読み取り権限のないファイル）をテストする

## 完了の条件

次のすべてを満たしたら完了とする。

1. `swift build`、テストゲート、変更したファイルに関係するすべてのガードレールが通る
2. アプリが起動し、3 つのペインが表示される。起動コマンドと確認する点を保守者に示し、
   保守者が確認するまで GUI の動作は未確認として報告する

同じ原因の失敗を 3 回直しても解決しなければ、作業を止めて状況を報告する。ツールの導入・更新は保守者に確認する。

## ドキュメント・コミット・Git

- 英語と日本語のドキュメントは対になっている（`README.md` / `README.ja.md`、`docs/*.md` / `docs/*.ja.md`）。
  両方を同じ変更で編集し、見出し・リスト・表・コードブロックを揃える
- コードのコメントは英語で書く
- コミットメッセージは Conventional Commits（`feat:`、`fix:`、`docs:`、`chore:`）に従い、Issue キーがあれば付ける: `(TAK-5)`
- push は作業ブランチにだけ行い、push 済みの履歴はそのまま保つ。PR は依頼されたときだけ作る
