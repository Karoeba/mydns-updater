# Linuxで直接実行する

Dockerを使わず、同じupdate.shを実行できます。必要なものはPOSIX sh、curl、CA証明書、tzdata、awkなどの標準コマンド、およびLinuxの/procです。以下はUbuntu/Debianとsystemdを使用する例です。ARM機での実機確認は別途必要です。Healthcheckは含みません。

## この手順での配置

| ファイル | 配置先 |
| --- | --- |
| update.sh | /usr/local/lib/mydns-updater/update.sh |
| mydns.conf・accounts.conf | /etc/mydns-updater/ |
| state.conf（自動生成） | /var/lib/mydns-updater/ |

## 1. 準備と模擬テスト

使用する版のリポジトリをクローンするか、ZIPを展開し、そのディレクトリで実行します。nanoを使う場合は、未導入ならエディターもインストールしてください。

```sh
sudo apt update
sudo apt install curl ca-certificates tzdata nano
sh tests/test-linux.sh
```

最後に `ALL LINUX TESTS PASSED (8 checks)` と出れば成功です。テストは一時ディレクトリ内で模擬通信を使い、実アカウントや既存設定には触れません。Dockerもroot権限も不要です。

## 2. 配置する

```sh
getent passwd mydns-updater >/dev/null || sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin mydns-updater
sudo install -d -m 755 /usr/local/lib/mydns-updater
sudo install -m 644 update.sh /usr/local/lib/mydns-updater/update.sh
sudo install -d -o root -g mydns-updater -m 750 /etc/mydns-updater
sudo install -d -o mydns-updater -g mydns-updater -m 700 /var/lib/mydns-updater
```

次のコピーは初回のみです。既存設定がある場合は上書きせず、その設定を使用してください。

```sh
sudo install -o root -g mydns-updater -m 640 mydns.conf.example /etc/mydns-updater/mydns.conf
sudo install -o root -g mydns-updater -m 640 accounts.conf.example /etc/mydns-updater/accounts.conf
sudo nano /etc/mydns-updater/mydns.conf
sudo nano /etc/mydns-updater/accounts.conf
```

共通設定と、各アカウントのID・PASSWORD・DOMAINを記入します。rootだけが編集し、実行ユーザーmydns-updaterは読める権限です。同じ実アカウントをDocker側と同時に動かさないでください。試験用アカウントを使うか、実通知の確認中だけ既存側を停止します。

## 3. サービスとして開始する

```sh
sudo install -m 644 deploy/linux/mydns-updater.service /etc/systemd/system/mydns-updater.service
sudo systemctl daemon-reload
sudo systemctl start mydns-updater
sudo systemctl status mydns-updater --no-pager
sudo journalctl -u mydns-updater -n 50 --no-pager
```

起動バージョン、通知成功、/var/lib/mydns-updater/state.confの生成を確認してください。DEBUG=1なら周期ごとの確認やスキップもログで確認できます。

## 4. 設定上書きと再起動を確認する

/etc/mydns-updater/mydns.confのDEBUGを変更して保存し、次の確認周期のログを確認します。設定を変更するだけならサービス再起動は不要です。アップロードで置き換える場合は、ファイルの所有者・グループ・権限も維持してください。

```sh
sudo journalctl -u mydns-updater -f
```

ログ表示はCtrl+Cで終了します。サービスは動き続けます。成功状態がある状態でサービスを再起動し、IPが同じで期限前なら再通知されないことも確認します。

```sh
sudo systemctl restart mydns-updater
sudo journalctl -u mydns-updater -n 30 --no-pager
```

継続運用する場合だけ自動起動を有効にします。

```sh
sudo systemctl enable mydns-updater
```

試験を終える場合：

```sh
sudo systemctl disable --now mydns-updater
```

試験のためDocker側を停止した場合は、Linux側の停止後にDocker側を再開してください。

## 設定ファイル

共通設定は `/etc/mydns-updater/mydns.conf`、アカウント情報は `/etc/mydns-updater/accounts.conf` に記載します。大文字のキーと半角の `=` を使い、行頭やキーの前後に空白を入れず、値を引用符で囲まないでください。`#` で始まる行はコメントです。

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

`FORCE_UPDATE_INTERVAL` はIPが変わらなくても再通知する間隔です。アカウントごとの前回成功時刻から数え、期限を過ぎた次の確認周期で通知します。既定値の86400は24時間です。IPが変わった場合は、この期限を待たずに通知します。

範囲外や数字以外の値は警告して既定値を使用します。`FORCE_UPDATE_INTERVAL` が `CHECK_INTERVAL` より短い場合も86400秒へ戻します。

### ログ設定

`TZ` でログの表示時刻を指定します。日本時間は `Asia/Tokyo`、協定世界時は `UTC`、ニューヨークは `America/New_York` です。時刻の後ろにJST・UTC・EST/EDTなどの略称を表示し、夏時間にも対応します。

省略時はAsia/Tokyo、空欄・不正値は警告してAsia/Tokyoを使用します。OSにインストール済みのzoneinfo名を指定してください。絶対パスやPOSIX形式は使用できません。表示時刻を変えても、保存済みの成功時刻と更新期限は変わりません。

通常は起動時のバージョン・実効設定値、通知結果、エラーなどを表示します。IP不変・期限前の周期は、ログが増えなくても正常です。

`DEBUG=1` にすると、IPv4確認開始・取得IP・アカウント番号別の更新理由やスキップ理由も表示します。`DEBUG=0` または省略で無効、不正値は警告して0を使用します。ID・パスワード・認証応答本文は記録しませんが、IPやログ表示用ドメインは表示されます。

### IPv4取得先

通常は変更不要です。次の標準サービスを順に試し、取得失敗・不正なIPv4形式の場合は次へ進みます。すべて失敗した周期は通知も状態変更もしません。

1. `IP_CHECK_URL1`：https://api.ipify.org
2. `IP_CHECK_URL2`：https://checkip.amazonaws.com/
3. `IP_CHECK_URL3`：https://ipv4.ifconfig.me/ip

変更する場合は、設定例の該当行の先頭の `#` を外してURLを書き換えます。空欄・省略時は、その番号の標準サービスを使用します。

### アカウント設定

`/etc/mydns-updater/accounts.conf` に記載します。共通設定をこのファイルに入れたり、アカウント設定を `mydns.conf` に残したりしないでください。

`[1]`、`[2]` のように、一意の1〜9桁の数字でアカウントを区切り、その下にID・PASSWORD・DOMAINを記載します。DOMAINはログ表示用ですが、省略できません。

アカウントを追加する場合は、セクション行と3項目の4行をまとめて有効にしてください。無効にする場合も4行すべてをコメントアウトします。空行だけではアカウントの区切りになりません。

- 必須項目が不足したアカウントは `CONFIG ERROR` として通知を見送り、ほかの正常なアカウントは処理します。
- セクションの欠落・不正・重複、同じセクション内のアカウント項目の重複、最初のセクションより前のアカウント項目、コメントアウトしたセクション行の下に残った有効な項目は構造エラーです。その周期のIP取得と全通知を見送り、状態を変更しません。

どちらかのファイルが読めない場合や、設定先の間違い・未対応のキーがある場合も、その周期のIP取得と全通知を見送ります。旧形式を自動的に読み込む互換処理はありません。

構造エラーは `[CONFIG]` ログにファイル名と理由を表示します。項目の位置や重複のエラーでは行番号も表示し、設定値は表示しません。修正後は次の確認周期で再開します。


## ログの見方

### エラーと復旧

通常ログ（DEBUG=0）にも、初回の失敗・原因変更・重要度の段階変更・復旧を表示します。同じ失敗の繰り返しはDEBUG=1でのみ表示します。起動・通知成功は従来どおり表示します。

| 段階 | 通信障害の判定 |
| --- | --- |
| FIRST | 最初の失敗。次の対象周期で再試行 |
| PERSISTENT | 3回以上連続して失敗し、初回から10分以上経過 |
| PROLONGED | 未復旧のまま初回から1時間以上経過 |
| RECOVERED | 対象の処理が成功。回数と継続秒数を表示 |

段階の判定はその対象を実際に試した時点で行います。設定エラーや認証・アクセス拒否など確認が必要な失敗は初回からERROR、状態保存など継続不能な失敗はFATALとして終了します。IP取得先ごとの失敗は代替取得先があるためWARNに留め、全取得先の失敗はIP_CHECKとして別に段階判定します。試していない取得先を復旧扱いにはしません。

IP取得先はIP_CHECK_URL1〜3、MyDNS通知はアカウント番号とログ表示用DOMAINで識別します。curl終了コード・HTTPステータス・固定の原因コードと対処の目安を表示し、URL全文、認証情報、応答本文は記録しません。HTTP 200でも成功応答がなければSUCCESS_NOT_CONFIRMEDとし、認証失敗と断定しません。

失敗履歴は実行中の一時領域に保持し、再起動でリセットします。タイムゾーンや日時変更による誤判定を避けるため、継続時間はシステムの経過時間で測ります。接続先やアカウント設定が変わった場合も対象の履歴をリセットします。アカウント削除や、IPが戻るなどして通知が不要になった場合は履歴を解除し、通信成功による復旧とは区別して表示します。通知成功記録のstate.conf形式と更新・再試行間隔は変更しません。429のRetry-Afterに合わせた待機やHealthcheckは、この版には含めません。


## 状態の保存

`/var/lib/mydns-updater/state.conf` にアカウントごとの通知成功IPと成功時刻を保存します。再起動後も状態を引き継ぎます。設定ファイルと異なり、スクリプトによる書き込み権限が必要です。

セクション番号は状態の識別子です。別アカウントに番号を再利用するときはサービスを停止し、該当する状態セクションを削除して初回扱いにします。状態の欠落・不正は初回扱いです。状態を読み取れない、または保存できない場合は終了し、この手順のサービス設定では再起動します。

## 配置先の指定

起動時の環境変数で指定します。mydns.conf内の設定項目ではありません。

| 環境変数 | 既定値 | 内容 |
| --- | --- | --- |
| MYDNS_CONFIG_DIR | /config | mydns.confとaccounts.confを置くディレクトリ |
| MYDNS_STATE_DIR | /state | state.confの保存先 |

絶対パスを指定してください。2つの設定ファイルは同じディレクトリに置きます。起動後に環境変数を変更する場合はプロセスの再起動が必要ですが、設定ファイルの内容は周期ごとに読み直します。ディレクトリの値をログには出さないため、読み込みエラー時はこの指定先を確認してください。

任意の配置先で手動起動する例：

```sh
MYDNS_CONFIG_DIR=/etc/mydns-updater MYDNS_STATE_DIR=/var/lib/mydns-updater sh /usr/local/lib/mydns-updater/update.sh
```

その配置先を読み書きできるユーザーで実行します。サービスと手動実行を同時に起動せず、複数プロセスで同じ状態ディレクトリを共有しないでください。

## 更新

停止してスクリプトを更新し、設定・状態を保持して開始します。サービス定義を変更した場合はdaemon-reloadも実行します。実行プログラムはDocker版と同一です。

systemdの起動・再起動設定は [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) を参照してください。

## 検証状況と注意点

GitHub ActionsではUbuntu上でDockerを使わず、配置先指定の8項目とsystemdサービス定義を検査します。ARM機や実際のサービス常駐動作は導入先でも確認してください。

- このプログラムは常駐して周期処理を行います。cronから定期的に重ねて起動しないでください。
- 実際のaccounts.confとmydns.confはGitへ追加しないでください。公開するのは記入例だけです。
- IPv4のみ対応します。state.confは通知成功の記録であり、DNS応答の確認ではありません。
