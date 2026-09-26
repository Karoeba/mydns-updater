# Linuxの動作確認手順

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。始める前に[取得する版と更新時の確認](current-version.md)を確認してください。

[資料一覧](README.md) ／ [Linux導入手順](linux.md) ／ [模擬テストの説明](testing.md)

**この資料は、実アカウントを設定して起動した後の詳しい確認です。**
まだプログラムを配置していない場合は、先に[Linux導入手順の1〜5](linux.md)を終えてください。
導入前の模擬テストとは別で、ここでは実際にMyDNS.JPへ通知します。

Ubuntuの端末で行います。NAS本体のSSHやDockerコンテナ内では実行しません。
同じ実アカウントを使うNAS・Docker側は停止したままにします。

順番は、**通常動作 → 設定変更と定期通知 → 必要な監視機能 → OS再起動 → 記録・終了**です。
自動復帰を使う場合と、監視だけを使う場合は手順3で分かれます。

## 1. 通常動作を確認する

試験中は経過を見やすくするため、共通設定の該当行を変更します。重複追加はしません。

```sh
sudo nano /etc/mydns-updater/mydns.conf
```

```ini
CHECK_INTERVAL=60
FORCE_UPDATE_INTERVAL=3600
DEBUG=1
```

保存した値を確認します。IDやパスワードは表示しません。

```sh
sudo grep -E '^(CHECK_INTERVAL|FORCE_UPDATE_INTERVAL|DEBUG)=' /etc/mydns-updater/mydns.conf
```

**確認：** 上の3項目が、同じ値で1行ずつ表示されます。
設定は次の確認周期で反映されます。変更前が300秒なら、最大でその待ち時間が残るため、すぐに1分間隔へ変わらないことがあります。

```sh
sudo journalctl -u mydns-updater -n 50 --no-pager
sudo ls -l /var/lib/mydns-updater/state.conf
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
```

**成功：** 起動ログがv1.11.0、CHECKが約1分間隔、state.confが存在し、HEALTHYと表示されます。
各アカウントの通知成功は `MyDNS update: OK` で確認します。
既存stateを引き継いだ場合は、通知期限前のSKIPは正常です。手順2の定期通知まで確認します。

エラーがある場合は、その内容を解決してから手順2へ進みます。

## 2. 設定変更・定期通知・状態の引き継ぎを確認する

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


通知成功を確認したらDEBUG=1に戻し、状態の引き継ぎを試します。
設定を保存し、次の周期で詳細ログが出た後、次を実行します。

```sh
sudo systemctl restart mydns-updater
sudo journalctl -u mydns-updater -n 30 --no-pager
```

**成功：** 新しいSTARTUPがあり、IP不変・通知期限前ならSKIPになります。
起動直後でまだ結果がなければ、少し待ってログ表示だけを再実行します。
state.confを消して試す必要はありません。

## 3. 監視または自動復帰を選んで確認する

**次の3つから1つ選びます。すべてを続けて実行する手順ではありません。**

| 選択 | 進む場所 |
| --- | --- |
| 自動復帰を使う（今回の自動復帰まで含む検証はこちら） | 3-A |
| 異常の記録だけを使う | 3-B |
| どちらも使わない | 手順4へ |

### 3-A. 自動復帰を使う場合

[Linux自動復帰の手順](linux-recovery.md)を「始める前に」から進めます。
その手順の4-4で、手動停止を維持することまで確認します。
**そこで元のDockerへ戻さず、この資料の手順4へ戻ってください。**
下の3-Bは実行しません。自動復帰側に監視処理があるため、監視専用タイマーの導入は不要です。

### 3-B. 定期監視だけを使う場合

先に[定期監視の配置・有効化](linux.md#定期監視を有効にする)を行い、タイマーの次回時刻と実行記録を確認してから、この位置へ戻ります。

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

手順2ではCHECK_INTERVAL=300へ戻しているため、検出には数分以上かかります。試験のため60へ変更し、CHECKログで反映を確認した場合は、進行期限と連続失敗の判定を含めて数分、目安として最大5分程度待ちます。負荷などで前後します。

```text
[ERROR] [HEALTH_MONITOR] UNHEALTHY; consecutive_failures=3; ...
```

これが1回表示され、その後同じ異常が続いても繰り返し表示されなければ想定どおりです。自動再起動は行いません。

**正常な試験の流れ：** 異常ログを確認したらCtrl+Cで表示を終了し、次で再開します。

**異常ログが出ない、または中断する場合：** 一時停止したままにせず、同じCONT操作で再開します。以後の記録は成功扱いにせず、状態とログを確認してください。

```sh
sudo systemctl kill --kill-whom=main --signal=CONT mydns-updater.service
```

再びログを見ます。

```sh
sudo journalctl -t mydns-updater-healthcheck -f
```

次の処理進行と監視を待ちます。CHECK_INTERVAL=60なら1〜2分程度、300なら5分以上かかる場合があります。次が復旧の目印です。

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


**監視の試験に成功したら手順4へ進みます。自動復帰の試験を続けて重ねる必要はありません。**

## 4. OS再起動前に記録を保存する

再起動後に前のログが残るかはOS設定によるため、先に保存します。

```sh
mkdir -p ~/mydns-test-results
sudo journalctl -u mydns-updater -b --no-pager > ~/mydns-test-results/updater-before-reboot.log
ls -l ~/mydns-test-results/updater-before-reboot.log
```

**確認：** ファイルが表示されます。内容の確認には `less ~/mydns-test-results/updater-before-reboot.log` を使い、qで閉じます。

**自動復帰を選んだ場合だけ：**

```sh
sudo journalctl -t mydns-updater-recovery -b --no-pager > ~/mydns-test-results/recovery.log
grep -E 'RESTART_ATTEMPT|RECOVERED' ~/mydns-test-results/recovery.log
```

**成功：** 今回の試験時刻のRESTART_ATTEMPTと、その後のRECOVEREDが表示されます。
監視だけを選んだ場合は、3-Bで保存したUNHEALTHY・RECOVEREDの記録を使います。

## 5. Ubuntu再起動後の自動起動を確認する

同じアカウントの既存環境は停止したまま行います。
更新サービスの自動起動を有効にします。手順3-Aでサービスを停止した状態でも、この操作は行えます。

```sh
sudo systemctl enable mydns-updater
sudo systemctl is-enabled mydns-updater
```

**確認：** `enabled` なら続けます。

```sh
sudo reboot
```

SSHは切断されます。Ubuntuの起動後に再接続します。NAS本体を再起動する必要はありません。

```sh
sudo systemctl is-active mydns-updater
sudo journalctl -u mydns-updater -b -n 30 --no-pager
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
```

**成功：** active、今回のSTARTUP、HEALTHYを確認します。
起動直後なら少し待ち、確認コマンドを再実行します。状態を引き継ぐため、通知期限前のSKIPは正常です。

**自動復帰を選んだ場合だけ：**

```sh
sudo systemctl is-active mydns-updater-recovery.timer
sudo systemctl list-timers --all mydns-updater-recovery.timer
sudo journalctl -u mydns-updater-recovery.service -b -n 20 --no-pager
```

**監視だけを選んだ場合だけ：**

```sh
sudo systemctl is-active mydns-updater-healthcheck.timer
sudo systemctl list-timers --all mydns-updater-healthcheck.timer
sudo journalctl -u mydns-updater-healthcheck.service -b -n 20 --no-pager
```

追加したタイマーがactiveで次回時刻があり、初回実行後のサービスログに正常終了があれば成功です。
初回前でNo entriesなら、30〜60秒程度待って同じログ確認を再実行します。
監視サービスの `Deactivated successfully` は1回の確認の正常終了で、タイマーの停止ではありません。
どちらも追加していない場合は、これらのタイマー確認は不要です。

## 6. 結果を保存する

```sh
mkdir -p ~/mydns-test-results
sudo journalctl -u mydns-updater -b --no-pager > ~/mydns-test-results/updater.log
git -C ~/mydns-updater rev-parse HEAD > ~/mydns-test-results/commit.txt
ls -l ~/mydns-test-results
```

Gitの取得先を変えた場合はパスを合わせます。ZIPならgitの行を省略し、取得元・版を控えます。
updater.logとcommit.txtが空ではなく、今回の更新日時になっていることを確認します。

**自動復帰を選んだ場合だけ：**

```sh
sudo systemctl list-timers --all mydns-updater-recovery.timer > ~/mydns-test-results/timer.txt
```

**監視だけを選んだ場合だけ：**

```sh
sudo journalctl -t mydns-updater-healthcheck --no-pager > ~/mydns-test-results/monitor.log
sudo systemctl list-timers --all mydns-updater-healthcheck.timer > ~/mydns-test-results/timer.txt
```

ファイルの意味は[保存した記録の見方](#保存した記録の見方)を参照してください。

<details>
<summary>必要な場合だけ：記録をWindowsへコピーする</summary>

Ubuntuのユーザー名とIPアドレスを実際の値に置き換え、**WindowsのPowerShell**で実行します。

```text
scp -r tester@192.168.1.50:~/mydns-test-results "$HOME\Downloads"
```

WindowsのDownloads内にmydns-test-resultsがあることを確認します。
Ubuntu側でこのWindows用コマンドを実行しないでください。

</details>

## 7. Linux側を止めてDockerへ戻す

**継続運用する場合：** この節の停止操作は行いません。試験用の値を希望する運用設定へ戻します。
既定値はCHECK_INTERVAL=300、FORCE_UPDATE_INTERVAL=86400、DEBUG=0です。

**試験を終えて元の環境へ戻す場合だけ：** 追加した機能に応じて停止し、その後に更新サービスを停止します。

自動復帰を追加した場合だけ：

```sh
sudo systemctl disable --now mydns-updater-recovery.timer
sudo systemctl stop mydns-updater-recovery.service
```

監視だけの機能を追加した場合だけ：

```sh
sudo systemctl disable --now mydns-updater-healthcheck.timer
sudo systemctl stop mydns-updater-healthcheck.service
```

試験終了を選んだ場合は、最後に次を実行します。

```sh
sudo systemctl disable --now mydns-updater
sudo systemctl is-active mydns-updater
```

**成功：** inactiveなら停止しています。この場面でのinactiveは期待した結果で、終了コードが0以外でも正常です。
Linux側の停止後に、元のNASやDockerの更新処理を再開します。

<details>
<summary>必要な場合だけ：Ubuntu VMの電源を切る</summary>

記録のコピーを終え、VMも使い終えた場合だけ実行します。

```sh
sudo poweroff
```

</details>

## 保存した記録の見方

記録は、テスト結果を後から確認したり、不具合を相談したりするために残します。Windowsではメモ帳などで開けます。

| ファイル | 記録していること・見るところ |
| --- | --- |
| updater.log | 更新処理のログ。日時とアカウント番号を見て、`MyDNS update: OK`（通知成功）、`STARTUP`（起動）、`SKIP`（更新不要）を確認 |
| updater-before-reboot.log | 手順4で保存した、OS再起動前の更新ログ。再起動後に古いログが残らない場合の確認用 |
| monitor-before-reboot.log | 手順3-Bで保存した異常・復旧の記録。`UNHEALTHY` の後に `RECOVERED` があるかを、時刻とともに確認 |
| monitor-service-before-reboot.log | 再起動前の監視サービスの実行記録。監視が呼ばれ、正常終了したか、実行エラーがないかを見る |
| recovery.log | 自動復帰を選んだ場合の記録。RESTART_ATTEMPTの後にRECOVEREDがあるかを確認 |
| monitor.log | 保存時点で残っている異常・復旧の記録。再起動前の記録が含まれない場合は上記の別保存を使う |
| timer.txt | 保存時点の監視予定。`NEXT` は次回、`LAST` は前回の実行時刻。予定の確認であり、検査成功の証明ではない |
| commit.txt | 試したコードを特定する番号。読み解かず、そのまま確認記録として残す |

監視を使わない場合は監視用の記録は作りません。
正常な間は監視の独自ログが増えないので、monitor.logが `No entries` の場合もあります。ただし、それだけでは「正常だった」と「監視していなかった」を区別できません。監視サービスの実行記録と、手順3-Bの異常・復旧の記録も確認します。

ログ先頭のOS側の時刻と、本文のJSTなどの時刻は、設定によって表示が異なります。時刻の基準をそろえて見比べてください。ヘルスチェックの正常とMyDNS.JPへの通知成功も別なので、通知はupdater.logで確認します。

記録は保存時点の内容で、自動更新されません。確認が済んだ後にこの記録フォルダーを削除しても、運用には影響しません。設定や更新履歴を保存する場所とは別です。共有時はIPやドメイン名を確認し、実際の設定ファイルやパスワードは添付しないでください。

## 確認記録

- 使用したコードのコミット番号または取得元・版
- 各アカウントの通知成功と状態ファイル生成
- 手動ヘルスチェックのHEALTHY
- 監視だけを選んだ場合：定期実行、一時停止後のUNHEALTHY、手動再開後のRECOVERED、停止・開始の連動
- 自動復帰を選んだ場合：定期実行、RESTART_ATTEMPTからRECOVERED、手動停止の維持
- 設定再読み込みと定期通知
- OS再起動後の自動起動と状態引き継ぎ
- 試験終了後の停止、または継続運用への切り替え

継続運用する場合は手順7の停止操作は行わず、試験用に変えた値を希望する運用設定へ戻します。既定値はCHECK_INTERVAL=300、FORCE_UPDATE_INTERVAL=86400、DEBUG=0です。
