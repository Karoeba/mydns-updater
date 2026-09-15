# MyDNS.JP IPアドレス自動更新ツール

[![Docker tests — main](https://github.com/Karoeba/mydns-updater/actions/workflows/tests.yml/badge.svg?branch=main&event=push)](https://github.com/Karoeba/mydns-updater/actions/workflows/tests.yml?query=branch%3Amain+event%3Apush)

MyDNS.JPへIPv4アドレスを自動通知する軽量な常駐ツールです。複数アカウントに対応し、IPアドレスが変わったときと、アカウントごとの定期更新期限に通知します。

このREADMEではDockerでの導入・運用を説明します。コマンドラインのほか、Synology NASのContainer Managerでも使用できます。

Dockerを使わずに動かす [Linux直接実行版](docs/linux.md) も用意しています。Linux版は実験的な対応で、作者による実機での動作確認はまだ行っていません。

現在はv1.6.0の開発版です。公開済みの版は [Releases](https://github.com/Karoeba/mydns-updater/releases) を参照してください。

## 事前準備

Docker環境を用意し、このリポジトリをクローンするか、使用するブランチのZIPをダウンロードして展開します。既存環境を更新する場合は [Upgrade](#upgrade) を参照してください。

1. 展開先に `config` と `state` フォルダーを用意します。
2. `mydns.conf.example` をコピーし、`config/mydns.conf` として保存します。
3. `accounts.conf.example` をコピーし、`config/accounts.conf` として保存します。
4. `accounts.conf` のID・PASSWORD・DOMAINを自分の情報に変更します。

アカウントには次の3項目を記入します。すべて必須です。

- ID：MyDNSのMasterID
- PASSWORD：MasterIDに対応するパスワード
- DOMAIN：ログ表示用のドメイン名

更新間隔などの共通設定は `mydns.conf` で調整します。

```text
mydns-updater/
├── Dockerfile
├── compose.yaml
├── update.sh
├── mydns.conf.example
├── accounts.conf.example
├── config/
│   ├── mydns.conf
│   └── accounts.conf
└── state/
```

`state/state.conf` は起動後に自動生成されます。設定例は [mydns.conf.example](mydns.conf.example) と [accounts.conf.example](accounts.conf.example) を参照してください。

## 起動方法

準備したファイルを使い、ご利用の環境に合う方法で起動します。

### 汎用Docker環境

Docker Composeを使用します。初回の設定ファイル作成をコマンドで行う場合は、展開先で次を実行します。

```sh
mkdir -p config state
cp mydns.conf.example config/mydns.conf
cp accounts.conf.example config/accounts.conf
```

すでに設定済みの場合はコピーせず、そのファイルを使用してください。アカウント情報の記入を終えたら、同じディレクトリで起動します。

```sh
docker compose up -d --build
docker compose logs -f
```

起動ログのバージョンと通知結果を確認します。初回はイメージの構築が必要です。

### Synology NAS（Container Manager）

1. File Stationで、`docker` 共有フォルダー内に `mydns-updater` フォルダーを作ります。
2. 上記のフォルダー構成を保って、プログラムと設定ファイルをアップロードします。
3. Container Managerの「プロジェクト」から「作成」を開きます。
4. プロジェクト名を `mydns-updater`、パスを作成したフォルダーにします。
5. 配置済みの `compose.yaml` を指定し、画面の案内に従って構築・開始します。
6. コンテナの「ログ」で、起動バージョンと通知結果を確認します。

配置先の例は `/docker/mydns-updater` です。フォルダー名にバージョンを含める必要はありません。

### Dockerを使わずに実行する場合

[Linux直接実行の導入・運用手順](docs/linux.md) を参照してください。

## Configuration

共通設定は `config/mydns.conf`、アカウント設定は `config/accounts.conf` に記載します。以下は設定例の順番に説明しています。

各ファイル内の設定の順番は自由ですが、アカウント項目は対応するセクション行の下に置いてください。

設定例と同じ大文字のキーと半角の `=` を使い、行頭やキーの前後に空白を入れず、値を引用符で囲まないでください。`#` で始まる行はコメントです。

### 設定一覧

| 設定 | 内容 | 既定値・範囲 |
| --- | --- | --- |
| **共通設定（mydns.conf）** | | |
| CHECK_INTERVAL | IPv4確認後の待機時間 | 300秒、60〜86400秒 |
| FORCE_UPDATE_INTERVAL | 前回の通知成功から再通知するまでの時間 | 86400秒、3600〜604800秒 |
| TZ | ログのタイムゾーン | Asia/Tokyo |
| DEBUG | 詳細ログの表示 | 0（無効）、1で有効 |
| IP_CHECK_URL1〜3 | IPv4取得先 | 下記の標準サービス |
| **アカウント設定（accounts.conf）** | | |
| ID | MyDNSのMasterID | アカウントごとに必須 |
| PASSWORD | MasterIDに対応するパスワード | アカウントごとに必須 |
| DOMAIN | ログ表示用のドメイン名 | アカウントごとに必須 |

### 更新間隔

`CHECK_INTERVAL` は各周期の処理が終わってから次のIPv4確認まで待つ秒数です。既定値の300では、処理時間を含めて約5分ごとに確認します。

`FORCE_UPDATE_INTERVAL` はIPが変わらなくても再通知する間隔です。アカウントごとの前回成功時刻から数え、期限を過ぎた次の確認周期で通知します。

既定値の86400は24時間です。IPが変わった場合は、この期限を待たずに通知します。

範囲外や数字以外の値は警告して既定値を使用します。`FORCE_UPDATE_INTERVAL` が `CHECK_INTERVAL` より短い場合も86400秒へ戻します。

### ログ設定

`TZ` でログの表示時刻を指定します。日本時間は `Asia/Tokyo`、協定世界時は `UTC`、ニューヨークは `America/New_York` です。

時刻の後ろにJST・UTC・EST/EDTなどの略称を表示し、夏時間にも対応します。

省略時はAsia/Tokyo、空欄・不正値は警告してAsia/Tokyoを使用します。コンテナにインストール済みのzoneinfo名を指定してください。

絶対パスやPOSIX形式は使用できません。表示時刻を変えても、保存済みの成功時刻と更新期限は変わりません。

通常は起動時のバージョン・実効設定値、通知結果、エラーなどを表示します。IP不変・期限前の周期は、ログが増えなくても正常です。

`DEBUG=1` にすると、IPv4確認開始・取得IP・アカウント番号別の更新理由やスキップ理由も表示します。`DEBUG=0` または省略で無効、不正値は警告して0を使用します。

ID・パスワード・認証応答本文は記録しませんが、IPやログ表示用ドメインは表示されます。

### IPv4取得先

通常は変更不要です。次の標準サービスを順に試し、取得失敗・不正なIPv4形式の場合は次へ進みます。

すべて失敗した周期は通知も状態変更もしません。

1. `IP_CHECK_URL1`：https://api.ipify.org
2. `IP_CHECK_URL2`：https://checkip.amazonaws.com/
3. `IP_CHECK_URL3`：https://ipv4.ifconfig.me/ip

変更する場合は、設定例の該当行の先頭の `#` を外してURLを書き換えます。空欄・省略時は、その番号の標準サービスを使用します。

### アカウント設定

`config/accounts.conf` に記載します。共通設定をこのファイルに入れたり、アカウント設定を `mydns.conf` に残したりしないでください。

`[1]`、`[2]` のように、一意の1〜9桁の数字でアカウントを区切り、その下にID・PASSWORD・DOMAINを記載します。DOMAINはログ表示用ですが、省略できません。

アカウントを追加する場合は、セクション行と3項目の4行をまとめて有効にしてください。無効にする場合も4行すべてをコメントアウトします。

空行だけではアカウントの区切りになりません。

- 必須項目が不足したアカウントは `CONFIG ERROR` として通知を見送り、ほかの正常なアカウントは処理します。
- セクションの欠落・不正・重複、同じセクション内のアカウント項目の重複、最初のセクションより前のアカウント項目、コメントアウトしたセクション行の下に残った有効な項目は構造エラーです。その周期のIP取得と全通知を見送り、状態を変更しません。

どちらかのファイルが読めない場合や、設定先の間違い・未対応のキーがある場合も、その周期のIP取得と全通知を見送ります。旧形式を自動的に読み込む互換処理はありません。

構造エラーは `[CONFIG]` ログにファイル名と理由を表示します。項目の位置や重複のエラーでは行番号も表示し、設定値は表示しません。

修正後は次の確認周期で再開します。

### 設定変更の反映

`config/mydns.conf` または `config/accounts.conf` を編集して上書きすると、次の確認周期で自動的に読み直します。通常は再起動不要です。

反映までの時間は処理時間とCHECK_INTERVALに依存するため、上書き直後に変わるとは限りません。

2つのファイルをまとめて変更する場合、個別のアップロードは一括処理ではありません。途中の組み合わせで動かしたくない場合は停止・両ファイルの更新・開始の順に操作してください。

設定ファイルは読み取り専用で使用し、不正値を既定値に戻す場合もファイル自体は書き換えません。過去の起動ログも、起動時点の値のまま残ります。

この動作にはComposeの `./config:/config:ro` によるフォルダーマウントを使用します。ファイルではなくconfigフォルダー自体を入れ替えた場合は、コンテナの再作成が必要です。

## Logs

### エラーと復旧

通常ログ（DEBUG=0）にも、初回の失敗・原因変更・重要度の段階変更・復旧を表示します。同じ失敗の繰り返しはDEBUG=1でのみ表示します。

起動・通知成功は従来どおり表示します。

| 段階 | 通信障害の判定 |
| --- | --- |
| FIRST | 最初の失敗。次の対象周期で再試行 |
| PERSISTENT | 3回以上連続して失敗し、初回から10分以上経過 |
| PROLONGED | 未復旧のまま初回から1時間以上経過 |
| RECOVERED | 対象の処理が成功。回数と継続秒数を表示 |

段階の判定はその対象を実際に試した時点で行います。設定エラーや認証・アクセス拒否など確認が必要な失敗は初回からERROR、状態保存など継続不能な失敗はFATALとして終了します。

IP取得先ごとの失敗は代替取得先があるためWARNに留め、全取得先の失敗はIP_CHECKとして別に段階判定します。試していない取得先を復旧扱いにはしません。

IP取得先はIP_CHECK_URL1〜3、MyDNS通知はアカウント番号とログ表示用DOMAINで識別します。curl終了コード・HTTPステータス・固定の原因コードと対処の目安を表示し、URL全文、認証情報、応答本文は記録しません。

HTTP 200でも成功応答がなければSUCCESS_NOT_CONFIRMEDとし、認証失敗と断定しません。

失敗履歴は実行中の一時領域に保持し、再起動でリセットします。タイムゾーンや日時変更による誤判定を避けるため、継続時間はシステムの経過時間で測ります。

接続先やアカウント設定が変わった場合も対象の履歴をリセットします。アカウント削除や、IPが戻るなどして通知が不要になった場合は履歴を解除し、通信成功による復旧とは区別して表示します。

通知成功記録のstate.conf形式と更新・再試行間隔は変更しません。429のRetry-Afterに合わせた待機は、この版には含めません。

## Healthcheck

定期処理が停止していないかを、DockerのHealthcheckで確認します。付属のCompose設定を使用すると有効になります。Synology Container Managerも同じ設定を使用します。

起動直後は `starting`、確認に成功すると `healthy`、失敗が続くと `unhealthy` になります。30秒ごとに確認し、起動猶予30秒、確認の制限時間5秒、3回連続失敗で異常と判定します。

確認対象はプロセスの存在と処理の進行です。待機時間・通信の制限時間に120秒の余裕を加えて期限を判定します。MyDNS.JPへの通知成功やDNS応答を保証するものではなく、通信・設定エラーがあっても処理が続いていれば正常と判定します。

追加の外部通信は行いません。`unhealthy` だけでは自動再起動しないため、異常時はログを確認してください。

Dockerの確認例：

```sh
docker inspect --format '{{json .State.Health}}' mydns-updater
```

Linux直接実行での確認方法は [Linux導入手順](docs/linux.md) を参照してください。

## State

`state/state.conf` は自動管理され、`./state:/state` で永続化されます。

```ini
LAST_IPV4=203.0.113.10

[1]
LAST_IPV4=203.0.113.10
LAST_UPDATE=1789200000
```

アカウント別の `LAST_IPV4` は通知成功IP、`LAST_UPDATE` は成功時のUNIX時刻です。IP変更または更新期限で通知し、成功したアカウントの状態を保存します。

失敗時は以前の記録を維持して次回に再試行します。全体の `LAST_IPV4` は全アカウントが現在のIPに揃った時点で更新します。

状態の欠落・不正なアカウント状態は初回扱い、状態ファイルの構文破損は全体を初回扱いにします。読取不能・保存失敗時は停止し、Composeの設定で再起動します。

繰り返す場合は権限や空き容量を確認してください。

セクション番号は状態の識別子です。別アカウントに番号を再利用する場合は、コンテナを停止し、該当する状態セクションを削除して初回扱いにしてください。

1つのstateフォルダーを複数の稼働コンテナで共有しないでください。

## Upgrade

### From v1.5.0

設定とstateを保持し、`update.sh` と `compose.yaml` を更新してコンテナを再作成します。Healthcheck設定の追加は、スクリプトの上書きと再起動だけでは反映されません。

Container Managerではプロジェクトで使用中のYAMLにも変更を反映してください。Dockerfileの変更はないため、イメージの再構築は不要です。

### From v1.4.0

設定・stateを保持し、上記のv1.5.0からの手順と同様にスクリプト・Compose設定を更新してコンテナを再作成します。

### From v1.1.x–v1.3.0

1. コンテナを停止し、既存の `config/mydns.conf` と `state` をバックアップします。
2. 既存の `mydns.conf` からアカウントのセクション行・ID・PASSWORD・DOMAINを `config/accounts.conf` へ移します。無効にしているアカウントのコメントも一緒に移します。
3. `config/mydns.conf` には共通設定だけを残します。更新間隔などは現在の値を引き継いでください。
4. `update.sh` を新版へ上書きして開始します。既存のフォルダーマウント構成なら、再構築・再作成は不要です。
5. 起動ログのバージョン、設定エラーがないこと、次の更新成功を確認します。

アカウント番号と `state/state.conf` を保持すれば、成功時刻と更新期限を引き継ぎます。サンプルを実設定に上書きしないでください。

切り戻す場合は停止し、旧スクリプトとバックアップした旧設定を戻して開始します。

### From v1.0.0

1. 旧コンテナを停止し、既存の `mydns.conf` をバックアップします。
2. 新版のファイルを配置し、共通設定を `config/mydns.conf`、アカウント設定を `config/accounts.conf` に分けて移します。サンプルで認証情報を上書きしないでください。
3. `INTERVAL` を `CHECK_INTERVAL` と `FORCE_UPDATE_INTERVAL` に置き換え、`state` フォルダーを作成します。旧 `INTERVAL` は警告のみで使用しません。
4. 新版のCompose構成でコンテナを構築・再作成し、起動ログと通知成功を確認します。旧版と新版を同じアカウントで同時稼働させないでください。

Container Managerでは、プロジェクトが実際に使用しているYAMLを更新してください。`docker-compose.yml` として保存されている場合があります。

### Subsequent updates

`config` と `state` を保持して更新します。`update.sh` だけの変更は停止・上書き・開始で反映できます。

Composeのマウント変更は再作成、Dockerfileや依存ソフトの変更は再構築が必要です。

イメージ名は `mydns-updater:local`、コンテナ名は `mydns-updater` に固定します。`local` は手元で構築するイメージの名前で、自動更新を意味しません。

実際に動く `update.sh` のバージョンは起動ログで確認してください。

既存環境のフォルダー名を変更する場合は、コンテナを停止し、設定と状態をバックアップしてから、新しい配置先でプロジェクトを再作成してください。イメージ名の変更を反映するときは、新しいCompose構成で構築・再作成します。

## Tests

GitHub Actionsで、Docker（Alpine）とLinux直接実行（Ubuntu）の模擬テストを行っています。実際のMyDNS.JPへの通知や、導入先での継続動作は別途確認します。

自動テストの内容と実機での確認方法は [テスト手順](docs/testing.md) を参照してください。

## Security and limitations

- `accounts.conf` に認証情報を保存します。Gitには設定例だけを掲載し、実設定は追加しないでください。旧形式の認証情報が残る可能性も考慮し、`mydns.conf` も引き続きGitから除外します。両ファイルの実設定・状態・テスト結果はDockerビルドにも含めません。認証情報ファイルへのアクセスは必要な利用者に限定してください。
- IPv4のみ対応し、通知先は `https://ipv4.mydns.jp/login.html` です。状態ファイルは通知成功の記録であり、DNS応答の検証ではありません。
- 通知成功と状態保存の間に停止すると再通知する場合があります。IPv4取得から通知までの間の回線IP変化も完全には排除できません。

変更履歴は [CHANGELOG](CHANGELOG.md) を参照してください。

## 開発について

ChatGPTを活用して開発しています。

## Disclaimer

This project is an unofficial tool and is not affiliated with, endorsed by, or sponsored by MyDNS.JP.

MyDNS is a trademark or registered trademark of its respective owner.

Docker is a trademark or registered trademark of Docker, Inc. in the United States and/or other countries.

All other product names, trademarks, and registered trademarks are the property of their respective owners.

Use at your own risk.
