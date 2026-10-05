# Linux：再起動確認・記録・試験終了

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。[取得する版の確認](current-version.md) ／ [試験コース](test-start.md)

選んだコースの試験が終わった後、Ubuntuで上から順に行います。
監視・復帰の異常時ログは、直前の専用ページで保存済みです。

## 1. OS再起動前に記録を保存する

再起動後に前のログが残るかはOS設定によるため、先に保存します。

```sh
mkdir -p ~/mydns-test-results
sudo journalctl -u mydns-updater -b --no-pager > ~/mydns-test-results/updater-before-reboot.log
ls -l ~/mydns-test-results/updater-before-reboot.log
```

**確認：** ファイルが表示されます。内容の確認には `less ~/mydns-test-results/updater-before-reboot.log` を使い、qで閉じます。

## 2. Ubuntu再起動後の自動起動を確認する

同じアカウントの既存環境は停止したまま行います。
更新サービスの自動起動を有効にします。直前の試験でサービスを停止した状態でも、この操作は行えます。

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

追加したタイマーと、その実行記録をまとめて確認します。

```sh
sudo systemctl list-timers --all 'mydns-updater-*.timer'
sudo journalctl -u 'mydns-updater-*.service' -b -n 30 --no-pager
```

| 選んだコース | 期待する結果 |
| --- | --- |
| L1 監視のみ | mydns-updater-healthcheck.timerに次回予定があり、healthcheck.serviceの正常終了記録がある |
| L2 自動復帰 | mydns-updater-recovery.timerに次回予定があり、recovery.serviceの正常終了記録がある |
| L0 追加監視なし | タイマーは0件。追加サービスの記録がなくても正常 |

L1・L2の初回実行前は、30〜60秒待って同じ確認をします。
`Deactivated successfully` は1回の検査の正常終了です。予定だけで成功とは判断しません。

## 3. 結果を保存する

```sh
mkdir -p ~/mydns-test-results
sudo journalctl -u mydns-updater -b --no-pager > ~/mydns-test-results/updater.log
git -C ~/mydns-updater rev-parse HEAD > ~/mydns-test-results/commit.txt
ls -l ~/mydns-test-results
```

Gitの取得先を変えた場合はパスを合わせます。ZIPならgitの行を省略し、取得元・版を控えます。
updater.logとcommit.txtが空ではなく、今回の更新日時になっていることを確認します。

```sh
sudo systemctl list-timers --all 'mydns-updater-*.timer' > ~/mydns-test-results/timer.txt
sudo journalctl -u 'mydns-updater-*.service' -b --no-pager > ~/mydns-test-results/timer-services.log
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

## 4. 試験を終了する

開発試験はここで停止して終了します。更新サービスに連動して、追加したタイマーも停止します。
設定・state・復帰履歴は削除しません。

```sh
sudo systemctl disable --now mydns-updater
sudo systemctl is-active mydns-updater
```

**成功：** inactiveなら停止しています。この場面でのinactiveは期待した結果で、終了コードが0以外でも正常です。
タイマーの停止も確認します。

```sh
sudo systemctl list-timers --all 'mydns-updater-*.timer'
```

追加したタイマーに次回予定がないことを確認します。Linux側の停止後に、元のNASやDockerの更新処理を再開します。

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
| updater-before-reboot.log | このページで保存した、OS再起動前の更新ログ。再起動後に古いログが残らない場合の確認用 |
| monitor-before-reboot.log | 監視のみの試験で保存した異常・復旧の記録。`UNHEALTHY` の後に `RECOVERED` があるかを、時刻とともに確認 |
| monitor-service-before-reboot.log | 再起動前の監視サービスの実行記録。監視が呼ばれ、正常終了したか、実行エラーがないかを見る |
| recovery.log | 自動復帰を選んだ場合の記録。RESTART_ATTEMPTの後にRECOVEREDがあるかを確認 |
| timer-services.log | OS再起動後の追加サービス実行記録。予定だけでなく実際の実行と正常終了を確認 |
| timer.txt | 保存時点の監視予定。`NEXT` は次回、`LAST` は前回の実行時刻。予定の確認であり、検査成功の証明ではない |
| commit.txt | 試したコードを特定する番号。読み解かず、そのまま確認記録として残す |

監視を使わない場合は監視用の記録は作りません。
正常な間は監視の独自ログが増えないので、監視のログが `No entries` の場合もあります。ただし、それだけでは「正常だった」と「監視していなかった」を区別できません。監視サービスの実行記録と、監視のみの試験の異常・復旧の記録も確認します。

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
- 試験終了後の停止と元の運用環境への切り替え
