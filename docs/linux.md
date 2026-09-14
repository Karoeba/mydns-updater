# Linuxで直接実行する

Dockerを使わず、同じupdate.shを実行できます。必要なものはPOSIX sh、curl、CA証明書、tzdata、awkなどの標準コマンド、およびLinuxの/procです。以下はUbuntu/Debianとsystemdを使用する例です。ARM機での実機確認は別途必要です。Healthcheckは含みません。

## 1. 準備と模擬テスト

この版のソースを取得し、展開先のmydns-updaterディレクトリで実行します。

```sh
sudo apt update
sudo apt install curl ca-certificates tzdata
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
