# mydns-updater

MyDNS.JPのIPv4通知を管理するDockerコンテナです。複数アカウントに対応し、IP変更時とアカウントごとの定期更新期限に通知します。

## Installation

```sh
git clone https://github.com/Karoeba/mydns-updater.git
cd mydns-updater
cp mydns.conf.example mydns.conf
mkdir -p state
```

mydns.confにMasterID、Password、ログ表示用DOMAINを設定してください。値を引用符で囲まず、キーの前後に空白を入れないでください。

```ini
CHECK_INTERVAL=300
FORCE_UPDATE_INTERVAL=86400

[1]
ID=your-master-id
PASSWORD=your-password
DOMAIN=example.mydns.jp
```

[2]以降を追加すると複数アカウントを使用できます。無効化するときはセクション全体をコメントアウトしてください。

```sh
docker compose up -d --build
docker compose logs -f
```

Synology Container Managerでは、配置先をプロジェクトのパスにしてcompose.yamlを読み込み、構築・開始します。mydns.confとstateフォルダーは起動前に作成してください。

## Timezone (v1.2.0)

mydns.confの最初のアカウントセクションより前に `TZ=Asia/Tokyo` を指定します。省略時は日本時間です。`UTC` や `America/New_York` など、イメージに含まれるzoneinfo名を使用できます。空欄・存在しない名前・ファイルパス等の不正値は日本時間へ戻して警告します。POSIX形式のTZ式は受け付けません。

起動ログの例:

```text
2026-09-13 12:00:00 UTC [STARTUP] MyDNS updater v1.2.0 started: TZ=UTC, CHECK_INTERVAL=300s, FORCE_UPDATE_INTERVAL=86400s
```

設定は各確認周期で再読込します。ログの日時と略称（JST/UTC/EST/EDT等）は指定地域と夏時間に従います。起動ログには実効TZ名も表示します。LAST_UPDATEはUNIX時刻のままで、タイムゾーンを変えても定期更新の判定や保存形式は変わりません。TZを設定ファイルで省略した場合、コンテナ環境変数より既定のAsia/Tokyoが優先されます。

v1.2.0は開発中です。1.1系の稼働環境をそのまま残し、実機検証は別環境で行ってください。本番Composeのイメージタグは1.2.xです。固定コンテナ名が同じため並列の実機検証では名前の変更が必要です。模擬テストは独立したtestサービスなので本番と共存できます。

## Configuration

| 設定 | 既定値 | 範囲 |
| --- | --- | --- |
| CHECK_INTERVAL | 300秒 | 60〜86400秒 |
| FORCE_UPDATE_INTERVAL | 86400秒 | 3600〜604800秒 |

不正値は警告して既定値へ戻します。FORCE_UPDATE_INTERVALがCHECK_INTERVALより短い場合も86400秒へ戻します。確認周期は処理完了後の待機時間です。

IPv4取得先は以下の順です。失敗・不正形式の場合は次を試し、全滅した回は通知も状態変更もしません。

1. https://api.ipify.org
2. https://checkip.amazonaws.com/
3. https://ipv4.ifconfig.me/ip

IP_CHECK_URL1〜3で変更できます。空欄・省略時は各既定URLを使用します。設定は確認周期ごとに再読込され、CRLFにも対応します。

## State

state/state.confは自動管理され、./state:/stateで永続化されます。

```ini
LAST_IPV4=203.0.113.10

[1]
LAST_IPV4=203.0.113.10
LAST_UPDATE=1789200000
```

各アカウントのLAST_IPV4は通知成功IP、LAST_UPDATEは通知成功時のUNIX時刻です。IPが異なるか定期更新期限を迎えると通知し、成功直後にそのアカウントの状態を保存します。失敗時は以前の記録を維持し、次回に再試行します。全体のLAST_IPV4は全アカウントが現在のIPに揃った時点で更新します。

状態欠落・不正なアカウント状態は初回扱いです。構文が壊れた状態ファイルは全体を初期化します。読取不能・保存失敗時は停止します。Composeの再起動設定により再起動するため、障害が続く場合は停止して権限・空き容量を確認してください。

セクション番号は一意の1〜9桁の数字で、状態の識別子です。同じ番号を別アカウントに再利用するときは、停止して該当状態セクションを削除し、初回扱いにしてください。state.confは通知成功の記録であり、DNS応答の検証ではありません。

ログは既定でJSTです。TZの指定で変更できます。IP不変・期限前は通知ログが出なくても正常です。

## Upgrade from v1.0.0

旧版を停止し、INTERVALをCHECK_INTERVALとFORCE_UPDATE_INTERVALに置き換えてください。INTERVALは警告のみで使用しません。stateフォルダーを作成し、更新したCompose構成で再作成します。同じアカウントを更新する旧版と新版を同時稼働させないでください。

## Automated tests

GitHub Actionsで、PR作成・更新時とmainへのpush時に既存のDocker模擬テストを自動実行します。Actionsタブの「Docker tests」から手動実行もできます（mainへの取り込み後）。

PRのChecksで「Alpine mock tests」の成功・失敗を確認できます。実行ログと、生成されたtest-reports（14日間保存）から結果を確認してください。コンテナ起動前に失敗した場合はレポートがないためActionsのログを確認します。

GitHub側の一時的なUbuntu環境でAlpineコンテナを実行します。NASや実アカウントの認証情報は使用しません。実機での起動・MyDNS通信・永続化の確認は別途必要です。自動実行の追加だけでは、テスト失敗時のマージを禁止する設定にはなりません。

## Tests

```sh
mkdir -p tests/reports
docker compose -f tests/compose.yaml run --build --rm test
```

外部通信を無効にしたAlpineコンテナで26項目の模擬テストを実行します。初回のイメージ取得と構築時のcurl・tzdata取得には接続が必要です。成功時はALL TESTS PASSED (26 checks)を表示します。結果はtests/reportsに保存します。curl・時刻・待機・保存失敗を模擬し、1周期ずつ新しいプロセスで状態を再読込します。

DS1522+のContainer Managerで、v1.1.1と修正済みのテスト構成による19項目の合格を2026-09-13に確認しました。実アカウントでの通知成功、JSTログ、状態保存、コンテナ再作成後の状態保持も確認済みです。

Container Managerではプロジェクトのパスをリポジトリ内のtestsフォルダーにし、その中のcompose.yamlを指定してください。tests/reportsは事前に作成します。update.shとDockerfileは1つ上の階層に置きます。本番用のルートcompose.yamlは選びません。

テストのupdate.shは/source/update.shへ個別にマウントし、読み取り専用の/suiteとは分離しています。成功時もコンテナは終了します。途中のFAILEDや保存失敗ログは意図した異常系テストであり、最後のALL TESTS PASSEDを確認してください。

## Security and limitations

mydns.confには認証情報が含まれます。Gitへ追加しないでください。実設定・状態・テスト結果は.gitignoreで除外し、Dockerのビルド送信対象からも除外します。

IPv4のみ対応しています。通知先はhttps://ipv4.mydns.jp/login.htmlです。成功応答と状態保存は別処理なので、その間の停止では再通知が発生し得ます。IPv4取得から通知までの間の回線IP変化を完全には排除できません。1つのstateフォルダーを複数の稼働コンテナで共有しないでください。

## Historical naming and v1.1.1 migration

以下はv1.1.1導入時の記録です。v1.2.0の構成は上のTimezone節を参照してください。

1.1系では、NASフォルダーを `mydns-updater-v1.1.x`、プロジェクト名とコンテナ名を `mydns-updater`、イメージ名を `mydns-updater:1.1.x` に固定します。`1.1.x` は自動更新やワイルドカードではなく固定の名前です。実際の版は起動ログと変更履歴で確認します。

起動時、設定を正常に読み込んだ最初の周期に1回、検証済みの実効値を表示します。

```text
2026-09-12 12:00:00 JST [STARTUP] MyDNS updater v1.1.1 started: CHECK_INTERVAL=300s, FORCE_UPDATE_INTERVAL=86400s
```

IP不変・期限前でも起動ログは表示されます。設定の読込に失敗した場合はエラーを出し、最初に読込が成功した時点で表示します。毎周期のログではありません。

Synologyで既存のmydns-updater-v110から移行する場合:

1. mydns.confとstateフォルダーをバックアップします。
2. 旧プロジェクトを停止してクリーンアップします。データを含むプロジェクト削除は行いません。
3. File Stationで配置フォルダーをmydns-updater-v1.1.xへ変更します。
4. update.shと構成ファイルを新版に置き換えます。mydns.confとstateは保持します。
5. 新しいプロジェクトmydns-updaterを作成し、変更後のフォルダーと新版compose.yamlを指定します。既存の同名コンテナがあれば停止して名前の競合を解消します。
6. 構築・開始し、v1.1.1の起動ログと状態保持を確認します。旧プロジェクトは開始しません。

構成ファイルがContainer Managerによりdocker-compose.ymlとして保存されている場合は、実際にプロジェクトで使用しているYAMLを更新してください。古い構成ファイルを誤って選ばないようにします。

今回の移行ではイメージ名が変わるため構築が必要です。その後update.shだけを差し替える場合は停止・差し替え・開始で反映できます。Dockerfileや依存ソフトを変更した場合は再構築してください。固定イメージタグだけでは稼働中のスクリプトの版を判別できません。

## Version

### v1.2.0 (unreleased)
- 設定ファイルでタイムゾーンを変更可能にし、夏時間と不正値の検証を追加。
- テスト環境も本番Dockerfileから構築し、tzdataを使用。

### v1.1.1
- 起動時に実際のバージョンと確認・強制更新間隔をJSTログへ表示。
- コンテナ名をmydns-updater、イメージタグを1.1.xに固定。
- NASの固定フォルダー名と移行手順を記載。


### v1.1.0
IPv4変更検知、アカウント別の通知IP・成功時刻、強制更新周期、3段フォールバック、設定検証、状態永続化を追加。

### v1.0.0
IPv4通知、複数アカウント、更新間隔設定、Docker Compose対応。

## Disclaimer

This project is an unofficial tool and is not affiliated with, endorsed by, or sponsored by MyDNS.JP.

MyDNS is a trademark or registered trademark of its respective owner.

Docker is a trademark or registered trademark of Docker, Inc. in the United States and/or other countries.

All other product names, trademarks, and registered trademarks are the property of their respective owners.

Use at your own risk.
