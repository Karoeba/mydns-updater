# Synologyの自動復帰を設定する

[Synologyの導入・運用](synology.md) ／ [共通の条件とログの意味](docker-recovery.md)

NAS本体のSSHとDSMを使います。以下ではボリュームをvolume1、コンテナ名をmydns-updaterとしています。
配置が異なる場合は実際の場所に合わせます。Ubuntu VMの端末では行いません。

File Stationで試験用ファイルをアップロードし、SSHで監視用ファイルの配置・権限設定と試験を行います。
最後にDSMのタスクスケジューラへ登録します。設定後はSSHを切断しても監視・自動復帰は続きます。

**進む順番：** 通常の通知・正常表示を確認 → 試験専用コンテナで確認 → 1〜3 配置とDSM登録 → 4 定期実行 → 5 自動復帰の試験。
本番の設定・通知確認が済んでいれば、初回導入からやり直しません。
模擬試験と、本番の定期実行・自動復帰は別の確認です。

## 配置の全体像

```text
/volume1/docker/
├── mydns-updater/                   ← 通常運用の一式とconfig・state
├── mydns-recovery-check/            ← 試験用に取得した一式
└── mydns-recovery/                  ← この手順で用意する監視用
    ├── docker-health-recover.sh
    ├── run.sh                      ← 配置先を指定して呼び出す
    ├── recovery.log                ← DSMの定期実行で生成
    └── state/
        └── status                  ← 復帰履歴。自動生成
```

試験用フォルダーと監視用フォルダーは用途が違います。
mydns-updater/stateの通知成功記録を、mydns-recovery/stateへコピーする必要はありません。

## 始める前に

### PCで入手し、File Stationで置く

1. [v1.10.0の試験用ZIP](https://github.com/Karoeba/mydns-updater/archive/refs/heads/v1.10.0-modular-core.zip)をPCへダウンロードし、展開します。
2. 展開したフォルダーを開き、update.shがある階層まで進みます。
3. File Stationで共有フォルダー `docker` の中に `mydns-recovery-check` を作ります。
4. 展開フォルダーの**中身をすべて**、そこへアップロードします。

[Container Managerの模擬テスト](testing.md#synology-container-manager)で同じ版を配置済みなら、このアップロードは不要です。
その試験と今回の自動復帰試験は内容が異なりますが、ファイル一式は共用できます。

```text
PC：ZIPを展開したフォルダー
展開した一式（update.shがある階層）/
    中身をすべてアップロード
                ↓
NAS：File Stationの docker/mydns-recovery-check/
├── update.sh
├── lib/
│   ├── config.sh
│   ├── diagnostics.sh
│   ├── health.sh
│   ├── network.sh
│   ├── runtime.sh
│   └── state.sh
├── docker-health-recover.sh
├── tests/
│   └── test-docker-recovery-integration.sh
└── その他の同梱ファイル
```

図は一部の抜粋です。tests内のほかのファイルも必要なので、一式をアップロードします。
File Stationでmydns-recovery-checkを開き、すぐにupdate.sh・lib・testsが見えれば正しい配置です。
ZIPの展開フォルダー自体を入れて、1段深くしないでください。

| File Stationで見える場所 | SSHで指定する同じ場所 |
| --- | --- |
| docker/mydns-recovery-check | /volume1/docker/mydns-recovery-check |
| docker/mydns-updater | /volume1/docker/mydns-updater |
| docker/mydns-recovery | /volume1/docker/mydns-recovery |

mydns-updaterは通常運用用、mydns-recovery-checkは試験用です。
mydns-recoveryは、この後の手順1で作る監視用フォルダーなので、今はなくても構いません。

### NASへSSH接続して配置と模擬試験を確認する

NASのSSHで次を実行し、作業場所を確認します。

```sh
cd /volume1/docker/mydns-recovery-check
pwd
ls -l update.sh lib/*.sh docker-health-recover.sh tests/test-docker-recovery-integration.sh
```

3ファイルとlib内の6ファイルが表示されたら、[試験専用コンテナでの確認](docker-recovery.md#本番導入前に組み合わせを試す)を行います。
この自動復帰の組み合わせ試験を同じ版・同じNASですでに済ませた場合は繰り返さず、次へ進みます。
Container Managerでの模擬テストだけを終えた場合は、ここで組み合わせ試験も行います。
リンク先で成功表示と終了コード0を確認したら、このページへ戻ります。
試験用コンテナはコマンドが自動で作成・削除するため、Container Managerでプロジェクトを作る操作はありません。

### 通常運用のコンテナを確認する

本番が古い版の場合だけ、[Synologyの更新手順](synology.md#更新する場合)でプログラム一式をv1.10.0にします。
すでにv1.10.0の通常導入を終えている場合は、再作成せず起動ログを確認します。
configとstateは保持します。v1.10.0ではlibの配置とComposeの変更があるため、更新手順に従って再作成します。

```sh
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}} {{.HostConfig.RestartPolicy.Name}}' mydns-updater
```

`running healthy unless-stopped` なら進めます。


## 1. NASにファイルを配置する

ここでは、先ほど試験用フォルダーへ置いた **docker-health-recover.shだけ**を監視用フォルダーへコピーします。
入手し直したり、本番用フォルダーへ一度置いたりする必要はありません。

| コピー元（取得したファイル） | コピー先（自動復帰で使用） |
| --- | --- |
| /volume1/docker/mydns-recovery-check/docker-health-recover.sh | /volume1/docker/mydns-recovery/docker-health-recover.sh |

下のコマンドがコピー先の作成・コピー・権限設定をまとめて行います。
File Stationで監視用フォルダーを先に作る必要はありません。

NASのSSH画面で次を実行します。

```sh
ls -l /volume1/docker/mydns-recovery-check/docker-health-recover.sh
```

**確認：** ファイルが表示されたら次へ進みます。見つからない場合は配置を直します。

```sh
sudo mkdir -p /volume1/docker/mydns-recovery/state
sudo chown root:root /volume1/docker/mydns-recovery /volume1/docker/mydns-recovery/state
sudo chmod 700 /volume1/docker/mydns-recovery /volume1/docker/mydns-recovery/state
sudo cp /volume1/docker/mydns-recovery-check/docker-health-recover.sh /volume1/docker/mydns-recovery/docker-health-recover.sh
sudo chown root:root /volume1/docker/mydns-recovery/docker-health-recover.sh
sudo chmod 600 /volume1/docker/mydns-recovery/docker-health-recover.sh
```

最初の行でファイルが見つからなければ、配置を直してから進めてください。
mydns-recoveryは、実行用スクリプト・復帰履歴・ログを保存する別フォルダーです。本番のstate.confとは共有しません。

## 2. 呼び出し用ファイルを作る

run.shはZIPからコピーするファイルではなく、下のコマンドで新しく作ります。
作成先は `/volume1/docker/mydns-recovery/run.sh` です。

NASのSSHで次のまとまりをそのまま実行します。以後は、このファイルが配置先などを指定するため、毎回入力する必要はありません。

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

- タスク名：`MyDNS Auto Recovery`（英数字とスペースで入力）
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
さらに次の3つを確認します。状態表示だけでは、定期実行が動いた証拠にはなりません。

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

保存先の `~/mydns-recovery-results` はSSHにログインしたユーザーのホーム内です。
同じユーザーでDSMへログインしていれば、通常はFile Stationの `home → mydns-recovery-results` で見つかります。
docker共有フォルダー内ではありません。表示されない場合の確認方法も、次のリンク先に記載しています。

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

試験と記録が終わったら、[Synology導入手順の最後の選択](synology.md#6-詳しい確認または通常運用へ進む)で、継続運用か停止・切り戻しを選びます。
正常に終わった試験の後に、下の履歴リセットを行う必要はありません。

## 必要な場合だけ：自動復帰を無効にする・制限を解除する

通常運用・正常な試験終了時には、以下の操作は不要です。

<details>
<summary>自動復帰だけを無効にする場合</summary>

DSMのタスクスケジューラでMyDNS Auto Recoveryの有効チェックを外し、保存します。
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
