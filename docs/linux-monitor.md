# Linux：監視のみを導入して試す

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。[取得する版の確認](current-version.md) ／ [試験コース](test-start.md)

## 1. 配置して有効にする


このページはL1（監視のみ）専用です。自動復帰のタイマーは導入しません。
systemdのタイマーで約30秒ごとに確認できます。追加するファイルは次の3つです。

| 配布ファイル | 配置先・役割 |
| --- | --- |
| `health-monitor.sh` | `/usr/local/lib/mydns-updater/health-monitor.sh`：連続失敗と復旧を判定 |
| `deploy/linux/mydns-updater-healthcheck.service` | `/etc/systemd/system/`：監視処理の実行方法 |
| `deploy/linux/mydns-updater-healthcheck.timer` | `/etc/systemd/system/`：監視処理を呼ぶ間隔 |

ここでのserviceは、常駐する更新プログラムとは別に、1回の確認を実行する設定です。タイマーが呼ぶたびに確認し、終了します。

[基本試験](linux-testing.md)を終え、更新サービスが動いている状態で行います。
Ubuntuの端末で配置元を確認してからコピーします。

```sh
cd ~/mydns-updater
pwd
ls -l health-monitor.sh deploy/linux/mydns-updater-healthcheck.*
```

**確認：** mydns-updaterフォルダーで、スクリプトとservice・timerの3ファイルが表示されます。

```sh
sudo install -m 644 health-monitor.sh /usr/local/lib/mydns-updater/health-monitor.sh
sudo install -m 644 deploy/linux/mydns-updater-healthcheck.service /etc/systemd/system/mydns-updater-healthcheck.service
sudo install -m 644 deploy/linux/mydns-updater-healthcheck.timer /etc/systemd/system/mydns-updater-healthcheck.timer
sudo systemctl daemon-reload
sudo systemctl enable --now mydns-updater-healthcheck.timer
```

有効にすると、以後は更新サービスの起動に合わせて監視も起動します。OS起動時にも更新サービスを起動するには、最後の再起動確認の自動起動設定が必要です。

更新サービスを手動で停止するとタイマーも停止します。監視から更新サービスを起動・再起動することはありません。

### 監視結果を確認する

```sh
sudo systemctl list-timers --all mydns-updater-healthcheck.timer
sudo journalctl -t mydns-updater-healthcheck --no-pager -n 30
```

1つ目はタイマーの次回実行時刻、2つ目は監視処理のログを表示します。監視サービスは1回の確認で終了するため、`inactive (dead)` だけで異常とは限りません。

タイマーに次回予定があり、サービスの実行記録を確認できたら、次の異常検知試験へ進みます。

- 初回から正常なら、監視処理の独自ログは出しません。`No entries` だけでは監視処理の成功を確認できないため、下記のサービス実行ログも確認します。
- 3回連続で確認に失敗すると `[ERROR] [HEALTH_MONITOR] UNHEALTHY` を1回記録します。
- 異常判定後に確認が成功すると `[INFO] [HEALTH_MONITOR] RECOVERED` を1回記録します。
- 1〜2回の失敗後に成功した場合は、失敗回数をリセットし、復旧ログは出しません。

30秒は確認を呼ぶ間隔です。更新処理の進行期限には待機時間・通信制限時間と120秒の余裕が含まれるため、処理停止から90秒で必ず異常になるという意味ではありません。

失敗回数は `/run/mydns-updater-monitor/status` に保存します。OS再起動や更新サービスの新しい起動では、それまでの失敗回数を引き継ぎません。監視処理の保存先などに問題がある場合は、監視自体のエラーとして表示します。

systemdが実際に監視を呼んだ記録を確認します。初回前なら30〜60秒待ってもう一度表示します。

```sh
sudo journalctl -u mydns-updater-healthcheck.service --no-pager -n 30
```

## 2. 異常検知と手動再開を確認する

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

基本試験でCHECK_INTERVAL=300にしたため、進行期限と連続失敗の判定を含めて数分以上待ちます。15分ほど待っても異常ログが出ない場合は、下の中断時の操作で再開し、ログを確認します。

```text
[ERROR] [HEALTH_MONITOR] UNHEALTHY; consecutive_failures=3; ...
```

これが1回表示され、その後同じ異常が続いても繰り返し表示されなければ想定どおりです。自動再起動は行いません。

**正常な試験の流れ：** 異常ログを確認したらCtrl+Cで表示を終了し、次で再開します。

<details>
<summary>困ったときだけ：異常ログが出ない・中断する</summary>

一時停止したままにせず、下のCONT操作で再開します。以後の記録は成功扱いにせず、状態とログを確認してください。

</details>

```sh
sudo systemctl kill --kill-whom=main --signal=CONT mydns-updater.service
```

再びログを見ます。

```sh
sudo journalctl -t mydns-updater-healthcheck -f
```

次の処理進行と監視を待ちます。基本試験のCHECK_INTERVAL=300では5分以上かかる場合があります。次が復旧の目印です。

```text
[INFO] [HEALTH_MONITOR] RECOVERED; updater progressing or waiting
```

Ctrl+Cで表示を終了したら、**次へ進む前に**記録を保存します。

```sh
mkdir -p ~/mydns-test-results
sudo journalctl -t mydns-updater-healthcheck -b --no-pager > ~/mydns-test-results/monitor-before-reboot.log
sudo journalctl -u mydns-updater-healthcheck.service -b --no-pager > ~/mydns-test-results/monitor-service-before-reboot.log
sudo journalctl -u mydns-updater -b --no-pager > ~/mydns-test-results/updater-before-reboot.log
```

保存したログにUNHEALTHYとRECOVEREDがあることを確認します。端末に表示された結果も記録してください。再起動後のログ保持は環境によるため、最後にまとめて取得するだけでは試験時の記録が残らない場合があります。

異常ログが出なかった場合もCONTは必ず実行し、状態とログを確認してください。[Ubuntuのsystemctl説明](https://manpages.ubuntu.com/manpages/noble/man1/systemctl.1.html)

#### 手動停止・開始の連動

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


**次は[再起動確認・記録・試験終了](linux-test-finish.md)です。** 自動復帰のページは実行しません。

<details>
<summary>必要な場合だけ：定期監視を無効にする</summary>

監視を使い続ける場合は、この操作を行いません。

```sh
sudo systemctl disable --now mydns-updater-healthcheck.timer
```

更新プログラムはそのまま動き続けます。この定期監視は検知と記録を担当し、再起動や外部への通知送信は行いません。


</details>
