# Synology：監視のみの試験

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。[取得する版の確認](current-version.md) ／ [試験コース](test-start.md)

S1専用です。[基本試験](synology-testing.md)を終え、**NAS本体へSSH接続した端末**で行います。
DSMの自動復帰タスクは登録しません。Ubuntu VMの端末では実行しません。
更新処理の一時停止・解除にはSSHが必要です。状態の変化はContainer Managerでも確認します。

記録先はSSHでは `/volume1/docker/mydns-health-results`、File Stationでは `docker/mydns-health-results` です。
共有フォルダーが別ボリュームなら、このページのvolume1を実際の番号に合わせます。
フォルダーを作成できない場合はFile Stationで同名フォルダーを作り、SSHユーザーの書き込み権限を確認してから続けます。

ここでは更新処理だけを一時停止し、Docker側のヘルスチェックは動かしたままにします。`docker pause` や `docker compose stop` に置き換えません。

## 1. 正常な状態を確かめて保存する

まず、次を実行します。

```sh
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

**`healthy` と表示されたら**、開始前の記録を保存します。一時停止はまだ行いません。

```sh
mkdir -p /volume1/docker/mydns-health-results
sudo docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' mydns-updater > /volume1/docker/mydns-health-results/before.txt
```

保存できたかを確認します。

```sh
ls -l /volume1/docker/mydns-health-results/before.txt
cat /volume1/docker/mydns-health-results/before.txt
```

**確認：** ファイル名と、長いコンテナID・開始時刻・再起動回数の1行が表示されます。空欄やエラーなら先へ進みません。

## 2. 一時停止して異常を確認する

再開用のCONTコマンドまで確認してから、次の枠をまとめて実行します。
Dockerの再起動ポリシーを抑止しないよう、ホスト側から処理を一時停止します。

```sh
sudo /bin/sh -c '
pid=$(docker inspect --format "{{.State.Pid}}" mydns-updater) || exit 1
[ "$pid" -gt 1 ] || exit 1
kill -STOP "$pid" && echo "更新処理を一時停止しました"
'
```

次を30秒程度の間隔で再実行し、`unhealthy` になることを確認します。

```sh
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

CHECK_INTERVAL=60なら、待機期限と120秒の余裕、その後の3回連続失敗を含め、数分（目安5分程度）かかります。負荷や停止させた位置で前後します。CHECK_INTERVAL=300ならさらに長くなります。

異常になった時点で記録を保存します。Dockerの健康状態履歴は件数が限られるため、復旧してからまとめて取ると異常時の記録が残らない場合があります。

```sh
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > /volume1/docker/mydns-health-results/health-unhealthy.json
```

## 3. 再開して正常に戻ったことを確かめる

**結果にかかわらず、必ず次で更新処理を再開します。**

```sh
sudo /bin/sh -c '
pid=$(docker inspect --format "{{.State.Pid}}" mydns-updater) || exit 1
[ "$pid" -gt 1 ] || exit 1
kill -CONT "$pid" && echo "一時停止の解除を送りました"
'
```

次のコマンドを実行します。

```sh
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

まだ `unhealthy` なら30秒ほど待って同じコマンドを再実行します。CHECK_INTERVAL=60なら1〜2分程度、300なら5分以上かかる場合があります。

**画面に `healthy` と表示されたら、初めて次の保存へ進みます。** CONTを送っただけでは、復旧記録を保存しません。

## 4. 復旧後の記録を保存する

```sh
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > /volume1/docker/mydns-health-results/health-recovered.json
sudo docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' mydns-updater > /volume1/docker/mydns-health-results/after.txt
diff /volume1/docker/mydns-health-results/before.txt /volume1/docker/mydns-health-results/after.txt
```

**確認：** 最後の `diff` で何も表示されず入力待ちへ戻れば、前後の記録は同じです。コンテナを再起動せず復旧したことを確認できます。違いが表示されたら、その結果を控えます。

保存内容も確認します。

```sh
cat /volume1/docker/mydns-health-results/health-recovered.json
```

先頭付近に `"Status":"healthy"` と `"FailingStreak":0` があれば復旧記録も正常です。

ここから先では **before.txtとafter.txtを上書きしません。** この2つは一時停止試験の前後を比べるための記録です。Docker版ではLinuxの監視スクリプトのUNHEALTHY／RECOVEREDログではなく、Dockerの状態と検査履歴を見ます。異常判定だけで自動再起動はしません。

自動復帰の試験では再起動回数が増えるのが正常です。この節の「再起動せずに復旧」と混同しないでください。

## 5. 記録を保存して試験を終了する

```sh
sudo docker logs --since 2h mydns-updater > /volume1/docker/mydns-health-results/updater.log 2>&1
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > /volume1/docker/mydns-health-results/health-final.json
sudo docker version > /volume1/docker/mydns-health-results/docker-version.txt
ls -lh /volume1/docker/mydns-health-results
```

**確認：** 上の3ファイルと、before.txt・after.txt・health-unhealthy.json・health-recovered.jsonがあり、空でないことを確認します。
取得したZIPのURLと取得日時も控えます。記録の意味は[Dockerと共通の説明](docker-health-testing.md#保存した記録の見方)を参照してください。
File Stationでdocker/mydns-health-resultsを開き、必要なら右クリックから圧縮してWindowsへダウンロードします。設定ファイルは含めません。

Container Managerで試験に使ったmydns-updaterプロジェクトを停止し、コンテナが停止したことを確認します。
設定・stateは削除せず、同じアカウントの元の運用環境を再開します。これで試験終了です。
