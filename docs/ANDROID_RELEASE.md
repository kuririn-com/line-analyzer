# ふたりとーく Android 公開準備

## 開発用と公開用

Androidの表示名は「ふたりとーく」。パッケージ名は `com.kuririn.futaritalk` を仮設定しています。最初にPlayへアップロードする前に所有者が確定してください。Playに登録したパッケージ名は後から変更できません。

iOSのInfo.plist、アイコン、署名設定、Codemagicワークフロー、バージョンは変更していません。解析と画面は既存の `lib/main.dart` を使います。Android用の分岐で広告IDと同意処理を追加しています。iOSバナーIDは既存値のままです。

Flutter 3.38.9 / Dart 3.10.8で作業。依存パッケージは既存のpubspec.lockを保持。Androidのcompile/target SDKはFlutterの既定値（この版では36）、min SDKは24（Android 7.0）です。

## 1. テスト用APK

```powershell
flutter pub get --enforce-lockfile
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter build apk --debug --no-pub
```

出力: `build/app/outputs/flutter-apk/app-debug.apk`。debug/profileはGoogle公式Androidテスト広告を使います。本番広告IDを渡してもdebug/profileのApp IDはテスト用に固定されます。リリース用の鍵は作成していません。

既存コードに解析警告（未使用の補助関数1件、非推奨withOpacity等のinfo19件）があります。今回の対象外なのでそのまま残しています。上記のanalyzeはerrorを失敗として扱います。

Android専用のアイコン再生成:

```powershell
dart run flutter_launcher_icons -f flutter_launcher_icons_android.yaml
```

既存iOS用アイコンを素材としてAndroid側だけ生成します。

## 2. Android AdMob（所有者の確認後）

1. AdMobで「ふたりとーく」のAndroidアプリを追加。Play未公開なら未公開として登録します。
2. バナー広告ユニットを作成します。iOSのIDをコピーしないでください。
3. `android/admob.example.json` を `android/admob.json` にコピーし、Android用のApp ID（`~`区切り）とバナーID（`/`区切り）を記入します。
4. AdMobの「プライバシーとメッセージ」で配信対象地域に合うメッセージを設定し、公開します。

Android releaseではUMPの同意情報更新と必要なフォーム表示を待ち、SDKが広告リクエストを許可した場合だけ広告を読み込みます。必要な場合は画面下に「広告のプライバシー設定」を表示し、再選択できます。本番IDと地域設定後に実端末でフォームを再検証してください。debug/profileはテスト広告の動作確認用で、この本番同意フローを実行しません。

App IDはAndroidManifestへ、バナーIDはDartへ、同じJSONから渡します。releaseは未設定・GoogleサンプルID・既存iOS ID・異なる広告主の組合せを拒否します。IDの形式からプラットフォーム自体を判定することはできないため、AdMob画面でAndroid用と確認してください。

## 3. アップロード鍵（所有者の確認後）

既存鍵があればそれを使います。新規生成は所有者に確認してから行ってください。鍵やパスワードをチャットやGitHubへ貼り付ける必要はありません。

`android/key.properties.example` を `android/key.properties` にコピーしてローカルで設定します。Windowsパスは `C:/...` のように `/` を使えます。相対パスはandroidフォルダー基準です。

`key.properties`、`*.jks`、`*.keystore`、`android/admob.json` はGit管理から除外します。releaseにdebug署名を使う代替設定はありません。

## 4. 公開用AAB（上記の設定後）

```powershell
flutter build appbundle --release --dart-define-from-file=android/admob.json
```

出力: `build/app/outputs/bundle/release/app-release.aab`。

広告IDまたは鍵の設定がない場合は意図的に失敗します。ストア用AABがまだない状態でdebug APKをストアへ提出しないでください。

共通pubspecのバージョンはiOSと同じ `1.0.0+4` を保持。Android独自の番号が必要ならビルド時に `--build-name` / `--build-number` を指定できます。Playへの次回アップロードではversionCodeを前回より増やしてください。

## 5. ファイル・権限・データの確認

- `.txt` の読み込みはfile_pickerのAndroid Storage Access Frameworkを使用。選択したファイルのURIを通じて読み込みます。
- ストレージ全体へのアクセス、写真、連絡先の権限は追加していません。主Manifestでは広告通信のINTERNETだけ追加。
- 広告SDKがマージするネットワーク・広告ID等の権限は完成したManifestで確認してください。広告ID利用のPlay申告も確認します。
- 会話テキストをアプリ独自のサーバーへ送信する処理はありません。広告リクエストにも会話テキストは渡していません。
- file_pickerは選択ファイルの一時コピーをアプリのキャッシュに作る場合があります。現状はプラグインの標準動作を維持しています。「会話データを一切保存しない」とは説明しないでください。Androidバックアップは無効化しています。
- 広告SDKによるデータ収集は別に存在します。「データを一切収集しない」とは申告しないでください。

## 6. Play Consoleへの入力準備

公開・内部テストへの配布・課金を伴う登録・利用規約への同意は、所有者に確認してから行います。今回はConsoleへの提出は行っていません。

- 表示名: ふたりとーく
- 説明案: 下記の文面を所有者が確認
- 広告の有無: あり
- アプリアクセス: ログイン不要。架空のLINE txtで解析を確認可能
- カテゴリ、配信対象国、対象年齢、コンテンツレーティング: 所有者が回答
- サポートメール、公開URLのプライバシーポリシー: 所有者の既存情報を確認
- データセーフティ: アプリ本体とGoogle Mobile Ads SDKの双方を確認して回答
- 512×512アイコン、1024×500フィーチャーグラフィック、スマートフォンのスクリーンショットを用意
- 個人アカウントの条件によってクローズドテスト等が必要。Consoleに表示される要件を確認
- 実端末での読み込み、クラウド上のtxt、オフライン、回転、大きい文字、戻る操作、広告・同意フォームを最終確認
- AABの16KBページサイズ対応、対象API要件、Play事前リリースレポートを確認。debug APKが動いたことだけではストア審査完了にはなりません

### ストア説明案

短い説明:

LINEのトーク履歴から、会話の回数や返信ペース、ふたりの特徴を楽しく分析。

詳しい説明:

ふたりとーくは、LINEから書き出したトーク履歴（.txt）を読み込んで、会話の特徴を振り返るアプリです。

総メッセージ数、参加者ごとの返信ペース、よく使う言葉、「好き」や「ありがとう」、深夜の会話、最近のトーク傾向をわかりやすく表示。気になる言葉を指定して調べることもできます。

トーク履歴の解析は端末内で行います。広告の表示には通信を利用します。詳しいデータの取り扱いは公開時のプライバシーポリシーをご確認ください。

診断結果は会話の傾向を楽しむための参考情報です。LINEの公式アプリではありません。

## 参照した公式資料

- [Flutter Android公開手順](https://docs.flutter.dev/deployment/android)
- [AdMob Flutter初期設定](https://developers.google.com/admob/flutter/quick-start)
- [テスト広告](https://developers.google.com/admob/flutter/test-ads)
- [UMP同意処理](https://developers.google.com/admob/flutter/privacy)
- [Androidのファイル選択と権限](https://developer.android.com/training/data-storage/shared/documents-files)
- [Google Mobile Adsのデータ開示](https://developers.google.com/admob/android/privacy/play-data-disclosure)（現在のページは最新SDK向け。実際の固定SDK版と設定を照合）
- [Playアプリ作成](https://support.google.com/googleplay/android-developer/answer/9859152)
- [対象API要件](https://developer.android.com/google/play/requirements/target-sdk)
