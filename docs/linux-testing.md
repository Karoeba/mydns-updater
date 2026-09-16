# Linuxの動作確認手順

[資料一覧](README.md) ／ [Linux導入手順](linux.md) ／ [自動テストと模擬テスト](testing.md)

Ubuntu Server 24.04 LTSと付属のsystemd設定を使用する手順です。Linux導入手順に沿って更新サービスと定期監視を起動した後に行います。各手順では実行結果を確認してから次へ進みます。

## 1. 試験の準備と通常動作

同じ実アカウントの既存環境を停止するか、別の試験用アカウントを使用します。試験環境と運用環境で設定・状態の保存先を共有しません。

共通設定の該当行を一時的に変更します。重複追加はしないでください。

```sh
sudo nano /etc/mydns-updater/mydns.conf
```

```ini
CHECK_INTERVAL=60
FORCE_UPDATE_INTERVAL=3600
DEBUG=1
```

次の確認周期で反映されます。約1分ごとのCHECKログになったこと、各アカウントの通知成功、状態ファイルの生成、手動ヘルスチェックのHEALTHYを確認します。起動直後でも既存の成功状態があれば、IP不変・期限前の通知は省略されます。

```sh
sudo journalctl -u mydns-updater -n 30 --no-pager
sudo ls -l /var/lib/mydns-updater/state.conf
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
sudo systemctl list-timers --all mydns-updater-healthcheck.timer
sudo journalctl -u mydns-updater-healthcheck.service -n 20 --no-pager
```

タイマーに次回時刻があり、監視サービスが実行され正常終了していることを確認します。正常時に監視の独自ログがないことと、監視が実行されていないことは別です。

## 2. 固まりを再現し、異常・復旧を確認する

**ここはUbuntuの試験環境で行います。NAS本体やDocker側では実行しません。** 一時停止している間はLinux版の通知処理も進みません。

通常の「サービス停止」と、処理だけが「固まる」状態は別です。通常停止では監視も休止するので、この試験ではSTOP信号で更新プログラムだけを一時停止します。

まず、再開用のコマンドが以下にあることを確認してから、一時停止します。

```sh
sudo systemctl kill --kill-whom=main --signal=STOP mydns-updater.service
```

監視ログを追いかけます。

```sh
sudo journalctl -t mydns-updater-healthcheck -f
```

CHECK_INTERVAL=60が反映済みなら、進行期限と連続失敗の判定を含めて数分、目安として最大5分程度待ちます。負荷などで前後します。

```text
[ERROR] [HEALTH_MONITOR] UNHEALTHY; consecutive_failures=3; ...
```

これが1回表示され、その後同じ異常が続いても繰り返し表示されなければ想定どおりです。自動再起動は行いません。

**Ctrl+Cでログ表示を終了し、必ず次で再開します。**

```sh
sudo systemctl kill --kill-whom=main --signal=CONT mydns-updater.service
```

再びログを見ます。

```sh
sudo journalctl -t mydns-updater-healthcheck -f
```

次の処理進行と監視を待つと、1〜2分程度を目安に次が表示されます。

```text
[INFO] [HEALTH_MONITOR] RECOVERED; updater progressing or waiting
```

Ctrl+Cで表示を終了したら、**再起動へ進む前に**記録を保存します。

```sh
mkdir -p ~/mydns-test-results
sudo journalctl -t mydns-updater-healthcheck -b --no-pager > ~/mydns-test-results/monitor-before-reboot.log
sudo journalctl -u mydns-updater-healthcheck.service -b --no-pager > ~/mydns-test-results/monitor-service-before-reboot.log
```

保存したログにUNHEALTHYとRECOVEREDがあることを確認します。端末に表示された結果も記録してください。再起動後のログ保持は環境によるため、最後にまとめて取得するだけでは試験時の記録が残らない場合があります。

異常ログが出なかった場合もCONTは必ず実行し、状態とログを確認してください。[Ubuntuのsystemctl説明](https://manpages.ubuntu.com/manpages/noble/man1/systemctl.1.html)

## 3. 手動停止・開始の連動を確認する

```sh
sudo systemctl stop mydns-updater
sudo systemctl is-active mydns-updater.service
sudo systemctl is-active mydns-updater-healthcheck.timer
```

両方 `inactive` が想定です。`is-active` はinactiveのとき終了コードが0以外になりますが、この場面では期待する結果です。

監視が更新サービスを勝手に起動しないことを確認し、手動で開始します。

```sh
sudo systemctl start mydns-updater
sudo systemctl is-active mydns-updater.service
sudo systemctl is-active mydns-updater-healthcheck.timer
```

両方 `active` になれば成功です。新しい起動では、それまでの監視の失敗回数をリセットします。

## 4. 設定変更と1時間ごとの通知を確認する

共通設定を開きます。

```sh
sudo nano /etc/mydns-updater/mydns.conf
```

`CHECK_INTERVAL=300` へ変更し、`FORCE_UPDATE_INTERVAL=3600` は試験用に残します。DEBUGは最初は1のままにします。

サービスを再起動せず、次の確認周期以降に約5分ごとのCHECK/SKIPログになることを確認します。必要ならDEBUG=0へ変更し、詳細ログが止まることも確認します。

```sh
sudo journalctl -u mydns-updater -f
```

定期通知は「サービス起動から」ではなく、アカウントごとの前回成功から1時間を過ぎた次の周期です。各アカウントの `MyDNS update: OK` が出れば成功です。

## 5. Ubuntu再起動後の自動起動を確認する

同じアカウントの既存環境を停止したまま行います。更新サービスのOS起動時の自動起動を有効にします。

```sh
sudo systemctl enable mydns-updater
sudo reboot
```

SSHは切断されます。起動が終わるのを待ち、再び端末またはSSHで接続します。VMの場合、接続できなければVMの画面でIPを確認します。

```sh
sudo systemctl is-active mydns-updater.service
sudo systemctl is-active mydns-updater-healthcheck.timer
sudo journalctl -u mydns-updater -b -n 30 --no-pager
```

両方activeで、今回の起動ログが確認できれば成功です。状態を引き継ぐため、IP不変・期限前なら直後に通知成功ログが出なくても正常です。

ここで試すのはUbuntu内の自動起動です。NAS本体を再起動する必要はありません。

---

## 6. 結果を保存する

Ubuntuで次を実行します。手順2で保存した再起動前の記録は上書きせず残します。Git以外で取得した場合は最後のコマンドを省略し、使用したZIP名・取得元・版を別に記録してください。

```sh
mkdir -p ~/mydns-test-results
sudo journalctl -u mydns-updater --since today --no-pager > ~/mydns-test-results/updater.log
sudo journalctl -t mydns-updater-healthcheck --since today --no-pager > ~/mydns-test-results/monitor.log
sudo systemctl list-timers --all mydns-updater-healthcheck.timer > ~/mydns-test-results/timer.txt
git -C ~/mydns-updater rev-parse HEAD > ~/mydns-test-results/commit.txt
```

Windowsへ持ち帰る場合は、**WindowsのPowerShell**で実行します。ユーザー名・IPを置き換えてください。

```text
scp -r tester@192.168.1.50:~/mydns-test-results "$HOME\Downloads"
```

ログにはIPや表示用ドメインが含まれます。公開する場合はその部分を確認してください。

## 7. Linux側を止めてDockerへ戻す

手順2で一時停止したままの場合は、先にCONTで再開してください。

Ubuntuで監視と更新を停止し、自動起動も無効にします。

```sh
sudo systemctl disable --now mydns-updater-healthcheck.timer
sudo systemctl disable --now mydns-updater
sudo systemctl is-active mydns-updater
```

inactiveを確認したら、試験前の環境へ戻す場合は元の更新サービスを再開します。SynologyではContainer Managerで元のプロジェクトを開始します。削除や再構築は不要です。

Ubuntu VMも止める場合は、Ubuntuで次を実行します。

```sh
sudo poweroff
```


## 確認記録

- 使用したコードのコミット番号または取得元・版
- 各アカウントの通知成功と状態ファイル生成
- 手動ヘルスチェックのHEALTHYとタイマーの定期実行
- 一時停止後のUNHEALTHY、同じ異常のログ抑制、再開後のRECOVERED
- 手動停止・開始時のタイマー連動
- 設定再読み込みと定期通知
- OS再起動後の自動起動と状態引き継ぎ
- 試験終了後の停止、または継続運用への切り替え

継続運用する場合は手順7の停止操作は行わず、試験用に変えた値を希望する運用設定へ戻します。既定値はCHECK_INTERVAL=300、FORCE_UPDATE_INTERVAL=86400、DEBUG=0です。
