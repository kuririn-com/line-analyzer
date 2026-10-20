# Android検証記録（2026年10月20日）

基準コミット: `f586cad` / 作業ブランチ: `android/prepare-play-release`

| 確認項目 | 結果 |
| --- | --- |
| Flutter / Dart | 3.38.9 / 3.10.8 |
| Android開発環境 | SDK 36、Java 21、ライセンス受諾済み |
| Android debug APK | ビルド成功・エミュレーターへインストール成功 |
| 端末 | Pixel_7 AVD、Android 16 / API 36、x86_64 |
| 標準ファイル選択 | アプリからDocumentsUIを開き、Downloadsのtxtを選択して成功 |
| 実際の解析 | 架空の日本語LINE履歴で8件・参加者2人を表示 |
| 標準ファイル選択の取消 | DocumentsUIから戻った後、読み込みボタンが有効に復帰することを実機操作相当で確認 |
| 画面 | 既存の緑・ピンクのデザイン、診断・基本集計・参加者表示・52px広告枠を確認 |
| 自動テスト | 11件成功（広告ID分離4、同意処理4、txt取込・取消・失敗3） |
| 静的解析 | errorなし。既存warning1件・info19件を保持 |
| iOS保護 | ios/、codemagic.yaml、pubspec.yaml、pubspec.lockに差分なし。WindowsではiOSビルド未実施 |
| 既存ローカル | C:/Users/reo11/line_analyzerは変更せず、別のコピーで作業 |
| 公開用AAB | Android広告App ID未設定のため意図した検証エラーで停止。作成・提出なし |
| 公開・費用 | Play Consoleの操作、課金、アップロード鍵の新規生成は未実施 |

## 完成APKの実測設定

- パッケージ: `com.kuririn.futaritalk`（初回Playアップロード前に所有者の確定が必要）
- 表示名: ふたりとーく
- バージョン: 1.0.0 / versionCode 4
- min SDK 24 / target SDK 36 / compile SDK 36
- ABI: armeabi-v7a、arm64-v8a、x86_64
- Android App ID: Google公式Androidテスト用 `ca-app-pub-3940256099942544~3347511713`
- バナー: Google公式Androidテスト用 `ca-app-pub-3940256099942544/6300978111`
- バックアップ: 無効
- ストレージ・写真・連絡先の権限: なし
- INTERNET、ACCESS_NETWORK_STATE、AD_ID、ACCESS_ADSERVICES_AD_ID / ATTRIBUTION / TOPICS、WAKE_LOCK、FOREGROUND_SERVICE、アプリ内receiver保護用permissionを確認。広告SDKとその依存ライブラリがマージする権限を含む。WAKE_LOCKはmeasurement/WorkManager、FOREGROUND_SERVICEはWorkManager由来

## 残っている確認

テストバナーの画像表示は未確認です。SDKは読み込みエラー0（JavascriptEngineを取得できない）を返しました。エミュレーター側のGoogle Playサービス等でも `Trust anchor for certification path not found`、ChromiumのSSL `net_error -202` が出ています。この証拠から、環境の証明書・HTTPS通信の問題が関係していると考えられます。アプリの証明書検証は緩和していません。証明書の正常な環境または実機で広告表示を再確認してください。

ビルド用Javaでも初回にHTTPS証明書エラーがありました。Windowsの信頼済み公開ルート証明書を作業領域内の一時ストアにコピーし、その実行に限って使って解消しました。PCのシステム証明書、JDK本体、リポジトリのHTTPS設定は変更していません。この一時ストアはソースに含めていません。

実機、Google Drive等のクラウドのtxt、release広告IDでのUMPフォーム、署名済みAAB、16KBページ端末、Play事前リリースレポートは今後の確認対象です。

次に必要なのはAndroid用AdMobのApp ID・バナーIDと、所有者が確認したアップロード鍵です。手順は [Android公開準備](ANDROID_RELEASE.md) にまとめています。
