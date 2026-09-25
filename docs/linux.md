# Linuxで直接実行する（Dockerなし）

[環境を選ぶ](../README.md#起動方法) ／ [資料一覧](README.md)

Dockerを使わず、update.shとlibをLinux上で動かします。
以下はUbuntu/Debianとsystemdを使う場合の手順です。DS1522+のVMにUbuntuをインストール済みなら、ここから始められます。

**操作する場所はUbuntuの端末です。NAS本体のSSHやWindowsのPowerShellではありません。**

## 目的に合わせて進む

| 目的 | 進む順番 |
| --- | --- |
| 開発版を検証する（今回はこちら） | 1 準備 → 2 模擬テスト → 3 配置と実アカウント設定 → 4 起動 → 5 ヘルスチェック → 6から詳しい動作確認へ |
| 通常導入する | 1 準備 → 3〜5で導入と通知確認 → 6で継続運用。2の模擬テストは任意 |
| 導入済みの版を更新する | [更新方法](#更新方法)へ。初回用の設定コピーは行わない |

下の取得コマンドはmainを指定しています。GitHub Releaseとしての公開状況とは別に、mainのコード一式を取得します。

- **模擬テスト**：実アカウントを使わず、用意した通信結果でプログラムを検査します。
- **実アカウントでの確認**：実際にMyDNS.JPへ通知し、導入先での動作を確認します。
- **定期監視・自動復帰**：通常の通知を確認した後、使う場合だけ追加します。自動復帰のために「定期監視だけ」の機能を先に入れる必要はありません。

## コマンドと結果の読み方

1つの枠を実行し、その下の確認を済ませてから次へ進みます。
枠の外にあるユーザー名や入力待ちの記号は入力しません。

- sudoのパスワードはUbuntuのログインパスワードです。入力中に文字が出なくても正常です。
- コピーや保存は、何も表示せず終了することがあります。後の確認コマンドで配置を確かめます。
- `Ctrl+C` はログの連続表示を終える操作です。更新サービスは停止しません。
- 「必要な場合だけ」「困ったときだけ」は条件に当てはまる場合だけ行います。
- 期待した表示にならなければ先へ進まず、手順番号と表示を控えます。

## ファイルの配置

**取得した作業フォルダー**と、**実際に動かす場所**は別です。
取得しただけではサービスは起動せず、手順3で必要なものをコピーします。

作業フォルダー（関係するファイルを抜粋）：

```text
~/mydns-updater/
├── update.sh
├── lib/                       ← 6つの.shファイル
├── mydns.conf.example
├── accounts.conf.example
├── deploy/
│   └── linux/
│       └── mydns-updater.service
└── tests/                     ← 模擬テスト。運用先へはコピーしない
```

配置後のLinux：

```text
/
├── usr/local/lib/mydns-updater/
│   ├── update.sh              ← 起動用プログラム
│   └── lib/
│       ├── config.sh
│       ├── diagnostics.sh
│       ├── health.sh
│       ├── network.sh
│       ├── runtime.sh
│       └── state.sh
├── etc/
│   ├── mydns-updater/
│   │   ├── mydns.conf          ← 自分の共通設定
│   │   └── accounts.conf       ← 自分のアカウント設定
│   └── systemd/system/
│       └── mydns-updater.service
├── var/lib/mydns-updater/
│   └── state.conf             ← 通知成功後に自動生成
└── run/mydns-updater/
    └── health                 ← 起動後に自動生成する進行記録
```

| 場所 | 用途 |
| --- | --- |
| /usr/local/lib/mydns-updater/ | プログラム一式。update.shとlibを同じ版で配置 |
| /etc/mydns-updater/ | 利用者が編集する設定 |
| /etc/systemd/system/ | Linuxへ起動方法を伝えるサービス設定 |
| /var/lib/mydns-updater/ | 再起動後も引き継ぐ通知成功の記録 |
| /run/mydns-updater/ | 起動中だけ使うヘルスチェックの記録 |

Linuxでは用途に応じて置き場所を分けています。ツリーは場所の関係、表は役割を説明しています。
state.confとhealthは手作業で作りません。監視・自動復帰を追加するときのファイルは、それぞれの追加手順で配置します。

## 1. 必要なソフトとプログラムを用意する

```sh
sudo apt update
sudo apt install curl ca-certificates tzdata git nano util-linux coreutils
```

**確認：** パッケージ取得・導入のエラーがなく、入力待ちへ戻ったら続けます。

### まだ取得していない場合だけ

```sh
git clone --branch main --single-branch https://github.com/Karoeba/mydns-updater.git mydns-updater
cd mydns-updater
```

取得済みの場合はcloneを繰り返さず、そのフォルダーへ移動します。
以降のコピーと模擬テストは、update.shがある作業フォルダーで行います。

```sh
pwd
ls update.sh lib/*.sh deploy/linux/mydns-updater.service
grep '^VERSION=' update.sh
git rev-parse HEAD
```

**確認：** update.sh、lib内の6ファイル、サービス設定が表示され、版が `1.10.1` であることを確認します。
最後の長い文字列は試したコードの識別番号です。控えておきます。
ZIPで取得した場合はgitのコマンドを省略し、ZIP名と取得元を控えます。

<details>
<summary>困ったときだけ：ファイルがない・別の端末から再開する</summary>

ホームへ取得した例では、次で作業場所へ戻ります。

```sh
cd ~/mydns-updater
pwd
ls update.sh lib/*.sh
```

`No such file or directory` の場合は、取得した場所とフォルダー名を確認します。
不足を埋めるために空のファイルを作らず、正しい一式がある場所へ移動してください。

</details>

## 2. 実アカウントを使わない模擬テスト

**開発版の検証では実施します。通常導入だけなら手順3へ進めます。**
この段階ではID・パスワードの入力は不要です。既存のNASやDockerを止める必要もありません。

次は順に5種類のテストを実行し、1つでも失敗したら残りを実行しない書き方です。
最後の2行も含めて実行します。

```sh
sh tests/test-program-layout.sh &&
sh tests/test-linux.sh &&
sh tests/test-healthcheck-linux.sh &&
sh tests/test-health-monitor.sh &&
sh tests/test-health-recovery.sh
test_result=$?
printf '模擬テストの終了コード: %s\n' "$test_result"
```

途中に失敗・異常を表すログが出ることがあります。異常をわざと起こす試験も含むため、それだけでは試験失敗と判断しません。
監視の応答待ちなどで、しばらく表示が増えない場合もあります。終了して入力待ちに戻るまで待ちます。

**成功：** 終了コードが `0` で、次の5種類の成功表示があることを確認します。

```text
ALL PROGRAM LAYOUT TESTS PASSED
ALL LINUX TESTS PASSED (8 checks)
ALL LINUX HEALTHCHECK TESTS PASSED (7 checks)
ALL MONITOR TESTS PASSED (13 checks)
ALL RECOVERY TESTS PASSED (18 checks)
模擬テストの終了コード: 0
```

配置試験の中でも一部のテストを呼ぶため、同じ成功表示が複数回出ても正常です。
**0以外、または成功表示が足りない場合は手順3へ進みません。** 最後に実行されたテスト名と表示を控えます。

ここまででは、実際のMyDNS.JPへの通知やサービスとしての起動は確認していません。
`tests/test-monitor-systemd.sh` と `tests/test-recovery-systemd.sh` は使い捨てのCI環境専用なので、このVMでは実行しません。

## 3. 配置して実アカウントを設定する

**ここから実アカウントを使います。**
同じアカウントを使うNAS・Dockerなどの更新処理を停止してから進めます。

### 3-1. 実行専用ユーザーを作る

```sh
getent passwd mydns-updater >/dev/null || sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin mydns-updater
getent passwd mydns-updater
```

**確認：** 最後に `mydns-updater:` で始まる1行が表示されれば用意できています。

### 3-2. プログラムと保存先を配置する

```sh
sudo install -d -o root -g root -m 755 /usr/local/lib/mydns-updater
sudo install -o root -g root -m 644 update.sh /usr/local/lib/mydns-updater/update.sh
sudo install -d -o root -g root -m 755 /usr/local/lib/mydns-updater/lib
sudo install -o root -g root -m 644 lib/*.sh /usr/local/lib/mydns-updater/lib/
sudo install -d -o root -g mydns-updater -m 750 /etc/mydns-updater
sudo install -d -o mydns-updater -g mydns-updater -m 700 /var/lib/mydns-updater
```

エラーがなければ配置先を確認します。コピー時に何も表示されないのは正常です。

```sh
ls -l /usr/local/lib/mydns-updater/update.sh /usr/local/lib/mydns-updater/lib/*.sh
sudo ls -ld /etc/mydns-updater /var/lib/mydns-updater
```

**確認：** プログラム7ファイルがあり、所有者・グループがroot、権限が `-rw-r--r--`。
設定先は `root mydns-updater`、状態保存先は `mydns-updater mydns-updater` になっていれば続けます。

### 3-3. 設定を用意する

**初回で設定がない場合だけ**、次で記入例をコピーします。設定済みなら上書きせず、編集へ進みます。

```sh
sudo install -o root -g mydns-updater -m 640 mydns.conf.example /etc/mydns-updater/mydns.conf
sudo install -o root -g mydns-updater -m 640 accounts.conf.example /etc/mydns-updater/accounts.conf
```

コピー先を編集します。

```sh
sudo nano /etc/mydns-updater/mydns.conf
sudo nano /etc/mydns-updater/accounts.conf
```

共通設定は通常、記入例の値で始められます。accounts.confにはID・PASSWORD・DOMAINを記入します。
2件目を使う場合は `[2]` と3項目をまとめて有効にします。
nanoはCtrl+O、Enterで保存し、Ctrl+Xで終了します。[設定項目の説明](../README.md#設定一覧)

```sh
sudo ls -l /etc/mydns-updater/mydns.conf /etc/mydns-updater/accounts.conf
sudo -u mydns-updater sh -c 'test -r /etc/mydns-updater/mydns.conf && test -r /etc/mydns-updater/accounts.conf && echo "設定ファイルを読み取れます"'
```

**確認：** 2ファイルがあり、所有者・グループが `root mydns-updater`、権限が `-rw-r-----`。
最後に「設定ファイルを読み取れます」と出れば次へ進みます。これは読み取り権限の確認で、認証情報の正しさは次の実通知で確認します。

## 4. サービスを開始し、実際の通知を確認する

サービス設定は、Linuxの管理機能systemdへ「誰が・どのプログラムを・どの設定で起動するか」を伝えるファイルです。
標準の配置先は記入済みなので、毎回起動時にパスを入力する必要はありません。

```sh
sudo install -o root -g root -m 644 deploy/linux/mydns-updater.service /etc/systemd/system/mydns-updater.service
sudo systemctl daemon-reload
sudo systemctl start mydns-updater
```

daemon-reloadはサービス設定の読み直し、startは起動です。
エラーがなく入力待ちへ戻ったら、状態とログを表示します。

```sh
sudo systemctl status mydns-updater --no-pager
sudo journalctl -u mydns-updater -n 50 --no-pager
sudo ls -l /var/lib/mydns-updater/state.conf
```

**成功：** 次の3点を確認します。

- 状態が `active (running)`、起動ログが `v1.10.1`。
- 設定した各アカウントに `MyDNS update: OK` がある。
- state.confが作成されている。

起動直後で通知がまだ終わっていなければ、30秒程度待ってログとファイル確認を再実行します。
既存stateを引き継いだ場合は、IP不変・通知期限前なら通知を見送ります。その場合はDEBUG=1のSKIPと、次の定期通知で確認します。

<details>
<summary>困ったときだけ：起動しない・通知が成功しない</summary>

`failed` や設定・認証などのエラーがあれば、次へ進まずログを確認します。
`active (running)` だけではMyDNS.JPへの通知成功とはいえません。

```sh
sudo journalctl -u mydns-updater -n 100 --no-pager
```

[ログの意味](../README.md#エラーと復旧)と照合します。相談するときは表示を控え、パスワードを含む設定ファイルは送らないでください。

</details>

## 5. ヘルスチェックを手動で確認する

確認機能と進行記録は、ここまでの通常導入に含まれています。
ただし、Linux直接実行ではまだ定期確認は設定していません。次のコマンドは、その場で1回だけ確認するものです。
Docker・Container Managerは付属Composeで定期確認が有効になるため、この点が異なります。

```sh
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
health_result=$?
printf 'ヘルスチェックの終了コード: %s\n' "$health_result"
```

**成功：** 次の表示になれば、処理が進行中または次の周期を待っています。

```text
HEALTHY: updater progressing or waiting
ヘルスチェックの終了コード: 0
```

UNHEALTHY、MODULE_UNAVAILABLE、終了コード0以外なら、表示と手順4のログを確認してから続けます。
この確認は通知成功とは別です。追加の通信は行いません。
定期確認を使いたい場合は手順6で「異常の記録だけ」か「自動復帰」を選びます。
自動復帰にも定期確認があるため、両方のタイマーを導入する必要はありません。

**これで基本の導入は完了です。** 次は目的に合う行を1つ選びます。

## 6. 次に行うことを選ぶ

| 目的 | 次の操作 |
| --- | --- |
| 今回の開発版を詳しく検証する | [Linuxの動作確認](linux-testing.md)の手順1から。通常動作を確認し、その後で監視・自動復帰を選ぶ |
| 通常運用で自動復帰を追加する | [Linux自動復帰](linux-recovery.md)の「始める前に」から。定期監視だけの機能は事前導入不要 |
| 異常の記録だけを追加する | 下の[定期監視を有効にする](#定期監視を有効にする)へ |
| 追加せず通常運用する | 下の「継続運用する場合」へ |

### 継続運用する場合

OS起動時の自動起動を有効にします。自動復帰などを追加した場合も、OS起動時に使うなら必要です。

```sh
sudo systemctl enable mydns-updater
sudo systemctl is-enabled mydns-updater
```

**確認：** `enabled` なら設定できています。詳しい検証を行う場合のOS再起動確認は、動作確認手順にあります。

### 試験を終えて元の環境へ戻す場合だけ

[試験終了の操作](linux-testing.md#7-linux側を止めてdockerへ戻す)を使います。
まだ自動復帰の試験などを続ける場合は、ここで停止・切り戻しを行いません。

以下は必要に応じて参照する説明です。上からすべて実行する続きの手順ではありません。

## 設定ファイル

共通設定は `/etc/mydns-updater/mydns.conf`、アカウント情報は `/etc/mydns-updater/accounts.conf` に記載します。
設定項目と記入方法は、Docker・Synologyと共通です。

[設定一覧と各項目の説明](../README.md#設定一覧)を参照してください。
設定例の順に、更新間隔、ログ設定、IPv4取得先、アカウント設定を説明しています。
変更した設定は次の確認周期で読み直します。起動時のログは、変更しても書き換わりません。

## ログの見方

ログは次のコマンドで確認します。

```sh
sudo journalctl -u mydns-updater --no-pager -n 50
```

起動バージョンと通知結果を確認します。`MyDNS update: OK` は通知成功です。
`DEBUG=0` では、IP不変・通知期限前のログが増えなくても正常です。

[エラーと復旧の説明](../README.md#エラーと復旧)は全環境共通です。
自動復帰を有効にした場合の監視ログは、[Linuxの自動復帰](linux-recovery.md)で説明しています。

## ヘルスチェック

Docker版と同じ判定処理で、プロセスと定期処理の進行を確認できます。付属のサービス設定ではsystemdが `/run/mydns-updater/` を用意し、進行記録を保存します。この記録は設定や通知成功の状態とは別の一時ファイルです。

手動確認のコマンドと成功表示は[手順5](#5-ヘルスチェックを手動で確認する)にあります。
HEALTHYは処理中または待機中、UNHEALTHYはプロセス・進行記録・進行期限のいずれかに問題があることを示します。

判定は追加通信を行いません。待機時間や通信制限時間に120秒の余裕を加えて判断し、通信・設定エラーがあってもループが進行していれば正常です。MyDNS.JPへの通知結果は通常ログで確認してください。

手順5は手動で1回確認する方法です。`systemctl status` の稼働表示とは別に、処理の進行を確認します。定期的に確認したい場合は、下記のタイマーを有効にしてください。

`MYDNS_HEALTH_FILE` は起動時の環境変数です。指定しない場合は `/tmp/mydns-updater.health` を使います。変更する場合は親ディレクトリを用意し、実行ユーザーの書き込み権限を設定してください。複数のプロセスで同じ進行記録を共有しないでください。

### 定期監視を有効にする

この節は、異常の記録だけを追加したい場合に使います。自動復帰を選んだ場合は実行不要です。
systemdのタイマーで約30秒ごとに確認できます。追加するファイルは次の3つです。

| 配布ファイル | 配置先・役割 |
| --- | --- |
| `health-monitor.sh` | `/usr/local/lib/mydns-updater/health-monitor.sh`：連続失敗と復旧を判定 |
| `deploy/linux/mydns-updater-healthcheck.service` | `/etc/systemd/system/`：監視処理の実行方法 |
| `deploy/linux/mydns-updater-healthcheck.timer` | `/etc/systemd/system/`：監視処理を呼ぶ間隔 |

ここでのserviceは、常駐する更新プログラムとは別に、1回の確認を実行する設定です。タイマーが呼ぶたびに確認し、終了します。

展開したフォルダーの直下でコピーし、タイマーを有効にします。先に手順4で更新サービスを起動してください。

```sh
sudo install -m 644 health-monitor.sh /usr/local/lib/mydns-updater/health-monitor.sh
sudo install -m 644 deploy/linux/mydns-updater-healthcheck.service /etc/systemd/system/mydns-updater-healthcheck.service
sudo install -m 644 deploy/linux/mydns-updater-healthcheck.timer /etc/systemd/system/mydns-updater-healthcheck.timer
sudo systemctl daemon-reload
sudo systemctl enable --now mydns-updater-healthcheck.timer
```

有効にすると、以後は更新サービスの起動に合わせて監視も起動します。OS起動時にも更新サービスを起動するには、「継続運用する場合」の自動起動設定が必要です。

更新サービスを手動で停止するとタイマーも停止します。監視から更新サービスを起動・再起動することはありません。

### 監視結果を確認する

```sh
sudo systemctl list-timers --all mydns-updater-healthcheck.timer
sudo journalctl -t mydns-updater-healthcheck --no-pager -n 30
```

1つ目はタイマーの次回実行時刻、2つ目は監視処理のログを表示します。監視サービスは1回の確認で終了するため、`inactive (dead)` だけで異常とは限りません。

タイマーの予定と実行記録を確認できたら、導入だけなら「継続運用する場合」へ、開発版の検証中なら[監視の試験](linux-testing.md#3-監視または自動復帰を選んで確認する)へ進みます。

- 初回から正常なら、監視処理の独自ログは出しません。`No entries` だけでは監視処理の成功を確認できないため、下記のサービス実行ログも確認します。
- 3回連続で確認に失敗すると `[ERROR] [HEALTH_MONITOR] UNHEALTHY` を1回記録します。
- 異常判定後に確認が成功すると `[INFO] [HEALTH_MONITOR] RECOVERED` を1回記録します。
- 1〜2回の失敗後に成功した場合は、失敗回数をリセットし、復旧ログは出しません。

30秒は確認を呼ぶ間隔です。更新処理の進行期限には待機時間・通信制限時間と120秒の余裕が含まれるため、処理停止から90秒で必ず異常になるという意味ではありません。

失敗回数は `/run/mydns-updater-monitor/status` に保存します。OS再起動や更新サービスの新しい起動では、それまでの失敗回数を引き継ぎません。監視処理の保存先などに問題がある場合は、監視自体のエラーとして表示します。

systemd自身の起動・終了メッセージまで確認する場合は、次を使います。

```sh
sudo journalctl -u mydns-updater-healthcheck.service --no-pager -n 30
```

<details>
<summary>必要な場合だけ：定期監視を無効にする</summary>

監視を使い続ける場合は、この操作を行いません。

```sh
sudo systemctl disable --now mydns-updater-healthcheck.timer
```

更新プログラムはそのまま動き続けます。この定期監視は検知と記録を担当し、再起動や外部への通知送信は行いません。


</details>

### 自動復帰を追加する

処理停止時に再起動する機能は、任意で追加できます。初期状態では無効です。
条件・回数制限と導入方法は [Linuxの自動復帰](linux-recovery.md) にまとめています。

配置先を独自に変更している場合は、監視サービスの `MYDNS_UPDATER` と `MYDNS_HEALTH_FILE` も更新プログラムと同じ場所に合わせてください。`MYDNS_MONITOR_DIR` は監視履歴の保存先であり、アカウントの状態保存先とは別です。これらは起動時の環境変数で、`mydns.conf` には記入しません。

## 状態の保存

`/var/lib/mydns-updater/state.conf` にアカウントごとの通知成功IPと成功時刻を保存します。再起動後も状態を引き継ぎます。設定ファイルと異なり、スクリプトによる書き込み権限が必要です。

セクション番号は状態の識別子です。別アカウントに番号を再利用するときはサービスを停止し、該当する状態セクションを削除して初回扱いにします。状態の欠落・不正は初回扱いです。状態を読み取れない、または保存できない場合は終了し、この手順のサービス設定では10分後に再起動を試します。1時間に4回の起動制限に達した場合は停止したままになるため、原因を解決してから `sudo systemctl reset-failed mydns-updater` と `sudo systemctl start mydns-updater` を実行します。

## 配置先を変更する場合

### サービス設定に保存する

通常は、この手順の配置先をそのまま使用できます。変更したい場合は、インストール済みのサービス設定を編集します。

```sh
sudo nano /etc/systemd/system/mydns-updater.service
```

`[Service]` 内の次の2行が、設定ファイルと状態ファイルの保存先です。右辺を希望する絶対パスに変更してください。

```ini
Environment=MYDNS_CONFIG_DIR=/etc/mydns-updater
Environment=MYDNS_STATE_DIR=/var/lib/mydns-updater
```

環境変数は、起動時にプログラムへ渡す設定です。このファイルに保存しておけば、サービスの起動・再起動・OS再起動時に毎回同じ値が使われます。`mydns.conf` に記入する項目ではありません。

サービス設定を変更しても、ファイルは自動では移動しません。サービスを停止してから、2つの設定ファイルと既存の状態ファイルを新しい場所へ配置します。

```sh
sudo systemctl stop mydns-updater
```

2つの設定ファイルは同じディレクトリに置き、実行ユーザー `mydns-updater` が読み取れる権限を保ちます。状態の保存先には同ユーザーの書き込み権限も必要です。状態ファイルを引き継がない場合は初回扱いになります。

プログラム自体の配置先も変える場合は、update.shと同じ場所にlibフォルダーも配置します。
また、同じサービス設定内の次の行も変更します。

```ini
ExecStart=/bin/sh /usr/local/lib/mydns-updater/update.sh
```

ファイルの配置と設定の保存を終えたら、サービス設定を読み直して起動します。

```sh
sudo systemctl daemon-reload
sudo systemctl start mydns-updater
sudo systemctl status mydns-updater --no-pager
sudo journalctl -u mydns-updater -n 30 --no-pager
```

この読み直しと起動は、サービス設定の変更を反映するための操作です。普段の `mydns.conf`・`accounts.conf` の内容変更は、次の確認周期で自動的に読み直します。

### サービスを使わず手動起動する場合

サービス設定は、`sh update.sh` のような直接起動には適用されません。手動起動では、次の環境変数で配置先を渡します。

| 環境変数 | 指定しない場合 | 内容 |
| --- | --- | --- |
| MYDNS_CONFIG_DIR | /config | mydns.confとaccounts.confを置くディレクトリ |
| MYDNS_STATE_DIR | /state | state.confの保存先 |

```sh
MYDNS_CONFIG_DIR=/etc/mydns-updater MYDNS_STATE_DIR=/var/lib/mydns-updater sh /usr/local/lib/mydns-updater/update.sh
```

この指定はその起動に対してだけ有効です。継続運用では、上記のサービス設定へ保存する方法を使用してください。

その配置先を読み書きできるユーザーで実行します。サービスと手動実行を同時に起動せず、複数プロセスで同じ状態ディレクトリを共有しないでください。

## 更新方法

### v1.9.0以降からv1.10.1へ更新する

状態ファイル・サービス定義は維持します。通知間隔の上限とcurl設定の扱いは[更新時の変更点](../README.md#v1100からv1101への更新)を先に確認してください。
update.shとlibに加え、Linux自動復帰用のhealth-recover.shも同じ版で配置します。配置だけで自動復帰が有効になることはありません。
設定と状態をバックアップし、取得したv1.10.1のフォルダーで次を実行します。

```sh
pwd
ls update.sh lib/*.sh
grep '^VERSION=' update.sh
```

update.shとlib内の6ファイルが表示され、版が1.10.1なら続けます。

**自動復帰を設定済みの場合だけ：** 次で一時的に止め、実行中の確認処理の終了を待ちます。

```sh
sudo systemctl stop mydns-updater-recovery.timer mydns-updater-recovery.service
```

自動復帰を使っていない場合は上の操作を飛ばします。更新サービスを停止し、一式を配置して開始します。
標準の配置先を使う場合のコマンドです。独自の配置先を使う場合は、コピー先を合わせます。

```sh
sudo systemctl stop mydns-updater
sudo install -o root -g root -m 644 update.sh /usr/local/lib/mydns-updater/update.sh
sudo install -d -o root -g root -m 755 /usr/local/lib/mydns-updater/lib
sudo install -o root -g root -m 644 lib/*.sh /usr/local/lib/mydns-updater/lib/
sudo install -o root -g root -m 644 health-recover.sh /usr/local/lib/mydns-updater/health-recover.sh
ls -l /usr/local/lib/mydns-updater/update.sh /usr/local/lib/mydns-updater/lib/*.sh
sudo systemctl start mydns-updater
sudo systemctl status mydns-updater --no-pager
sudo journalctl -u mydns-updater -n 30 --no-pager
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
```

7ファイルが配置され、起動ログがv1.10.1、状態が `active (running)`、ヘルスチェックが `HEALTHY` なら成功です。
起動直後で判定待ちの場合は、少し待って最後の確認コマンドだけを再実行します。
stateを引き継ぐため、IP不変・通知期限前は通知を見送ります。

**自動復帰を最初に止めた場合だけ：** 次で再開し、次回実行時刻を確認します。

```sh
sudo systemctl start mydns-updater-recovery.timer
sudo systemctl list-timers --all mydns-updater-recovery.timer
```

### さらに古い版から更新する場合の追加事項

上の一式の配置に加え、使用中の版に応じて次を確認します。

v1.8.0では更新サービスの異常終了後の待機を10分とし、1時間に4回までの起動制限を追加しました。スクリプトに加えて `deploy/linux/mydns-updater.service` も更新します。独自の配置先を使っている場合は、その指定を保持してください。

自動復帰を使う場合は [導入・更新手順](linux-recovery.md) に従って追加します。Ubuntu VMでの自動復帰と手動停止を確認済みです。範囲は [検証記録](testing.md#作者による確認状況) を参照してください。

v1.6.0からは、設定・状態を保持してスクリプトを更新し、[定期監視](#定期監視を有効にする)の3ファイルを追加して有効にします。v1.7.0までの更新サービス定義はv1.6.0と同じでしたが、v1.8.0では上記の変更があります。監視スクリプトを更新する際はタイマーと監視サービスを停止してから上書きし、タイマーを再開してください。

v1.5.0からの更新では、スクリプトと付属のサービス定義を更新してください。サービス定義を独自に編集している場合は、その配置先を保持したうえでRuntimeDirectory・RuntimeDirectoryMode・MYDNS_HEALTH_FILEの指定を反映します。

停止してスクリプトを更新し、設定・状態を保持して開始します。サービス定義を変更した場合はdaemon-reloadも実行します。実行プログラムはDocker版と同一です。

systemdの起動・再起動設定は [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) を参照してください。

## 検証状況と注意点

GitHub ActionsではUbuntu上でDockerを使わず、既存の配置先・ヘルスチェックに加え、連続失敗と復旧の判定、systemdによる定期実行・停止連動を確認します。ARM機や実際のサービス常駐動作は導入先でも確認してください。

- このプログラムは常駐して周期処理を行います。cronから定期的に重ねて起動しないでください。
- 実際のaccounts.confとmydns.confはGitへ追加しないでください。公開するのは記入例だけです。
- IPv4のみ対応します。state.confは通知成功の記録であり、DNS応答の確認ではありません。
