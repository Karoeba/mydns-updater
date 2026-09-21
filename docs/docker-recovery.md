# Docker・Synologyの自動復帰

v1.9.0で追加した任意の機能です。導入・有効化しなければ、これまでどおり異常の表示だけを行います。
LinuxでDockerを使わずに動かす場合は、[Linuxの自動復帰](linux-recovery.md)を参照してください。

## 復帰する条件

| 項目 | 動作 |
| --- | --- |
| 対象 | 処理の進行期限超過が3回連続した場合 |
| 定期確認 | 約1分ごと。30秒以内の連続実行は回数に加えない |
| 再起動の間隔 | 前回の要求から10分以上 |
| 回数上限 | 直近1時間に3回まで。4回目が必要になった時点で手動解除待ち |
| 上限後 | 確認は続けるが、手動解除するまで復帰を要求しない |
| 手動停止・一時停止 | 停止中、Dockerのpause中のコンテナは起動・解除しない |

通信・認証・設定エラーがあっても、処理が進んでいれば再起動しません。
進行記録が読めない、壊れている、確認コマンドが失敗する場合も再起動せず、原因の確認が必要です。

Dockerが表示するunhealthyをさらに3回数えるのではなく、毎回、同じ進行記録を新しく検査します。
3分を超えて監視が途切れた場合は連続回数を数え直します。
期限には更新処理側の待機時間なども含むため、プロセスが止まった瞬間から3分で復帰するとは限りません。

復帰要求の履歴はホスト側に保存します。コンテナ・OSの再起動、正常復帰でも回数は消しません。要求の失敗や結果不明も1回に含めます。
時計が大きく過去に戻った場合も、手動解除待ちになります。

この上限は、この機能が出す復帰要求の上限です。プロセスの異常終了に対するDockerのunless-stoppedによる再起動回数を制限するものではありません。

## 先に更新するもの

1. 対象コンテナを停止します。
2. configとstateは保持し、update.shをv1.9.0へ上書きします。
3. コンテナを開始し、起動ログにv1.9.0が出ることとhealthyを確認します。

ComposeとDockerfileの変更はありません。設定が付属のものと同じなら、再構築・再作成は不要です。
この先の監視スクリプトは、コンテナの外側に配置します。

```sh
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}} {{.HostConfig.RestartPolicy.Name}}' mydns-updater
```

正常時の表示は `running healthy unless-stopped` です。
古いupdate.shでは監視側が処理を拒否します。停止済みコンテナに対してstartやrestartを実行する仕組みではありません。

## Synology Container Managerで有効にする

### 1. NASにファイルを配置する

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

### 2. 呼び出し用ファイルを作る

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

### 3. DSMのタスクスケジューラへ登録する

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
保存後にタスクを一度実行し、1〜2分後にも最終実行時刻が更新されることを確認します。

### 4. 状態とログを確認する

```sh
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --status
sudo tail -n 30 /volume1/docker/mydns-recovery/recovery.log
```

正常時はログが空でも問題ありません。状態表示と、DSMのタスク実行履歴を併せて確認します。
手動でコンテナを停止した後もタスクは動きますが、復帰要求は出しません。

## UbuntuなどのDockerホストで有効にする

systemdを使用するホスト向けです。以下は取得したリポジトリのフォルダーで実行します。

```sh
sudo install -d -m 755 /usr/local/lib/mydns-updater
sudo install -o root -g root -m 644 docker-health-recover.sh /usr/local/lib/mydns-updater/docker-health-recover.sh
sudo install -o root -g root -m 644 deploy/linux/mydns-updater-docker-recovery.service /etc/systemd/system/
sudo install -o root -g root -m 644 deploy/linux/mydns-updater-docker-recovery.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start mydns-updater-docker-recovery.service
sudo systemctl status mydns-updater-docker-recovery.service --no-pager
```

一度だけ確認して終了するサービスなので、正常終了後は `inactive (dead)` と `status=0/SUCCESS` になります。
エラーがなければタイマーを有効にします。

```sh
sudo systemctl enable --now mydns-updater-docker-recovery.timer
sudo systemctl list-timers --all mydns-updater-docker-recovery.timer
sudo journalctl -u mydns-updater-docker-recovery.service -n 30 --no-pager
```

タイマーの行に次回実行時刻が表示されれば、定期実行が始まっています。
履歴は `/var/lib/mydns-updater-docker-recovery` に保存されます。

コンテナ名やDockerコマンドの場所を変える場合だけ、`/etc/mydns-updater-docker-recovery.conf` をroot所有で作成します。
次は設定例です。値は自分の環境に合わせます。

```ini
MYDNS_RECOVERY_CONTAINER=mydns-updater
MYDNS_DOCKER_BIN=/usr/bin/docker
```

これはsystemdサービスが読み込むファイルです。手動でスクリプトを実行するときには自動では読み込まれません。

## ログの見方

| 表示 | 意味 |
| --- | --- |
| RESTART_ATTEMPT | 復帰を試みる。対象と直近1時間の回数を表示 |
| RESTART_REQUESTED | 終了を依頼した。まだ正常復帰の確定ではない |
| RESTART_REQUEST_UNCONFIRMED | 要求結果が不明。終了で通信が切れる場合もあるため、次の確認で判断 |
| RECOVERED | 要求後の確認が正常になった |
| BLOCKED | 回数上限や時計の巻き戻りで、手動解除待ち |

`--status` のblocked=1は手動解除待ち、pending=1は要求後の正常確認待ちです。
consecutiveは現在の連続期限超過回数、last_attemptは最後の要求時刻（UNIX秒、0は未要求）です。

## 実機での動作確認

まず本番とは別の試験コンテナで、[復帰方式の確認](reference/synology-recovery-probe.md)を行えます。
この7項目試験は方式の確認であり、今回追加した回数制限と定期実行の全体試験とは別です。

自動テストでは、実際の監視スクリプトとupdate.shを試験コンテナで組み合わせて、3回の確認から復帰・正常確認・手動停止まで試します。
時計を模擬した別の試験で、10分間隔・1時間3回・手動解除・時計変更・コンテナの入れ替わりも確認します。
NASで今回の定期実行まで含めた確認結果は、方式確認の結果と分けて記録します。

<details>
<summary>上限に達した場合だけ：原因を確認して解除する</summary>

ログを確認し、設定や環境に問題があれば先に直します。正常動作の確認中に毎回解除する必要はありません。

Synology：

```sh
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --reset
sudo /bin/sh /volume1/docker/mydns-recovery/run.sh --status
```

Ubuntu（既定の配置の場合）：

```sh
sudo sh /usr/local/lib/mydns-updater/docker-health-recover.sh --reset
```

RESETが表示され、履歴と上限待ちが解除されます。停止中のコンテナは起動しません。
Linux側で配置先を変更した場合は、解除時も同じMYDNS_RECOVERY_DIRを指定してください。

</details>

<details>
<summary>自動復帰を使わなくする場合だけ</summary>

SynologyはDSMの「MyDNS自動復帰」タスクを無効にします。
Ubuntuは次を実行します。

```sh
sudo systemctl disable --now mydns-updater-docker-recovery.timer
```

すでに開始した確認処理は終了するまで待ってください。履歴は削除せず残して構いません。

</details>

## 制限

- ローカルのDockerソケットを使用します。リモートDocker、rootless Docker、Podmanは対象外です。
- コンテナのPID 1が付属のupdate.shで、再起動ポリシーがunless-stoppedの構成が対象です。
- 1つの履歴フォルダーを複数コンテナやLinux直接実行版と共有しないでください。
- プロセスが終了要求に応答できない種類の停止や、Docker自体の異常は復帰できない場合があります。回数制限で要求の繰り返しを抑えます。
- この監視を有効にしても、通知成功やDNS応答の正常性は保証しません。
- 管理者がDockerのkill操作を行った場合、再起動ポリシーが抑止されることがあります。異常の再現に以前のdocker kill --signal STOPを使わないでください。
