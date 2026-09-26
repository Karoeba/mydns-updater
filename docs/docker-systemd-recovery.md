# 通常のDockerの自動復帰を設定する

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。始める前に[取得する版と更新時の確認](current-version.md)を確認してください。

[Dockerの導入・運用](docker.md) ／ [共通の条件とログの意味](docker-recovery.md)

Ubuntuなど、systemdを使うDockerホスト向けです。Ubuntu VMの場合も、Ubuntu側の端末で実行します。
SynologyのNAS本体には、このサービスを導入しません。

systemdの「サービス」は監視コマンドを1回実行する設定、「タイマー」はそれを繰り返す設定です。
ここで追加するのはDocker用の監視です。Linux直接実行版のmydns-updater.serviceは使いません。

**進む順番：** 通常の通知・healthyを確認 → 1 対象確認 → 2 配置 → 3〜4 定期実行 → 5 自動復帰の試験。
Dockerの動作確認から来た場合は、5-4の記録まで終えて[同資料の手順7](docker-testing.md#7-記録して終了する)へ戻ります。
その場合、この資料の手順6で先に停止・切り戻しをしません。

## 追加するファイルの配置

次はコンテナ内ではなく、Ubuntuホスト上の配置です。

```text
/
├── usr/local/lib/mydns-updater/
│   └── docker-health-recover.sh
├── etc/systemd/system/
│   ├── mydns-updater-docker-recovery.service
│   └── mydns-updater-docker-recovery.timer
└── var/lib/mydns-updater-docker-recovery/
    └── status                  ← 復帰履歴。自動生成
```

更新プログラムとconfig・stateは、引き続き~/mydns-updater-docker側にあります。
監視用のファイルだけを上の場所へコピーします。

## 1. 対象とファイルを確認する

[Dockerの導入・更新手順](docker.md)で、コンテナ内のプログラム一式をv1.11.0にします。
旧mainや別の試験用フォルダーのファイルを使わないよう、取得した版も確認します。

以下はv1.11.0のファイルを置いたフォルダーで実行します。ホーム内に取得した場合の例です。

```sh
cd ~/mydns-updater-docker
pwd
grep '^VERSION=' update.sh
ls -l docker-health-recover.sh deploy/linux/mydns-updater-docker-recovery.service deploy/linux/mydns-updater-docker-recovery.timer
ps -p 1 -o comm=
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}} {{.HostConfig.RestartPolicy.Name}}' mydns-updater
sudo docker logs --tail 50 mydns-updater
```

**確認：** v1.11.0のファイル、指定した3ファイル、`systemd`、最新のSTARTUPが `v1.11.0`、`running healthy unless-stopped` が確認できれば進めます。
この版で初めて試す場合は、先に[試験専用コンテナでの確認](docker-recovery.md#本番導入前に組み合わせを試す)を行います。

## 2. 監視用ファイルを配置する

```sh
sudo install -d -m 755 /usr/local/lib/mydns-updater
sudo install -o root -g root -m 644 docker-health-recover.sh /usr/local/lib/mydns-updater/docker-health-recover.sh
sudo install -o root -g root -m 644 deploy/linux/mydns-updater-docker-recovery.service /etc/systemd/system/
sudo install -o root -g root -m 644 deploy/linux/mydns-updater-docker-recovery.timer /etc/systemd/system/
sudo systemctl daemon-reload
```

ファイルを置いた場所を確認します。

```sh
ls -l /usr/local/lib/mydns-updater/docker-health-recover.sh /etc/systemd/system/mydns-updater-docker-recovery.service /etc/systemd/system/mydns-updater-docker-recovery.timer
```

3ファイルが表示されれば配置できています。確認記録は後で `/var/lib/mydns-updater-docker-recovery/` に自動作成されます。

<details>
<summary>コンテナ名やDockerの場所を変更している場合だけ</summary>

通常の名前mydns-updaterで使う場合、この操作は不要です。
変更する場合は、root所有の `/etc/mydns-updater-docker-recovery.conf` を作り、次の例を自分の環境に合わせて記載します。

```ini
MYDNS_RECOVERY_CONTAINER=mydns-updater
MYDNS_DOCKER_BIN=/usr/bin/docker
```

サービスが毎回読み込むため、起動のたびに指定する必要はありません。
手動で監視スクリプトを呼ぶ場合は自動では読み込まれません。以下の手動確認は既定のコンテナ名と配置先を使う例です。

</details>

## 3. 一度実行してからタイマーを有効にする

```sh
sudo systemctl start mydns-updater-docker-recovery.service
sudo systemctl status mydns-updater-docker-recovery.service --no-pager
```

一度確認して終了するサービスなので、`inactive (dead)` と `status=0/SUCCESS` なら正常です。
この状態のstatusコマンドは終了コードが0以外になることがあります。表示された実行結果で判断してください。
`failed` やエラーがある場合は有効化へ進まず、ログを確認します。

```sh
sudo systemctl enable --now mydns-updater-docker-recovery.timer
sudo systemctl is-enabled mydns-updater-docker-recovery.timer
sudo systemctl list-timers --all mydns-updater-docker-recovery.timer
```

`enabled` と、タイマーの次回実行時刻（NEXT）が表示されれば登録できています。
NEXTは予定なので、実際の実行は次で確認します。

## 4. 定期実行を確認する

1〜2分待って実行します。

```sh
sudo systemctl list-timers --all mydns-updater-docker-recovery.timer
sudo stat -c '監視記録の更新時刻: %y' /var/lib/mydns-updater-docker-recovery/status
sudo journalctl -u mydns-updater-docker-recovery.service --no-pager -n 30
```

さらに1〜2分待ち、同じ3行を繰り返します。
LASTは最後にタイマーが実行された時刻です。LASTと監視記録の更新時刻が進み、サービスのエラーがなければ定期実行できています。
正常時は監視スクリプト独自のログがなく、systemdの開始・終了記録だけの場合もあります。

コンテナと監視状態も確認します。

```sh
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
sudo sh /usr/local/lib/mydns-updater/docker-health-recover.sh --status
```

`running healthy` と `consecutive=0 pending=0 blocked=0` が通常の状態です。

## 5. 定期実行による自動復帰を1回試す

ここからは任意の最終確認です。手順4までなら「定期監視が動く」、ここまで行えば「異常時の自動復帰まで動く」を確認できます。
試験中は数分以上、IP確認と通知が止まります。同じ版・設定ですでに確認済みなら繰り返す必要はありません。

### 5-1. 正常な状態を保存する

UbuntuなどDockerホスト側の端末で実行します。

```sh
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}} {{.HostConfig.RestartPolicy.Name}}' mydns-updater
sudo docker logs --tail 50 mydns-updater
sudo sh /usr/local/lib/mydns-updater/docker-health-recover.sh --status
```

`running healthy unless-stopped` と `consecutive=0 pending=0 blocked=0` を確認します。
last_attemptが0以外の場合は前回の復帰履歴があります。直前に試した場合は10分の間隔を空けてください。
上限待ちやエラーが出ている場合は、履歴を消して続けず原因を確認します。

```sh
mkdir -p ~/mydns-recovery-results
sudo docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' mydns-updater > ~/mydns-recovery-results/before.txt
cat ~/mydns-recovery-results/before.txt
```

コンテナID・開始時刻・再起動回数が1行で表示されます。これは試験前の記録です。
まだ一時停止していない、この時点で保存してください。

### 5-2. 処理を一時停止し、自動復帰を待つ

今回は `docker kill --signal=STOP` を使いません。Docker側の再起動が抑止されることがあるため、ホスト側から処理を止めます。
`docker pause` やコンテナの「停止」も、この試験とは別の操作です。

次の枠をまとめて実行します。対象コンテナの処理番号を取得して一時停止します。

```sh
sudo /bin/sh -c '
pid=$(docker inspect --format "{{.State.Pid}}" mydns-updater) || exit 1
[ "$pid" -gt 1 ] || exit 1
kill -STOP "$pid" && echo "更新処理を一時停止しました"
'
```

「更新処理を一時停止しました」が出たら、復帰ログの表示を始めます。

```sh
sudo journalctl -u mydns-updater-docker-recovery.service --since '1 minute ago' -f
```

`Starting` → `Deactivated successfully` → `Finished` が繰り返されるのは、監視が1回ずつ正常終了している表示です。
この表示だけでは自動復帰の成功ではありません。下のRECOVEREDまで待ちます。

サービスを手動実行せず、定期実行に任せて待ちます。
手動のCONTや再起動は行いません。処理の進行期限が切れ、期限超過を3回続けて確認すると復帰を試みます。

CHECK_INTERVAL=300では、待機時間と余裕時間に加えて連続検出の時間が必要です。
一時停止した瞬間から3分で復帰するとは限りません。直前の復帰試行があれば10分間隔の制限も適用されます。

**次へ進む目印：** 今回の時刻で `RESTART_ATTEMPT`、続いて `RECOVERED` が表示されます。
途中の `RESTART_REQUESTED` や `RESTART_REQUEST_UNCONFIRMED` は、まだ成功確定ではありません。
古い試験のログと混同しないよう、時刻も確認します。

RECOVEREDが出たらCtrl＋Cでログ表示だけを終了し、5-3へ進みます。
15分ほど待っても戻らない、エラーが出た、途中で中断したい場合だけ、下の「困ったときだけ」を開きます。
CHECK_INTERVALを長く設定している場合は待ち時間も長くなります。15分は失敗を断定する基準ではなく、いったん状況を確認する目安です。

### 5-3. 再起動と通常動作への復帰を確認する

```sh
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
sudo sh /usr/local/lib/mydns-updater/docker-health-recover.sh --status
sudo docker logs --since 15m --tail 50 mydns-updater
sudo docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' mydns-updater > ~/mydns-recovery-results/after.txt
cat ~/mydns-recovery-results/before.txt ~/mydns-recovery-results/after.txt
```

**合格の目印：**

- `running healthy` に戻っている。startingなら30秒ほど待って確認し直す。
- `consecutive=0 pending=0 blocked=0` に戻っている。
- コンテナIDは同じで、開始時刻が変わり、再起動回数が1増えている。
- 今回の起動ログがあり、DEBUG=1なら次の周期のIP確認も再開している。
- 復帰ログに、今回の `RESTART_ATTEMPT` と `RECOVERED` がある。

DEBUG=0ではIP不変・通知期限前のログは出ません。通知成功ログがすぐ増えないだけでは異常ではありません。
この試験では再起動するため、before.txtとafter.txtは異なるのが正常です。
以前の「手動でCONTを送り、再起動せずに戻す試験」と判定が違います。

### 5-4. 記録を保存する

```sh
sudo journalctl -u mydns-updater-docker-recovery.service --since '30 minutes ago' --no-pager > ~/mydns-recovery-results/recovery.log
sudo docker logs --since 30m mydns-updater > ~/mydns-recovery-results/updater.log 2>&1
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > ~/mydns-recovery-results/health-final.json
sudo docker version > ~/mydns-recovery-results/docker-version.txt
ls -lh ~/mydns-recovery-results
```

before.txt、after.txt、recovery.log、updater.log、health-final.json、docker-version.txtがあり、サイズが0でないことを確認します。
これは保存した時点の記録で、以後の状態を自動表示するファイルではありません。

各ファイルの意味と見る場所は、[保存した記録の見方](docker-recovery.md#保存した記録の見方)にまとめています。

メモ帳などで開けます。ファイル名ではなく中の時刻と結果で判断してください。
IPと表示用ドメインを含むため、共有時には内容を確認します。設定ファイルは試験記録に含めません。
記録の削除は運用に影響しませんが、運用中のconfig・state・監視履歴とは取り違えないでください。

Windowsへ持ち帰る場合だけ、[記録のコピー手順](docker-recovery.md#必要な場合だけ記録をwindowsへコピーする)を使います。

**実働環境での最終確認はここで完了です。** 回数上限まで繰り返す必要はありません。
試験のためにDEBUGなどを変えた場合は、運用時の値へ戻します。

<details>
<summary>困ったときだけ：自動復帰しない・途中で試験を中断する</summary>

正常にRECOVEREDまで確認できた場合は、この操作は不要です。
Ctrl＋Cでログ表示を終え、次で一時停止を解除します。

```sh
sudo /bin/sh -c '
pid=$(docker inspect --format "{{.State.Pid}}" mydns-updater) || exit 1
[ "$pid" -gt 1 ] || exit 1
kill -CONT "$pid" && echo "一時停止の解除を送りました"
'
sudo journalctl -u mydns-updater-docker-recovery.service --since '30 minutes ago' --no-pager
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
```

すでに停止していてCONTを送れない場合は、ログを確認してから導入手順の開始操作を行います。
手動で解除して正常になっても、自動復帰の成功とは区別します。再試験の前に原因を確認してください。
BLOCKEDの場合も、そのまま履歴を消して試験を繰り返しません。

</details>

## 6. VMでの試験を終了する場合

**Dockerの動作確認から来た場合は、この節を実行せず[元の手順7](docker-testing.md#7-記録して終了する)へ戻ります。**
この資料だけで試験を終える場合に、以下を使います。


**VMで運用を続ける場合は、この節の停止操作は行いません。**
試験を終えてNASの運用へ戻す場合は、記録を保存してからUbuntu側を停止します。

```sh
sudo docker stop mydns-updater
sudo docker inspect --format '{{.State.Status}}' mydns-updater
```

exitedを確認し、タイマーを有効にしたまま2分ほど待ち、もう一度状態を確認します。

```sh
sudo docker inspect --format '{{.State.Status}}' mydns-updater
```

引き続きexitedなら、手動停止したコンテナを監視が勝手に起動しないことも確認できています。
確認後、VMの監視も停止します。

```sh
sudo systemctl disable --now mydns-updater-docker-recovery.timer
sudo systemctl stop mydns-updater-docker-recovery.service
sudo systemctl is-active mydns-updater-docker-recovery.timer
```

inactiveを確認してから、同じアカウントを使うNAS側を再開します。設定や監視履歴は削除不要です。

## 必要な場合だけ：制限を解除する

通常運用・正常な試験終了時には、この操作は不要です。

<details>
<summary>上限待ちの原因を直し、制限を解除する場合</summary>

ログのBLOCKEDの原因を確認・修正してから、監視を止めて解除します。

```sh
sudo systemctl stop mydns-updater-docker-recovery.timer
sudo systemctl stop mydns-updater-docker-recovery.service
sudo sh /usr/local/lib/mydns-updater/docker-health-recover.sh --reset
sudo sh /usr/local/lib/mydns-updater/docker-health-recover.sh --status
```

RESETとblocked=0を確認します。配置先や対象を変更した場合は、手動コマンドにも同じ環境変数を指定します。
解除は停止中のコンテナを起動しません。コンテナの状態を確認後、定期実行を戻します。

```sh
sudo systemctl start mydns-updater-docker-recovery.timer
```

</details>
