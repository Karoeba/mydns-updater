# イメージ格納方式への移行・更新

対象はv1.11.0です。[取得する版](current-version.md)を確認してから、使用中の環境の節だけを実行します。
Linux直接実行版はこの操作を行わず、[Linuxの更新手順](linux.md#更新方法)を使います。

## 変わるところ

| 項目 | v1.10.1以前 | v1.11.0以降 |
| --- | --- | --- |
| update.sh・lib | ホストのファイルを実行時に読み込む | 構築時にイメージの/appへ格納 |
| config・state | 外部フォルダー | 同じ場所を引き継ぐ |
| プログラム更新 | ファイルを置き換えて起動 | 必ずイメージを再構築・コンテナを再作成 |
| 設定変更 | 次の確認周期で再読み込み | 変更なし。通常は再構築不要 |
| 自動復帰 | ホストのタイマー・DSMタスク | 変更なし。履歴も保持 |

配布用イメージは未公開なので、構築用のupdate.sh・libなどは引き続き手元に置きます。
ただし、その上書きだけでは動作中のコンテナへ反映されません。

## 共通の準備

1. 新しい一式を別フォルダーへ取得し、VERSIONが1.11.0であることを確認します。
2. 自動復帰を使う場合だけ監視を停止し、実行中の確認処理の終了を待ちます。
3. 更新コンテナを停止し、config・state・元のプログラム一式・使用中のYAMLをバックアップします。復帰履歴も保存します。

標準の復帰履歴は通常のDockerでは `/var/lib/mydns-updater-docker-recovery/`、Synologyでは `/volume1/docker/mydns-recovery/state/` です。
これらは更新時に削除しません。独自の場所を使っていれば、その場所を保存します。
復帰回数・制限を消すための初期化は行いません。
バックアップにはアカウント情報が入るので、公開したり試験結果として提出したりしないでください。

## 通常のDocker

### 1. 停止とバックアップ

Dockerホストの端末で行います。自動復帰を使っている場合だけ実行します。

```sh
sudo systemctl stop mydns-updater-docker-recovery.timer mydns-updater-docker-recovery.service
```

運用先が `~/mydns-updater-docker` の例です。

```sh
cd ~/mydns-updater-docker
pwd
sudo docker compose stop
sudo docker compose ps -a
```

**確認：** mydns-updaterが停止していれば続けます。別のコンテナは操作しません。
以下のバックアップ名とイメージ名は初回の移行用です。既存のものがあれば上書きせず別名を使い、切り戻しにもその名前を指定します。

```sh
sudo mkdir -m 700 ../mydns-updater-before-image
```

**確認：** 何も表示されなければ成功です。File existsなどのエラーが出たらコピーへ進みません。

```sh
sudo cp -a Dockerfile .dockerignore compose.yaml update.sh lib config state ../mydns-updater-before-image/
sudo docker image tag "$(sudo docker inspect --format '{{.Image}}' mydns-updater)" mydns-updater:before-image
sudo ls -la ../mydns-updater-before-image
```

**確認：** 構築用ファイル・config・stateが表示されます。before-imageは旧イメージを残す名前です。試験終了まで削除しません。
YAML名がdocker-compose.ymlなどの場合は実際のファイルを保存します。
自動復帰を使う場合は、その設定と上記の復帰履歴も停止中にバックアップします。

### 2. 構築用ファイルを配置する

新しい一式を `~/mydns-updater-source-1.11.0` へ取得した例です。運用先へ必要なものだけコピーします。

```sh
cd ~/mydns-updater-docker
cp ~/mydns-updater-source-1.11.0/Dockerfile ~/mydns-updater-source-1.11.0/.dockerignore ~/mydns-updater-source-1.11.0/update.sh .
mkdir -p lib
cp ~/mydns-updater-source-1.11.0/lib/*.sh lib/
```

標準のcompose.yamlを使う場合だけ、次で置き換えます。独自設定がある場合はコピーせず、次に示す2行の削除を反映します。

```sh
cp ~/mydns-updater-source-1.11.0/compose.yaml .
```

使用中のYAMLで `./update.sh:/app/update.sh:ro` と `./lib:/app/lib:ro` を外し、configとstateの行を残します。
ファイル名が複数ある場合はComposeが実際に使う方を編集します。

```sh
grep '^VERSION=' update.sh
sudo docker compose config --quiet
```

**確認：** VERSIONが1.11.0。構文確認は成功時に何も表示しません。エラーがあれば直してから続けます。

### 3. 再構築・再作成して確認する

```sh
sudo docker compose build
```

**確認：** 構築エラーがなければ続けます。失敗したら停止したまま原因を確認し、古いイメージのまま起動しません。

```sh
sudo docker compose up -d --force-recreate
sudo docker compose logs --tail 50
sudo docker inspect --format '{{range .Mounts}}{{println .Destination}}{{end}}' mydns-updater
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
```

**成功：** 最新STARTUPがv1.11.0、標準構成のマウント先は/config・/stateだけです。/app・/app/update.sh・/app/libがないことを確認します。
健康状態がstartingなら30〜60秒待って最後の確認を再実行し、`running healthy` を確認します。
設定エラーがなく、既存stateを引き継いで期限前なら通知を省略することも確認します。

**自動復帰を最初に止めた場合だけ：** 次で再開します。

```sh
sudo systemctl start mydns-updater-docker-recovery.timer
sudo systemctl list-timers --all mydns-updater-docker-recovery.timer
sudo journalctl -u mydns-updater-docker-recovery.service --since '2 minutes ago' --no-pager
```

次回予定だけでなく、1分程度待って実行記録にエラーがないことも確認します。

## Synology Container Manager

### 1. 停止とバックアップ

1. 自動復帰を使う場合だけ、DSMタスクスケジューラの該当タスクを無効にして適用し、実行中の処理が終わるのを待ちます。
2. Container Managerでmydns-updaterプロジェクトを停止します。
3. File Stationで `docker/mydns-updater` を別のバックアップ用フォルダーへコピーします。config・state・旧プログラム・使用中のYAMLを含めます。
4. 自動復帰を使う場合は `docker/mydns-recovery` も保存します。元のフォルダーとDSMタスクは削除しません。

バックアップ先は管理者だけが開ける場所にします。コピー後、必要なファイルがあることを確認します。
使用中のYAML名はcompose.yamlではなくdocker-compose.ymlの場合もあります。

### 2. 構築用ファイルとYAMLを配置する

PCで展開した新しい一式から、次だけをFile Stationの運用先へ上書きします。

```text
docker/mydns-updater/
├── Dockerfile        ← 新しいものへ
├── .dockerignore     ← 新しいものへ。省略しない
├── update.sh         ← 新しいものへ
├── lib/              ← 中の6ファイルを新しいものへ
├── compose.yaml      ← 使用中のYAMLへ変更を反映
├── config/           ← 保持。exampleで上書きしない
└── state/            ← 保持
```

プロジェクトが使用中のYAMLでもupdate.sh・libのマウントを削除します。
`./config:/config:ro` と `./state:/state` は残し、独自設定も保持します。
アップロードだけで画面側のYAMLが変わったと思わず、実際のプロジェクト設定を確認してください。

### 3. イメージを再構築する

確実に再構築するため、この移行手順ではNASへSSH接続して構築します。Ubuntu VMでは行いません。
before-imageという名前をすでに使っている場合は別名にし、切り戻しでも同じ名前を使います。
volume1以外に配置している場合はパスを読み替えます。

```sh
cd /volume1/docker/mydns-updater
pwd
ls -la Dockerfile .dockerignore update.sh lib/*.sh
grep '^VERSION=' update.sh
sudo docker image tag "$(sudo docker inspect --format '{{.Image}}' mydns-updater)" mydns-updater:before-image
sudo docker build -t mydns-updater:local .
```

**確認：** VERSIONが1.11.0、構築がエラーなく完了していることを確認します。失敗したら次へ進みません。

### 4. プロジェクトを再作成して確認する

1. Container Managerでプロジェクトを「クリーンアップ」し、その後「構築」で再作成・起動します。共有フォルダーやconfig・stateは削除しません。
2. ログの最新STARTUPがv1.11.0、設定エラーがないことを確認します。
3. コンテナの全般でボリュームを確認します。config・stateは残り、/app/update.sh・/app/libへのマウントはありません。
4. 30〜60秒後に「正常」になっていることを確認します。通知期限前なら通知成功ログが増えなくても構いません。
5. 最初に止めた場合だけDSMタスクを有効へ戻して適用し、[定期実行の確認](synology-recovery.md#4-定期実行を確認する)を行います。

## 移行後の確認

開発版の検証では通常動作の確認後、[Docker](docker-systemd-recovery.md)または[Synology](synology-recovery.md)の自動復帰試験へ進みます。
停滞検知からRESTART_ATTEMPT・RECOVEREDまでを確認します。
最新版の起動ログ・健康状態・前後の起動情報・復帰ログを保存します。旧版の実機結果を今回の結果へ読み替えません。

## 問題があった場合だけ：切り戻す

正常に移行できた場合は実行しません。

1. 監視を止め、更新コンテナも停止します。
2. バックアップの旧update.sh・lib・Dockerfile・.dockerignore・使用中のYAMLを元の運用先へ戻します。**config・state・復帰履歴は現在のものを保持**し、古い通知時刻へ戻しません。
3. 旧YAMLのプログラムマウントが復元されたことを確認します。NASではプロジェクトが使用中のYAMLも戻します。
4. NASのSSHまたはDockerホストで `sudo docker image tag mydns-updater:before-image mydns-updater:local` を実行します。
5. 通常のDockerは `sudo docker compose up -d --no-build --force-recreate`、Synologyはプロジェクトをクリーンアップして構築し直します。Synologyで再構築される場合も旧Dockerfile・旧ソースから構築します。
6. 旧版の最新STARTUPとhealthy、通知状態の引き継ぎを確認し、止めた監視を再開します。

状態形式は変えていません。configやstateの破損が原因の場合は、この切り戻しとは別に原因を調べてください。
