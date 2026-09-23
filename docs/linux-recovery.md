# Linuxで自動復帰を有効にする

この機能はv1.8.0で追加したLinux直接実行向けの機能です。初期状態では無効です。
先に [Linux導入手順](linux.md) で通常の更新とヘルスチェックが動くことを確認してください。

DockerとSynology Container Managerの設定は、この手順では変更しません。
定期監視だけの機能は事前導入不要です。自動復帰自身が進行を確認します。

**進む順番：** 導入済み確認 → 1 ファイル確認 → 2 配置 → 3 定期実行確認 → 4 自動復帰の試験。
[Linuxの動作確認](linux-testing.md)から来た場合は、4-4まで終えたら同資料の手順4へ戻ります。
通常運用の導入だけなら、手順3で登録を確認した後、手順4の試験を行うか選びます。

## どんなときに再起動するか

約30秒ごとに確認し、次の条件で更新サービスだけを再起動します。Linux自体は再起動しません。

| 条件・制限 | 動作 |
| --- | --- |
| 処理の進行期限超過が3回連続 | 再起動を試す |
| 通信・認証・設定エラー | 自動復帰の対象外。通常ログを見て対処する |
| 進行記録がない・壊れている、確認処理自体が失敗 | 再起動しない |
| 前回の再起動要求から10分未満 | 待つ |
| 直近1時間ですでに3回要求した | 自動復帰を止め、手動解除を待つ |
| 利用者がサービスを停止した | 停止したままにする |

「3回」は進行期限を過ぎた後の確認回数です。待機時間なども考慮するため、処理停止から90秒で必ず再起動するわけではありません。

再起動の要求が失敗した場合も1回に数えます。
正常に戻っても再起動履歴は消さず、サービスやOSを再起動しても引き継ぎます。
上限に達して停止した自動復帰は、時間が経っても勝手には再開しません。

履歴はrootだけが読み書きできる `/var/lib/mydns-updater-recovery/status` に保存します。
アカウントの通知成功を記録する `state.conf` とは別です。
時刻が60秒を超えて逆戻りした場合も、自動復帰を止めて確認を待ちます。

## 異常終了時の再起動との違い

既存の `Restart=on-failure` は、プログラムが異常終了したときの再起動です。
今回の自動復帰は、プログラムが残ったまま処理が止まった場合を扱います。

v1.8.0の更新サービス設定では、異常終了後も10分待って再起動します。
systemd側にも1時間に4回までの起動制限を設けます。この4回には初回・手動・自動の起動が含まれます。
自動復帰の「直近1時間で3回」とは別の制限なので、手動操作などが多い場合は先にこちらの制限に達することがあります。

## 始める前に：Linux版が導入済みか確認する

```sh
systemctl status mydns-updater.service --no-pager
```

| 表示 | 進み方 |
| --- | --- |
| `Loaded: loaded` と `active (running)` | 手順1へ進む |
| `Loaded: loaded` と `inactive (dead)` | 導入済みで停止中。手順1へ進む |
| `could not be found` | 未導入。[Linux導入手順](linux.md)で初回導入と手動ヘルスチェックを済ませてから、ここへ戻る |
| `failed` | ログを確認して既存の問題を解決してから進む |

Docker版を導入していても、Linux直接実行版のサービスが用意されているとは限りません。

## 1. 配布ファイルを確認する

以下はLinux側で実行します。開発中の版を試す場合は、GitHubで対象PRのブランチを選んで取得してください。mainにまだ入っていない変更もあるため、バージョンを確認します。
展開したフォルダーの直下へ移動してから確認します。

```sh
pwd
ls update.sh lib/*.sh health-recover.sh deploy/linux/mydns-updater.service deploy/linux/mydns-updater-recovery.service deploy/linux/mydns-updater-recovery.timer
grep '^VERSION=' update.sh
```

5つのファイルとlib内の6ファイルが表示され、バージョンが `1.10.0` であることを確認します。
`No such file or directory` が出た場合は、今いるフォルダーや取得した版を確認してください。

## 追加するファイルの配置

```text
/
├── usr/local/lib/mydns-updater/
│   ├── update.sh                               ← 導入済みの起動プログラム
│   ├── lib/                                    ← 導入済みの共通処理
│   └── health-recover.sh                       ← 今回追加
├── etc/systemd/system/
│   ├── mydns-updater.service                   ← 更新処理の起動設定
│   ├── mydns-updater-recovery.service          ← 復帰判断を1回行う設定
│   └── mydns-updater-recovery.timer            ← 定期的に呼び出す設定
└── var/lib/mydns-updater-recovery/
    └── status                                 ← 復帰履歴。自動生成
```

通知成功を保存する/var/lib/mydns-updater/state.confとは別です。

## 2. 停止してファイルを配置する

独自の配置先や実行ユーザーを使っている場合は、サービス設定をそのまま上書きせず、既存の指定を残して変更点を反映してください。
自動復帰サービスの `MYDNS_UPDATER`、`MYDNS_HEALTH_FILE`、`MYDNS_RECOVERY_USER` も合わせます。

自動復帰がすでに有効な場合だけ、先に末尾の「無効にする・更新する」に従って停止します。初回導入では不要です。
設定ファイルと通知成功の記録はそのまま使います。
更新サービスを停止し、プログラムとサービス設定をコピーします。

```sh
sudo systemctl stop mydns-updater
sudo install -o root -g root -m 644 update.sh /usr/local/lib/mydns-updater/update.sh
sudo install -d -o root -g root -m 755 /usr/local/lib/mydns-updater/lib
sudo install -o root -g root -m 644 lib/*.sh /usr/local/lib/mydns-updater/lib/
sudo install -o root -g root -m 644 health-recover.sh /usr/local/lib/mydns-updater/health-recover.sh
sudo install -o root -g root -m 644 deploy/linux/mydns-updater.service /etc/systemd/system/mydns-updater.service
sudo install -o root -g root -m 644 deploy/linux/mydns-updater-recovery.service /etc/systemd/system/mydns-updater-recovery.service
sudo install -o root -g root -m 644 deploy/linux/mydns-updater-recovery.timer /etc/systemd/system/mydns-updater-recovery.timer
sudo systemctl daemon-reload
sudo systemctl start mydns-updater
```

配置と起動を確認します。

```sh
ls -l /usr/local/lib/mydns-updater/lib/*.sh /usr/local/lib/mydns-updater/health-recover.sh /etc/systemd/system/mydns-updater-recovery.service /etc/systemd/system/mydns-updater-recovery.timer
sudo systemctl status mydns-updater --no-pager
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
```

ファイルの所有者・グループが `root root`、権限が `-rw-r--r--` であること、
サービスが `active (running)`、確認結果が `HEALTHY: updater progressing or waiting` であることを確認します。

サービスの再起動操作には管理者権限が必要なため、自動復帰サービスはrootで動きます。
更新処理とヘルスチェックの判定は、引き続き専用ユーザーで実行します。

## 3. 自動復帰を有効にする

```sh
sudo systemctl enable --now mydns-updater-recovery.timer
sudo systemctl is-enabled mydns-updater-recovery.timer
sudo systemctl list-timers --all mydns-updater-recovery.timer
sudo journalctl -u mydns-updater-recovery.service --no-pager -n 20
```

`enabled` と表示され、タイマー一覧に次回実行時刻が出れば設定できています。
初回実行は約30秒後です。No entriesなら30〜60秒程度待ち、ログ確認を再実行します。
サービスの実行記録が繰り返され、エラーがないことも確認します。
`Deactivated successfully` は1回の確認の正常終了であり、タイマーの停止ではありません。

自動復帰サービスは確認のたびに終了するため、`inactive (dead)` だけで異常とは限りません。
正常が続いている間は、独自のログを出しません。

以後は更新サービスの起動・停止に合わせてタイマーも起動・停止します。
OS起動時にも更新サービスを起動するには、Linux導入手順の自動起動設定が必要です。

## 4. 動作を試す

この試験では更新処理を一時停止します。
同じアカウントを使うNASなどを同時に動かさず、Linuxの端末を閉じずに確認してください。

### 4-1. 正常な状態と起動番号を確認する

まず、現在の起動を識別する番号と正常状態を確認します。

```sh
sudo systemctl show mydns-updater --property=InvocationID --value
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
```

番号を控え、`HEALTHY` が表示されたら4-2へ進みます。

### 4-2. 一時停止して自動復帰を待つ

以下で一時停止します。正常な試験ではCONTによる手動再開は行わず、自動復帰を待ちます。

```sh
sudo systemctl kill --kill-whom=main --signal=STOP mydns-updater
sudo journalctl -t mydns-updater-recovery --since '1 minute ago' -f
```

標準の確認間隔が300秒なら、検出まで数分かかります。
ログに `RESTART_ATTEMPT`、`RESTART_REQUESTED`、その後 `RECOVERED` が出るのを待ちます。
`RESTART_REQUESTED` だけでは、復帰成功とは判断しません。

**`RECOVERED` が出たら → 4-3へ進みます。**

**復帰しない、または試験を中断する場合だけ → 下の「困ったときだけ：自動復帰しない・試験を中断する」を開いてください。**

### 4-3. 復帰後の状態を確認する

Ctrl+Cでログ表示を終え、もう一度確認します。

```sh
sudo systemctl show mydns-updater --property=InvocationID --value
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
sudo journalctl -u mydns-updater --no-pager -n 30
sudo systemctl list-timers --all mydns-updater-recovery.timer
```

起動番号が変わり、`HEALTHY` に戻り、更新サービスの新しい起動ログがあれば成功です。
タイマーも継続していることを確認します。
通知期限前は通知成功ログが増えないことがあります。起動後の確認周期も見たい場合は `DEBUG=1` を使います。

正常を確認できたら4-4へ進みます。

### 4-4. 手動停止したままになることを確認する

最後に、手動停止を尊重することも確認します。

```sh
sudo systemctl stop mydns-updater
sudo systemctl is-active mydns-updater
sudo systemctl is-active mydns-updater-recovery.timer
```

どちらも `inactive` なら正常です。この確認コマンドはinactiveの場合に終了コードが0以外になります。
1分ほど待って、次の2行をもう一度実行します。

```sh
sudo systemctl is-active mydns-updater
sudo systemctl is-active mydns-updater-recovery.timer
```

両方が引き続き `inactive` なら、この自動復帰試験は完了です。
**Linuxの動作確認から来た場合は、停止した状態のまま[手順4](linux-testing.md#4-os再起動前に記録を保存する)へ戻ります。まだ元のDockerへ戻しません。**
自動復帰だけを試していた場合は、続け方をどちらか選びます。

- **NASなどの運用に戻す：** Linux側は停止したまま、元の環境を起動します。
- **Linux側で運用を続ける：** 同じアカウントの別環境を停止したまま、`sudo systemctl start mydns-updater` を実行します。

**正常に完了した場合、以下のトラブル対応・制限解除・無効化は実行不要です。**

<details>
<summary>困ったときだけ：自動復帰しない・試験を中断する</summary>

正常に復帰した場合は、この操作を行いません。
ログ表示中ならCtrl+Cで終了し、一時停止を解除して状況を確認します。

```sh
sudo systemctl kill --kill-whom=main --signal=CONT mydns-updater
sudo systemctl status mydns-updater --no-pager
sudo journalctl -u mydns-updater-recovery.service --no-pager -n 50
```

すでにサービスが停止していてCONTを送れない場合は、ログを確認してから手動で起動します。
短時間に試験を繰り返すと10分待機や回数制限にかかるため、失敗と決めつけずログを確認してください。


ここでCONTにより正常へ戻っても、自動復帰の試験に成功したことにはなりません。
原因を解決してから4-1へ戻るか、更新サービスを停止して試験を終了します。

</details>

## ログの意味と制限の解除

```sh
sudo journalctl -t mydns-updater-recovery --no-pager -n 50
```

| 表示 | 意味・対応 |
| --- | --- |
| RESTART_ATTEMPT | 処理停止を検出し、再起動を試す。回数も表示 |
| RESTART_REQUESTED | systemdが要求を受け付けた。復帰確認を待つ |
| RECOVERED | 再起動要求後に正常な進行を確認した |
| RESTART_REQUEST_FAILED | 要求失敗。更新サービスと自動復帰サービスのログを確認 |
| BLOCKED / RESTART_LIMIT | 回数上限。原因を調べ、解決後に手動解除 |
| BLOCKED / CLOCK_MOVED_BACKWARD | 時計が逆戻りした。時刻を確認してから手動解除 |
| invalid recovery state | 履歴を読めない。保存先・権限を確認し、必要なら手動解除 |

### 制限を解除する必要がある場合だけ

**通常の試験後に実行する手順ではありません。** 上限到達や履歴の問題を確認し、原因を修正した場合だけ実行します。
再試行を繰り返すために履歴を消さないでください。

原因を確認・修正した後で、制限を解除します。
先にタイマーと自動復帰サービスを止め、実行中の操作が終わるのを待ちます。

```sh
sudo systemctl stop mydns-updater-recovery.timer
sudo systemctl stop mydns-updater-recovery.service
sudo sh /usr/local/lib/mydns-updater/health-recover.sh --reset
sudo systemctl reset-failed mydns-updater
sudo systemctl start mydns-updater
sudo systemctl start mydns-updater-recovery.timer
```

`RESET` と表示されれば、自動復帰の履歴と制限が解除されています。
`--reset` 自体は更新サービスを起動しません。
保存先を独自に変えている場合は、この手動コマンドにも `MYDNS_RECOVERY_DIR` の指定が必要です。

## 無効にする・更新する

**自動復帰を使い続ける場合、この節の操作は不要です。** 無効化またはファイル更新を行うときだけ使います。

自動復帰だけを無効にする場合：

```sh
sudo systemctl disable --now mydns-updater-recovery.timer
sudo systemctl stop mydns-updater-recovery.service
```

更新プログラムや、別に設定した定期監視はそのまま動きます。
すでに受け付けられた再起動要求を取り消す操作ではありません。

自動復帰のファイルを更新する場合も、先に上記で無効にしてからコピーします。
サービス設定を変更したら `daemon-reload` を行い、手順3で再度有効にしてください。
