# Folzio 開発・検証ガイド

[English](development.md) | 日本語 · [README に戻る](../README.ja.md)

ソースからのビルド、テスト、検証用フォルダ、構成の詳細をまとめています。
コマンドはリポジトリのルートで実行してください。

Swift 6 + AppKit のみで実装し、外部パッケージに依存しません。Swift Package 構成で、Xcode プロジェクトは不要です。
アプリはネットワーク API（`URLSession` / `Network` / `NWConnection`）を使用しません。

アプリを試すには「[.app として起動](#app-として起動)」の手順を使います。

## 動作環境

- macOS 15 以降
- Xcode（Swift 6 ツールチェーン）。`swift --version` が 6.0 以上であること
- `xcode-select -p` が `/Applications/Xcode.app/Contents/Developer` を指していること

```bash
xcode-select -p
swift --version
```

## 起動

### .app として起動

```bash
scripts/make-app.sh
open .build/Folzio.app
```

`scripts/make-app.sh` は release ビルドを行い、`.build/Folzio.app` を組み立てて ad-hoc 署名します。
TCC の許可は Folzio アプリに紐づきます。初回に許可ダイアログが出たら「許可」してください。

### 開発中の起動（ターミナル）

```bash
swift run FolzioApp
```

ターミナルを占有します。終了は ⌘Q または Ctrl-C。TCC（デスクトップ・書類・ダウンロードへのアクセス許可）は
ターミナルに紐づきます。

## ビルドと自動テスト

```bash
swift build
swift test
```

- `swift test` は `FolzioCoreTests`（Core のロジック・異常系・FSEvents）と
  `FolzioPerformanceTests`（性能基準）を実行します
- 個別に実行する場合:

```bash
swift test --filter FolzioCoreTests
swift test --filter FolzioPerformanceTests
```

- ネットワーク非依存の確認:

```bash
scripts/check-no-network.sh
```

## 検証用フォルダの準備

フィクスチャの生成には `cwebp` / `img2webp`（Homebrew の `webp` パッケージ）を使用します。
アプリ本体のビルドと実行には不要です。

```bash
scripts/make-fixtures.sh ~/FolzioFixtures
```

次のフォルダが生成されます（スクリプトは毎回作り直します）。

| フォルダ | 内容 |
|----------|------|
| `mixed/` | JPEG・PNG・アニメーション GIF・静止/アニメーション WebP・mp4・mov・.txt・.pdf・サブフォルダ・隠しファイル |
| `slideshow/` | スライドショー用（画像3件・GIF・1秒/10秒動画・非対応 .txt・サブフォルダ・zip。WebP と隠しファイルは `mixed/` で確認） |
| `broken/` | 破損 JPEG、中身が PNG の `.jpg`、0 バイトの `.mp4` |
| `huge/` | 10,000 個の小さな JPEG |
| `bigimage/` | 1 億画素級の PNG |
| `ops/` | コピー・移動・名前変更などの検証用（`a.jpg`、`b.png`、`c 2.jpg`、`dest/`、`album/`） |
| `folders/` | ファイルリストのフォルダの検証用（`trip/day1/`・`day2/`、空のフォルダ、隠しフォルダ、パッケージ、名前が `.zip` のフォルダ） |
| `zoom/` | プレビューの拡大・縮小の検証用（16×16・1×1 の PNG、6000×4000 の JPEG、1200×2400 の縦長 PNG） |

WebP フィクスチャは `cwebp` / `img2webp` で生成し、`Sources/FixtureKit/Resources/` に同梱しています。
生成し直す場合:

```bash
scripts/make-webp-fixtures.sh
```

## 手動での動作確認

`scripts/make-fixtures.sh` で生成したフォルダを使って、次の点を確認します。

1. **閲覧**: `mixed/` を開き、7 件のメディアだけが並ぶこと。↓ でプレビューが追従し、GIF が動くこと。
   アニメーション WebP は再生されるか先頭フレームで表示されること。
2. **動画**: mp4 が自動再生・ループすること。設定で自動再生をオフにすると先頭フレームで止まること。
   画像へ移ると音声込みで停止すること。
3. **表示形式**: ⌘1 / ⌘2 で形式を切り替えても選択が維持されること。サムネイルの折り返しが追従し、
   横スクロールバーが出ないこと。再起動で表示形式・サイズ・最後のフォルダが復元されること。
4. **ファイル操作**: `ops/` でコピー・移動・複製・名前変更・ゴミ箱・D&D を確認すること。
   同名衝突で「置き換える／両方残す／中止」が出ること。
5. **フルスクリーン**: 画像のダブルクリック／⌃⌘F で全画面になり、Esc で 3 ペインに戻ること。
6. **ペイン幅**: 仕切りを端までドラッグしても各ペインが最小幅（160 / 240 / 320pt）で止まること。
   仕切りのダブルクリックで折りたたまれないこと。
7. **キーボードのみ**: Tab でツリー → リスト → プレビュー、矢印で選択、⌃⌘F → Esc を完了できること。
8. **異常系**: `broken/` でクラッシュしないこと。権限のないフォルダで「アクセスできません」が出ること。
   外部からファイルを追加・削除して一覧が更新されること。
9. **スライドショー**: `slideshow/mixed/` を開き、⇧⌘S で開始すること。設定した間隔（既定3秒）ごとに画像・動画・GIF が表示順に進み、
   動画は再生されたまま切り替わること。設定ウインドウで間隔を 10 秒にすると送りが 10 秒ごとになり、不正な値は直前の有効値に戻ること。
   繰り返しをオフにすると末尾の表示から間隔の後に終了し、Esc と同じ復帰になること。4種類の効果が自動送りだけに付き、
   効果の途中の矢印・Esc が待たされないこと。「視差効果を減らす」でスライド・ズームがクロスフェードになること。
   矢印で移動すると期限が設定した間隔でやり直しになり、Esc で元のペイン・幅・フォーカスへ戻ること。
   1件だけのフォルダでは同じ対象のまま期限だけがやり直すこと（繰り返しオフなら間隔の後に終了）。開始・終了だけでは動画が止まらないこと
   （復帰先がファイルリストのみ表示の場合は停止・消音）。フルスクリーンから開始し、Esc で復帰すると元のウインドウ状態に戻ること。
   検索やフォルダ移動でスライドショーが終了すること。
10. **アクセシビリティ**: Accessibility Inspector で各ビューのラベルを確認すること。

## プロジェクト構成

```text
Package.swift
Sources/
  FolzioCore/        # AppKit を import しないロジック層
    Model/                # MediaFile / FolderNode / FileOperation など
    Browser/              # BrowserModel（状態と非同期処理の調停）
    FileSystem/           # ディレクトリ列挙、ボリューム、FSEvents 監視
    Imaging/              # デコード、サムネイル、LRU キャッシュ
    Layout/               # フィット計算、サムネイル列計算
    Operations/           # 名前検証、ファイル操作サービス
    Settings/             # UserDefaults による設定
  FolzioLocalization/ # 表示文言と地域書式
  FolzioApp/         # AppKit UI（描画と入力）
    App/                  # 起動、メインウインドウ、メニュー、3 ペイン
    Tree/                 # ディレクトリツリー
    FileList/             # リスト／サムネイル／コンテキストメニュー
    Preview/              # 画像・動画プレビュー
    Operations/           # 確認・衝突ダイアログ、実行コーディネータ
    Settings/             # 設定ウインドウ
  FixtureKit/             # テスト用メディア生成（画像・GIF・WebP・動画）
  make-fixtures/          # フィクスチャ生成 CLI
Tests/
  FolzioCoreTests/         # Swift Testing
  FolzioPerformanceTests/  # 性能基準
scripts/
  make-app.sh              # .app の組み立てと署名
  make-icon.sh             # アプリアイコンの生成
  make-fixtures.sh         # フィクスチャ生成
  make-webp-fixtures.sh    # 同梱 WebP の再生成
  check-no-archive-writes.sh # アーカイブコードで書き込み API を使わないことの確認
  check-no-network.sh      # ネットワーク API 非依存の確認
  check-readme-sync.sh     # README.md と README.ja.md の同期の確認
```

設計上のルール:

- `FolzioCore` は AppKit を import しません。判断ロジックは Core、描画と入力は App に置きます
- デコード・ディレクトリ列挙・ファイル操作は UI スレッドで行いません
- Core のロジックと異常系には Swift Testing のテストを付けます

## トラブルシューティング

- **ウインドウが出ない／メニューだけ表示される**: 古いプロセスが残っていないか確認し、終了してから再起動します。

  ```bash
  pgrep -fl Folzio
  scripts/make-app.sh
  open .build/Folzio.app
  ```

  ターミナルから直接実行すると、起動時のエラーがそのまま表示されます。

  ```bash
  .build/Folzio.app/Contents/MacOS/Folzio
  ```

- **ファイルが見えない**: システム設定 → プライバシーとセキュリティ → ファイルとフォルダ で、
  起動方法に応じてターミナルまたは Folzio にアクセスを許可してください。
- **フィクスチャ生成に失敗する**: `cwebp` / `img2webp` が見つからない場合は `brew install webp` を実行してください。
- **性能テストが失敗する**: `Tests/FolzioPerformanceTests` の基準値を確認してください。他の負荷が高い状態では一時的に超えることがあります。
