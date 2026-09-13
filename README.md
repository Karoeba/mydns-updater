# mydns-updater

このブランチはv1.2.0の開発版です。公開済みのリリースは [Releases](https://github.com/Karoeba/mydns-updater/releases) を参照してください。

MyDNS.JPのIPv4通知を管理するDockerコンテナです。複数アカウントに対応し、IP変更時とアカウントごとの定期更新期限に通知します。

## Installation

DockerとDocker Composeを使用します。リポジトリを取得するか、GitHubのZIPを展開してください。

```sh
git clone https://github.com/Karoeba/mydns-updater.git
cd mydns-updater
mkdir -p config state
cp mydns.conf.example config/mydns.conf
```

配置する主なファイルは次のとおりです。`config/mydns.conf` は設定例をコピーして作成し、`state/state.conf` は起動後に自動生成されます。

```text
mydns-updater/
├── Dockerfile
├── compose.yaml
├── update.sh
├── mydns.conf.example
├── config/
│   └── mydns.conf
└── state/
    └── state.conf
```

`config/mydns.conf` のID・PASSWORD・DOMAINを自分の設定に変更します。IDはMyDNSのMasterID、PASSWORDはそのパスワード、DOMAINはログ表示用のドメイン名です。3項目すべて必須です。

```ini
# 共通設定はアカウント設定より前に記載してください。

# 更新間隔（秒）
# IPv4確認後の待機時間: 60〜86400（既定値: 300）
CHECK_INTERVAL=300
# 前回の通知成功から再通知するまで: 3600〜604800（既定値: 86400）
FORCE_UPDATE_INTERVAL=86400

# ログ設定
# タイムゾーン（既定値: Asia/Tokyo。例: UTC、America/New_York）
TZ=Asia/Tokyo
# 詳細ログ: 0=無効（既定値）、1=有効
DEBUG=0

# IPv4取得先（任意。空欄・省略時は各標準サービスを使用）
#IP_CHECK_URL1=https://api.ipify.org
#IP_CHECK_URL2=https://checkip.amazonaws.com/
#IP_CHECK_URL3=https://ipv4.ifconfig.me/ip

# アカウント設定（ID・PASSWORD・DOMAINはすべて必須）
# ID: MyDNSのMasterID、PASSWORD: そのパスワード、DOMAIN: ログ表示用
[1]
ID=your-master-id
PASSWORD=your-password
DOMAIN=example.mydns.jp

# 追加する場合は次の4行すべての先頭の#を外してください。
# 無効にする場合はセクション行を含む4行すべてに#を付けてください。
#[2]
#ID=your-second-master-id
#PASSWORD=your-second-password
#DOMAIN=example2.mydns.jp
```

```sh
docker compose up -d --build
docker compose logs -f
```

Synology Container Managerでは、ファイルを配置したフォルダーをプロジェクトのパスにし、ルートの `compose.yaml` を指定して構築・開始します。`config/mydns.conf` と `state` フォルダーは事前に作成してください。配置先の例は `/docker/mydns-updater`、プロジェクト名は `mydns-updater` です。フォルダー名にバージョンを含める必要はありません。

## Configuration

設定ファイルは `config/mydns.conf` です。以下はファイルへの記載順に説明しています。共通設定はすべて最初のアカウント行 `[1]` より前に置いてください。共通設定同士の順番は自由ですが、設定例と揃えると確認しやすくなります。

設定例と同じ大文字のキーと半角の `=` を使い、行頭やキーの前後に空白を入れず、値を引用符で囲まないでください。`#` で始まる行はコメントです。

### 設定一覧

| 設定 | 内容 | 既定値・範囲 |
| --- | --- | --- |
| CHECK_INTERVAL | IPv4確認後の待機時間 | 300秒、60〜86400秒 |
| FORCE_UPDATE_INTERVAL | 前回の通知成功から再通知するまでの時間 | 86400秒、3600〜604800秒 |
| TZ | ログのタイムゾーン | Asia/Tokyo |
| DEBUG | 詳細ログの表示 | 0（無効）、1で有効 |
| IP_CHECK_URL1〜3 | IPv4取得先 | 下記の標準サービス |
| ID | MyDNSのMasterID | アカウントごとに必須 |
| PASSWORD | MasterIDに対応するパスワード | アカウントごとに必須 |
| DOMAIN | ログ表示用のドメイン名 | アカウントごとに必須 |

### 更新間隔

`CHECK_INTERVAL` は各周期の処理が終わってから次のIPv4確認まで待つ秒数です。既定値の300では、処理時間を含めて約5分ごとに確認します。

`FORCE_UPDATE_INTERVAL` はIPが変わらなくても再通知する間隔です。アカウントごとの前回成功時刻から数え、期限を過ぎた次の確認周期で通知します。既定値の86400は24時間です。IPが変わった場合は、この期限を待たずに通知します。

範囲外や数字以外の値は警告して既定値を使用します。`FORCE_UPDATE_INTERVAL` が `CHECK_INTERVAL` より短い場合も86400秒へ戻します。

### ログ設定

`TZ` でログの表示時刻を指定します。日本時間は `Asia/Tokyo`、協定世界時は `UTC`、ニューヨークは `America/New_York` です。時刻の後ろにJST・UTC・EST/EDTなどの略称を表示し、夏時間にも対応します。

省略時はAsia/Tokyo、空欄・不正値は警告してAsia/Tokyoを使用します。コンテナにインストール済みのzoneinfo名を指定してください。絶対パスやPOSIX形式は使用できません。表示時刻を変えても、保存済みの成功時刻と更新期限は変わりません。

通常は起動時のバージョン・実効設定値、通知結果、エラーなどを表示します。IP不変・期限前の周期は、ログが増えなくても正常です。

`DEBUG=1` にすると、IPv4確認開始・取得IP・アカウント番号別の更新理由やスキップ理由も表示します。`DEBUG=0` または省略で無効、不正値は警告して0を使用します。ID・パスワード・認証応答本文は記録しませんが、IPやログ表示用ドメインは表示されます。

### IPv4取得先

通常は変更不要です。次の標準サービスを順に試し、取得失敗・不正なIPv4形式の場合は次へ進みます。すべて失敗した周期は通知も状態変更もしません。

1. `IP_CHECK_URL1`：https://api.ipify.org
2. `IP_CHECK_URL2`：https://checkip.amazonaws.com/
3. `IP_CHECK_URL3`：https://ipv4.ifconfig.me/ip

変更する場合は、設定例の該当行の先頭の `#` を外してURLを書き換えます。空欄・省略時は、その番号の標準サービスを使用します。

### アカウント設定

`[1]`、`[2]` のように、一意の1〜9桁の数字でアカウントを区切り、その下にID・PASSWORD・DOMAINを記載します。DOMAINはログ表示用ですが、省略できません。

アカウントを追加する場合は、セクション行と3項目の4行をまとめて有効にしてください。無効にする場合も4行すべてをコメントアウトします。空行だけではアカウントの区切りになりません。

- 必須項目が不足したアカウントは `CONFIG ERROR` として通知を見送り、ほかの正常なアカウントは処理します。
- セクションの欠落・不正・重複、同じセクション内のアカウント項目の重複、最初のセクションより前のアカウント項目、コメントアウトしたセクション行の下に残った有効な項目は構造エラーです。その周期のIP取得と全通知を見送り、状態を変更しません。

構造エラーは `[CONFIG]` ログに理由を表示します。項目の位置や重複のエラーでは行番号も表示し、設定値は表示しません。修正後は次の確認周期で再開します。

### 設定変更の反映

`config/mydns.conf` を編集して上書きすると、次の確認周期で自動的に読み直します。通常は再起動不要です。反映までの時間は処理時間とCHECK_INTERVALに依存するため、上書き直後に変わるとは限りません。

設定ファイルは読み取り専用で使用し、不正値を既定値に戻す場合もファイル自体は書き換えません。過去の起動ログも、起動時点の値のまま残ります。

この動作にはComposeの `./config:/config:ro` によるフォルダーマウントを使用します。ファイルではなくconfigフォルダー自体を入れ替えた場合は、コンテナの再作成が必要です。

## State

`state/state.conf` は自動管理され、`./state:/state` で永続化されます。

```ini
LAST_IPV4=203.0.113.10

[1]
LAST_IPV4=203.0.113.10
LAST_UPDATE=1789200000
```

アカウント別の `LAST_IPV4` は通知成功IP、`LAST_UPDATE` は成功時のUNIX時刻です。IP変更または更新期限で通知し、成功したアカウントの状態を保存します。失敗時は以前の記録を維持して次回に再試行します。全体の `LAST_IPV4` は全アカウントが現在のIPに揃った時点で更新します。

状態の欠落・不正なアカウント状態は初回扱い、状態ファイルの構文破損は全体を初回扱いにします。読取不能・保存失敗時は停止し、Composeの設定で再起動します。繰り返す場合は権限や空き容量を確認してください。

セクション番号は状態の識別子です。別アカウントに番号を再利用する場合は、コンテナを停止し、該当する状態セクションを削除して初回扱いにしてください。1つのstateフォルダーを複数の稼働コンテナで共有しないでください。

## Upgrade

### From v1.0.0

1. 旧コンテナを停止し、既存の `mydns.conf` をバックアップします。
2. 新版のファイルを配置し、既存設定を `config/mydns.conf` に移します。サンプルで認証情報を上書きしないでください。
3. `INTERVAL` を `CHECK_INTERVAL` と `FORCE_UPDATE_INTERVAL` に置き換え、`state` フォルダーを作成します。旧 `INTERVAL` は警告のみで使用しません。
4. 新版のCompose構成でコンテナを構築・再作成し、起動ログと通知成功を確認します。旧版と新版を同じアカウントで同時稼働させないでください。

Container Managerでは、プロジェクトが実際に使用しているYAMLを更新してください。`docker-compose.yml` として保存されている場合があります。

### Subsequent updates

`config/mydns.conf` と `state` を保持して更新します。`update.sh` だけの変更は停止・上書き・開始で反映できます。Composeのマウント変更は再作成、Dockerfileや依存ソフトの変更は再構築が必要です。

イメージ名は `mydns-updater:local`、コンテナ名は `mydns-updater` に固定します。`local` は手元で構築するイメージの名前で、自動更新を意味しません。実際に動く `update.sh` のバージョンは起動ログで確認してください。

既存環境のフォルダー名を変更する場合は、コンテナを停止し、設定と状態をバックアップしてから、新しい配置先でプロジェクトを再作成してください。イメージ名の変更を反映するときは、新しいCompose構成で構築・再作成します。

## Tests

GitHub ActionsはPR作成・更新時とmainへのpush時に、37項目の模擬テストと3項目の設定再読み込みテストを実行します。Actionsの「Docker tests」から手動実行もできます。結果はPRのChecksとActionsログ、成果物 `test-reports`（14日間保存）で確認できます。コンテナ起動前の失敗ではレポートがない場合があります。

手元で実行する場合：

```sh
mkdir -p tests/reports
docker compose -f tests/compose.yaml run --build --rm test
# Linux Docker host only
sh tests/test-config-reload.sh
```

模擬テストは外部通信を無効にし、実アカウントを使いません。初回のイメージ取得には接続が必要です。結果は `tests/reports` に保存され、成功時は `ALL TESTS PASSED (37 checks)` と表示して終了します。途中の失敗ログは異常系テストに含まれるため、最後の結果を確認してください。

Container Managerでは、プロジェクトのパスを `tests` フォルダーにし、その中の `compose.yaml` を指定します。`tests/reports` を事前に作成し、`update.sh` は1つ上の階層に置いてください。3項目のホスト側テストはこの操作では実行されないため、設定の上書き反映は別途確認します。

v1.1.2ではDS1522+で30項目の合格と、実アカウントの通知・アカウント別定期更新・設定再読み込み・デバッグ切替を確認済みです。統合後のv1.2.0は別途実機確認してください。GitHubのテストだけではNAS上の動作は保証されないため、導入先で起動・通信・状態保持を確認してください。テスト失敗時のマージ禁止には別途リポジトリ設定が必要です。

## Security and limitations

- `mydns.conf` には認証情報が含まれます。Gitへ追加しないでください。実設定・状態・テスト結果はGitとDockerビルドの対象から除外しています。
- IPv4のみ対応し、通知先は `https://ipv4.mydns.jp/login.html` です。状態ファイルは通知成功の記録であり、DNS応答の検証ではありません。
- 通知成功と状態保存の間に停止すると再通知する場合があります。IPv4取得から通知までの間の回線IP変化も完全には排除できません。

変更履歴は [CHANGELOG](CHANGELOG.md) を参照してください。

## Disclaimer

This project is an unofficial tool and is not affiliated with, endorsed by, or sponsored by MyDNS.JP.

MyDNS is a trademark or registered trademark of its respective owner.

Docker is a trademark or registered trademark of Docker, Inc. in the United States and/or other countries.

All other product names, trademarks, and registered trademarks are the property of their respective owners.

Use at your own risk.
