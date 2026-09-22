# Linuxで直接実行する（Dockerなし）

[環境を選ぶ](../README.md#起動方法) ／ [資料一覧](README.md)

Dockerを使わず、同じ `update.sh` と `lib/` の一式を実行できます。以下はUbuntu/Debianとsystemdを使用する例です。

systemdを使うArmbianやRaspberry Pi OS（旧Raspbian）でも同じ仕組みを利用できます。ただし、この手順とARM機での動作は未検証です。
`ps -p 1 -o comm=` の結果が `systemd` であることを確認し、必要なコマンドや配置先も導入先に合わせて確認してください。

Ubuntu Server 24.04 LTS（DS1522+上のx86-64 VM）で、v1.7.0の実アカウントによる通知・定期監視・異常検知と復旧・OS再起動後の動作を確認しています。ARM機や他のLinux環境は未検証です。

初めてLinux環境を用意する場合は、[DS1522+でのUbuntu VM構築例](reference/synology-vm.md) を参考にしてください。導入後の詳しい検証は [Linuxの動作確認手順](linux-testing.md) にまとめています。

必要なものはPOSIX sh、curl、CA証明書、tzdata、awkなどの標準コマンド、およびLinuxの `/proc` です。

導入前に模擬テストを行い、ファイルを配置した後に実際の通知・設定の再読み込み・再起動を確認します。

## コマンドの読み方

以下はLinux側の端末で実行します。VMの場合はVMの画面、またはVMへSSH接続した画面を使います。NAS本体の端末ではありません。

- 番号付きの手順を順に進め、各操作の結果を確認します。
- 「必要な場合だけ」「困ったときだけ」の操作は、条件に当てはまる場合に限って行います。
- 選択肢がある箇所は、どちらか一方を選びます。すべてのコード枠を実行する必要はありません。
- `sudo` は管理者権限で実行する指定です。入力するのはLinuxのログインユーザーのパスワードです。
- パスワード入力中に文字が表示されなくても正常です。
- エラーが出たら、次の操作へ進む前に内容を確認します。
- `Ctrl+C` でログ表示を終了しても、サービスは動き続けます。

## ファイルの配置

ダウンロードして展開したフォルダーは、テストとインストールの作業場所です。運用に必要なファイルを、次の場所へコピーします。

| 配置先 | 役割・コピー元 |
| --- | --- |
| `/usr/local/lib/mydns-updater/update.sh` | 実行プログラム。配布ファイルの `update.sh` をコピー |
| `/usr/local/lib/mydns-updater/lib/` | 機能ごとの処理。配布ファイルの `lib/` 内の6ファイルをコピー |
| `/etc/mydns-updater/mydns.conf` | 共通設定。`mydns.conf.example` をコピーして編集 |
| `/etc/mydns-updater/accounts.conf` | アカウント情報。`accounts.conf.example` をコピーして編集 |
| `/var/lib/mydns-updater/state.conf` | 通知成功の記録。実行中に自動生成 |
| `/etc/systemd/system/mydns-updater.service` | 常駐・起動の設定。`deploy/linux/mydns-updater.service` をコピー |

設定は `/etc/mydns-updater/`、自動保存する状態は `/var/lib/mydns-updater/` に分けます。新規導入では状態の保存先を空で用意し、`state.conf` を手作業で作る必要はありません。

配布フォルダーの `config/`・`state/` を、そのままLinuxの運用場所にする手順ではありません。`tests/` は作業場所で使用し、上記の配置先へコピーする必要はありません。

手順1でコードを取得した後のコピー・テスト操作は、展開したフォルダーの直下（`update.sh` がある場所）で実行します。インストール後のサービス操作や設定編集は、どのフォルダーからでも実行できます。

## 1. 必要なソフトを準備する

次のコマンドで、実行・設定編集・取得・監視に必要なソフトをインストールします。

```sh
sudo apt update
sudo apt install curl ca-certificates tzdata git nano util-linux coreutils
```

### まだコードを取得していない場合だけ

すでに対象の版を取得した場合は、次のclone操作を飛ばして「取得済みのファイルを確認する」へ進みます。

以下はv1.10.0の試験用ブランチを新しいフォルダーへ取得する例です。まだmainにマージしていません。公開済みリリースとは異なります。

```sh
git clone --branch v1.10.0-modular-core --single-branch https://github.com/Karoeba/mydns-updater.git mydns-updater
cd mydns-updater
git rev-parse HEAD
```

最後に表示される文字列は、取得したコードを識別するコミット番号です。確認記録として残します。同名フォルダーがある場合は上書きせず、中身を確認してください。

### 取得済みのファイルを確認する

Git・ZIPのどちらで取得した場合も、対象の版の `update.sh` があるフォルダーへ移動し、次で確認します。以降の配置操作はこの場所から実行します。

```sh
pwd
ls update.sh lib/*.sh deploy/linux/mydns-updater.service
grep '^VERSION=' update.sh
```

update.sh・lib内の6ファイル・サービス定義が表示され、版が `1.10.0` と一致したら手順2へ進みます。`No such file or directory` や違う版が出た場合は、取得元とフォルダーを確認してから再確認します。

## 2. 導入前の模擬テスト

実アカウントや既存設定に触れず、一時ディレクトリと模擬応答で確認します。Dockerもroot権限も不要です。

```sh
sh tests/test-program-layout.sh
sh tests/test-linux.sh
sh tests/test-healthcheck-linux.sh
sh tests/test-health-monitor.sh
```

各コマンドの最後に、それぞれ次の成功表示が出ることを確認します。

- `ALL PROGRAM LAYOUT TESTS PASSED`（その前に配置後のLinux・ヘルスチェックの成功表示も出ます）
- `ALL LINUX TESTS PASSED (8 checks)`
- `ALL LINUX HEALTHCHECK TESTS PASSED (7 checks)`
- `ALL MONITOR TESTS PASSED (13 checks)`

監視テストには応答待ちの試験があり、十数秒かかります。テストの詳細は [テスト手順](testing.md) を参照してください。`tests/test-monitor-systemd.sh` は使い捨てのCI環境専用で、導入先では実行しません。

## 3. ファイルを配置する

### 実行専用ユーザーを作成する

サービスを動かすための `mydns-updater` ユーザーを用意します。

```sh
getent passwd mydns-updater >/dev/null || sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin mydns-updater
```

### プログラムと保存先を用意する

プログラムをコピーし、設定用・状態保存用のディレクトリを作成します。

```sh
sudo install -d -m 755 /usr/local/lib/mydns-updater
sudo install -o root -g root -m 644 update.sh /usr/local/lib/mydns-updater/update.sh
sudo install -d -o root -g root -m 755 /usr/local/lib/mydns-updater/lib
sudo install -o root -g root -m 644 lib/*.sh /usr/local/lib/mydns-updater/lib/
sudo install -d -o root -g mydns-updater -m 750 /etc/mydns-updater
sudo install -d -o mydns-updater -g mydns-updater -m 700 /var/lib/mydns-updater
```

配置を確認します。

```sh
ls -l /usr/local/lib/mydns-updater/update.sh /usr/local/lib/mydns-updater/lib/*.sh
```

update.shとlib内の6ファイルが表示され、所有者・グループがroot、権限が `-rw-r--r--` なら次へ進みます。

### 設定例をコピーして編集する

次のコピーは初回のみです。既存設定がある場合は上書きせず、その設定を使用してください。

```sh
sudo install -o root -g mydns-updater -m 640 mydns.conf.example /etc/mydns-updater/mydns.conf
sudo install -o root -g mydns-updater -m 640 accounts.conf.example /etc/mydns-updater/accounts.conf
```

コピー先の2つのファイルを編集します。`mydns.conf` に共通設定、`accounts.conf` に各アカウントのID・PASSWORD・DOMAINを記入してください。各項目は後述の「設定ファイル」で説明しています。

```sh
sudo nano /etc/mydns-updater/mydns.conf
sudo nano /etc/mydns-updater/accounts.conf
```

nanoは **Ctrl+O → Enterで保存、Ctrl+Xで終了**です。2つ目のアカウントは `[2]` とID・PASSWORD・DOMAINの4行をまとめて有効にします。

通常の運用では設定例の間隔を使用できます。試験用に間隔を短くする場合は [動作確認手順](linux-testing.md) を参照してください。

この権限設定ではrootが編集でき、実行ユーザーmydns-updaterが読み取れます。

同じ実アカウントをDocker側と同時に動かさないでください。試験用アカウントを使うか、実通知の確認中だけ既存側を停止します。

## 4. サービスを開始して通知を確認する

`mydns-updater.service` は、Linuxのサービス管理機能であるsystemdに、プログラムの起動方法を伝える設定ファイルです。実行するユーザー、プログラムの場所、設定・状態の保存先、異常終了時の再起動方法を記載しています。

付属のファイルを `/etc/systemd/system/mydns-updater.service` にコピーして使います。この手順の配置先は指定済みなので、通常は内容を変更する必要も、起動のたびに環境変数を入力する必要もありません。

以下の `daemon-reload` はサービス設定の読み直し、`start` はサービスの起動です。OS起動時の自動起動は、手順6で別途有効にします。

```sh
sudo install -m 644 deploy/linux/mydns-updater.service /etc/systemd/system/mydns-updater.service
sudo systemctl daemon-reload
sudo systemctl start mydns-updater
```

状態とログを表示します。

```sh
sudo systemctl status mydns-updater --no-pager
sudo journalctl -u mydns-updater -n 50 --no-pager
```

確認する項目は次のとおりです。

- `active (running)` と表示され、ログに使用中のバージョンが表示される。
- 各アカウントに `MyDNS update: OK` が表示される。
- `/var/lib/mydns-updater/state.conf` が生成される。

`DEBUG=1` なら、周期ごとの確認やスキップもログで確認できます。

定期監視も導入する場合は、先に [ヘルスチェック](#ヘルスチェック) の手動確認と [定期監視の有効化](#定期監視を有効にする) を行います。正常時の確認を終えたら、以下の手順5へ戻ります。異常・復旧などの詳しい試験は [Linuxの動作確認手順](linux-testing.md) にまとめています。

## 5. 設定の再読み込みと再起動を確認する

`/etc/mydns-updater/mydns.conf` のDEBUGを変更して保存し、次の確認周期のログを確認します。設定を変更するだけならサービス再起動は不要です。

アップロードで置き換える場合は、ファイルの所有者・グループ・権限も維持してください。

```sh
sudo journalctl -u mydns-updater -f
```

ログ表示はCtrl+Cで終了します。サービスは動き続けます。

通知成功後にサービスを再起動し、状態が引き継がれることも確認します。IPが同じで更新期限前なら再通知されません。`DEBUG=1` にしておくと、スキップ理由を確認できます。

```sh
sudo systemctl restart mydns-updater
sudo journalctl -u mydns-updater -n 30 --no-pager
```

## 6. 継続運用する、または試験を終了する

**ここは、どちらか一方を選びます。**

### Linuxで継続運用する場合

OS起動時の自動起動を有効にします。

```sh
sudo systemctl enable mydns-updater
```

ここで導入手順は完了です。次の停止操作は行いません。

### 試験を終了して元の環境へ戻す場合

継続運用する場合は、この操作を行いません。サービスを停止し、自動起動も無効にします。

定期監視を導入済みの場合だけ、先に `sudo systemctl disable --now mydns-updater-healthcheck.timer` を実行します。自動復帰を導入済みの場合だけ、`sudo systemctl disable --now mydns-updater-recovery.timer` と `sudo systemctl stop mydns-updater-recovery.service` も実行します。

```sh
sudo systemctl disable --now mydns-updater
```

確認・記録・切り戻しの順序は [動作確認手順](linux-testing.md) を参照してください。

試験のためDocker側を停止した場合は、Linux側の停止後にDocker側を再開してください。

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

サービス起動後、次のコマンドで確認します。

```sh
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
```

`HEALTHY` は処理中または待機中、`UNHEALTHY` はプロセス・進行記録・進行期限のいずれかに問題があることを示します。終了コードは正常時0、異常時1です。サービス設定はこの手動コマンドには自動適用されないため、同じ記録先を指定します。

判定は追加通信を行いません。待機時間や通信制限時間に120秒の余裕を加えて判断し、通信・設定エラーがあってもループが進行していれば正常です。MyDNS.JPへの通知結果は通常ログで確認してください。

上記は手動で1回確認する方法です。`systemctl status` の稼働表示とは別に、処理の進行を確認します。定期的に確認したい場合は、下記のタイマーを有効にしてください。

`MYDNS_HEALTH_FILE` は起動時の環境変数です。指定しない場合は `/tmp/mydns-updater.health` を使います。変更する場合は親ディレクトリを用意し、実行ユーザーの書き込み権限を設定してください。複数のプロセスで同じ進行記録を共有しないでください。

### 定期監視を有効にする

v1.7.0では、systemdのタイマーで約30秒ごとに確認できます。追加するファイルは次の3つです。

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

有効にすると、以後は更新サービスの起動に合わせて監視も起動します。OS起動時にも更新サービスを起動するには、手順6の自動起動設定が必要です。

更新サービスを手動で停止するとタイマーも停止します。監視から更新サービスを起動・再起動することはありません。

### 監視結果を確認する

```sh
sudo systemctl list-timers --all mydns-updater-healthcheck.timer
sudo journalctl -t mydns-updater-healthcheck --no-pager -n 30
```

1つ目はタイマーの次回実行時刻、2つ目は監視処理のログを表示します。監視サービスは1回の確認で終了するため、`inactive (dead)` だけで異常とは限りません。

異常・復旧を実際に試す場合は [Linuxの動作確認手順](linux-testing.md) を参照してください。

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

### v1.9.0からv1.10.0へ更新する

設定項目・状態ファイル・サービス定義は変更していません。今回はupdate.shとlibを一緒に配置します。
設定と状態をバックアップし、取得したv1.10.0のフォルダーで次を実行します。

```sh
pwd
ls update.sh lib/*.sh
grep '^VERSION=' update.sh
```

update.shとlib内の6ファイルが表示され、版が1.10.0なら続けます。

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
ls -l /usr/local/lib/mydns-updater/update.sh /usr/local/lib/mydns-updater/lib/*.sh
sudo systemctl start mydns-updater
sudo systemctl status mydns-updater --no-pager
sudo journalctl -u mydns-updater -n 30 --no-pager
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
```

7ファイルが配置され、起動ログがv1.10.0、状態が `active (running)`、ヘルスチェックが `HEALTHY` なら成功です。
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

v1.6.0からは、設定・状態を保持してスクリプトを更新し、上記の3ファイルを追加して定期監視を有効にします。v1.7.0までの更新サービス定義はv1.6.0と同じでしたが、v1.8.0では上記の変更があります。監視スクリプトを更新する際はタイマーと監視サービスを停止してから上書きし、タイマーを再開してください。

v1.5.0からの更新では、スクリプトと付属のサービス定義を更新してください。サービス定義を独自に編集している場合は、その配置先を保持したうえでRuntimeDirectory・RuntimeDirectoryMode・MYDNS_HEALTH_FILEの指定を反映します。

停止してスクリプトを更新し、設定・状態を保持して開始します。サービス定義を変更した場合はdaemon-reloadも実行します。実行プログラムはDocker版と同一です。

systemdの起動・再起動設定は [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) を参照してください。

## 検証状況と注意点

GitHub ActionsではUbuntu上でDockerを使わず、既存の配置先・ヘルスチェックに加え、連続失敗と復旧の判定、systemdによる定期実行・停止連動を確認します。ARM機や実際のサービス常駐動作は導入先でも確認してください。

- このプログラムは常駐して周期処理を行います。cronから定期的に重ねて起動しないでください。
- 実際のaccounts.confとmydns.confはGitへ追加しないでください。公開するのは記入例だけです。
- IPv4のみ対応します。state.confは通知成功の記録であり、DNS応答の確認ではありません。
