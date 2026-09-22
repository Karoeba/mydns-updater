# Synologyの自動復帰を設定する

[Synologyの導入・運用](synology.md) ／ [共通の条件とログの意味](docker-recovery.md)

NAS本体のSSHとDSMを使います。以下ではボリュームをvolume1、コンテナ名をmydns-updaterとしています。
配置が異なる場合は実際の場所に合わせます。Ubuntu VMの端末では行いません。

## 始める前に

v1.9.0の[開発ブランチのZIP](https://github.com/Karoeba/mydns-updater/archive/refs/heads/docker-recovery-validation.zip)を展開します。
初回の導入確認には、本番とは別の `/volume1/docker/mydns-recovery-check` に中身を置きます。

NASのSSHで次を実行し、作業場所を確認します。

```sh
cd /volume1/docker/mydns-recovery-check
pwd
ls -l update.sh docker-health-recover.sh tests/test-docker-recovery-integration.sh
```

3ファイルが表示されたら、[試験専用コンテナでの確認](docker-recovery.md#本番導入前に組み合わせを試す)を行います。
この確認を同じ版ですでに済ませた場合は繰り返さず、次へ進みます。

[Synologyの更新手順](synology.md#更新する場合)で本番のupdate.shをv1.9.0にし、起動ログを確認します。
configとstateは保持します。v1.8.0からの場合、Composeの変更はありません。

```sh
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}} {{.HostConfig.RestartPolicy.Name}}' mydns-updater
```

`running healthy unless-stopped` なら進めます。


## 1. NASにファイルを配置する

最新版のdocker-health-recover.shを、本番のupdate.shと同じフォルダーへアップロードします。
ここでは `/volume1/docker/mydns-updater` に置いたものとして説明します。

NASのSSH画面で次を実行します。

```sh
ls -l /volume1/docker/mydns-updater/docker-health-recover.sh
sudo mkdir -p /volume1/docker/mydns-recovery/state
sudo chown root:root /volume1/docker/mydns-recovery /volume1/docker/mydns-recovery/state
sudo chmod 700 /volume1/docker/mydns-recovery /volume1/docker/mydns-recovery/state
sudo cp /volume1/docker/mydns-updater/docker-health-recover.sh /volume1/docker/mydns-recovery/docker-health-recover.sh
sudo chown root:root /volume1/docker/mydns-recovery/docker-health-recover.sh
sudo chmod 600 /volume1/docker/mydns-recovery/docker-health-recover.sh
```

最初の行でファイルが見つからなければ、配置を直してから進めてください。
mydns-recoveryは、実行用スクリプト・復帰履歴・ログを保存する別フォルダーです。本番のstate.confとは共有しません。

## 2. 呼び出し用ファイルを作る

次のまとまりをそのまま実行します。以後は、このファイルが配置先などを指定するため、毎回入力する必要はありません。

```sh
sudo tee /volume1/docker/mydns-recovery/run.sh >/dev/null <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
export MYDNS_DOCKER_BIN=/usr/local/bin/docker
export MYDNS_RECOVERY_CONTAINER=mydns-updater
export MYDNS_RECOVERY_DIR=/volume1/docker/mydns-recovery/state
exec /bin/sh /volume1/docker/mydns-recovery/docker-health-recover.sh "$@"
EOF
sudo chown root:root /volume1/docker/mydns-recovery/run.sh
sudo chmod 600 /volume1/docker/mydns-recovery/run.sh
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --status
```

`STATUS; container=mydns-updater` と、初回なら `consecutive=0 pending=0 blocked=0 last_attempt=0` が表示されます。
更新時に履歴が残っている場合は数値が異なります。初期化せず引き継いでください。

```sh
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --once
echo $?
```

healthyなら通常は何も表示せず、最後の終了コードは0です。エラーが出た場合は、定期実行を有効にする前に内容を確認します。

## 3. DSMのタスクスケジューラへ登録する

DSMの「コントロールパネル」→「タスクスケジューラ」で、スケジュールされたタスクの「ユーザー定義のスクリプト」を作成します。

- 名前：MyDNS自動復帰
- ユーザー：root
- スケジュール：毎日、1分ごと、終日
- 有効：オン

ユーザー定義のスクリプトには次の1行を記入します。

```sh
/bin/sh /volume1/docker/mydns-recovery/run.sh --once >> /volume1/docker/mydns-recovery/recovery.log 2>&1
```

DSMの版によって項目名は異なる場合があります。「1分ごと」で終日実行する設定を確認してください。
開始時刻を00:00、繰り返しを毎分、最終実行時刻を23:59にします。
最終実行時刻が00:59だと、深夜の1時間しか動きません。保存し、変更が未保存なら「適用」を押します。

一覧の「次回の実行時刻」は予定です。実際に実行された証拠ではないので、次の手順で確認します。


## 4. 定期実行を確認する

ここからはDSMの「実行」ボタンを押さず、スケジュールで動くのを待ちます。
NASのSSHで次を実行します。

```sh
sudo stat -c '監視記録の更新時刻: %y' /volume1/docker/mydns-recovery/state/status
```

登録直後にファイルが見つからない場合は、次の実行予定を過ぎてから再確認します。
表示できたら1〜2分待ち、同じコマンドをもう一度実行します。

**確認：** 更新時刻が進んでいれば、監視記録は更新されています。
さらに次の2つを確認します。状態表示だけでは、定期実行が動いた証拠にはなりません。

```sh
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --status
sudo tail -n 30 /volume1/docker/mydns-recovery/recovery.log
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
```

正常時は `consecutive=0 pending=0 blocked=0` と `running healthy` です。
ログは空でも正常です。エラーが出ている場合は、記録の時刻が進んでいても原因を確認します。

<details>
<summary>困ったときだけ：記録がない・時刻が進まない</summary>

DSMで、有効、ユーザーroot、毎日00:00〜23:59の毎分実行、保存済みであることを確認します。
手順3のコマンドのパスと、手順2で作ったrun.shの場所を見比べます。
ログにエラーがあれば、その内容を先に確認してください。

</details>

## 5. 定期実行による自動復帰を1回試す

ここからは任意の最終確認です。手順4までなら「定期監視が動く」、ここまで行えば「異常時の自動復帰まで動く」を確認できます。
試験中は数分以上、IP確認と通知が止まります。同じ版・設定ですでに確認済みなら繰り返す必要はありません。

### 5-1. 正常な状態を保存する

NAS本体へSSH接続した画面で実行します。

```sh
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}} {{.HostConfig.RestartPolicy.Name}}' mydns-updater
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --status
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
pid=$(/usr/local/bin/docker inspect --format "{{.State.Pid}}" mydns-updater) || exit 1
[ "$pid" -gt 1 ] || exit 1
kill -STOP "$pid" && echo "更新処理を一時停止しました"
'
```

「更新処理を一時停止しました」が出たら、復帰ログの表示を始めます。

```sh
sudo tail -n 0 -f /volume1/docker/mydns-recovery/recovery.log
```

DSMの「実行」ボタンを押さず、定期実行に任せて待ちます。
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
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --status
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
sudo cat /volume1/docker/mydns-recovery/recovery.log > ~/mydns-recovery-results/recovery.log
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
pid=$(/usr/local/bin/docker inspect --format "{{.State.Pid}}" mydns-updater) || exit 1
[ "$pid" -gt 1 ] || exit 1
kill -CONT "$pid" && echo "一時停止の解除を送りました"
'
sudo tail -n 50 /volume1/docker/mydns-recovery/recovery.log
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
```

すでに停止していてCONTを送れない場合は、ログを確認してから導入手順の開始操作を行います。
手動で解除して正常になっても、自動復帰の成功とは区別します。再試験の前に原因を確認してください。
BLOCKEDの場合も、そのまま履歴を消して試験を繰り返しません。

</details>

## 必要な場合だけ：自動復帰を無効にする・制限を解除する

通常運用・正常な試験終了時には、以下の操作は不要です。

<details>
<summary>自動復帰だけを無効にする場合</summary>

DSMのタスクスケジューラでMyDNS自動復帰の有効チェックを外し、保存します。
すでに始まった確認が終わるまで待ちます。更新コンテナ自体は動いたままです。

</details>

<details>
<summary>上限待ちの原因を直し、制限を解除する場合</summary>

まずログのBLOCKEDの原因を確認・修正します。
次にDSMのタスクを一時的に無効にし、実行中の確認が終わるのを待ってから解除します。

```sh
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --reset
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --status
```

RESETと、blocked=0を確認します。ロック中のエラーが出たら少し待って再実行します。
解除は停止中のコンテナを起動しません。コンテナの状態を確認し、DSMのタスクを再び有効にします。

</details>
