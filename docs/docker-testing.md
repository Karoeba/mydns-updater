# Dockerの動作確認手順

[資料一覧](README.md) ／ [Dockerの導入・運用](../README.md) ／ [テストの説明](testing.md)

Ubuntu Server 24.04 LTS上のDocker EngineとComposeを使い、公開手順どおりの導入と動作を確認します。Docker未導入なら [UbuntuへのDocker導入](reference/ubuntu-docker.md) から進めます。

ここでのコマンドはUbuntu側の端末で実行します。Synology Container Managerの操作手順ではありません。Ubuntu VMで成功しても、Container Managerの異常・復旧表示は別の確認として残ります。

## 1. コードを取得する

Linux直接実行版の作業フォルダーと分け、新しいフォルダーを用意します。同名フォルダーがすでにある場合は中身を確認し、上書きしません。

```sh
sudo apt update
sudo apt install git nano
git clone --branch main --single-branch https://github.com/Karoeba/mydns-updater.git mydns-updater-docker
cd mydns-updater-docker
git rev-parse HEAD
```

mainは開発版です。試す対象がPRや公開済みリリースの場合は、その対象のコードを取得してください。Git以外で取得した場合は、展開したフォルダーの `update.sh` がある場所へ移動し、取得元・版を控えます。

以降はこのフォルダーで操作します。SSHへ接続し直した場合、この例では `cd ~/mydns-updater-docker` で戻ります。

## 2. 実アカウントを使わない模擬テスト

```sh
mkdir -p tests/reports
sudo docker compose -f tests/compose.yaml run --build --rm test
```

[テスト手順](testing.md#dockerのコマンドライン) に掲載した6種類の成功表示を確認します。

```sh
cat tests/reports/result.txt
```

`ALL TESTS PASSED` が成功です。失敗した場合は `tests/reports/test.log` を確認します。イメージ構築前などの失敗では、新しいレポートがない場合があります。古い成功記録だけで判断せず、今回の端末表示も確認してください。

さらにLinuxのDockerホスト側で、設定ファイルの上書きと健康状態の遷移を確認します。

```sh
sudo sh tests/test-config-reload.sh
```

次の2行が成功の目印です。

```text
ALL CONFIG RELOAD TESTS PASSED (4 checks)
ALL DOCKER HEALTHCHECK TESTS PASSED (3 checks)
```

これは別の一時コンテナとダミーの通信を使います。実アカウントは不要で、NASの運用は継続できます。試験では待ち時間とヘルスチェックの間隔を短縮し、進行記録の期限も操作します。付属Composeの通常設定での確認は以下で行います。

## 3. 実アカウントを設定する

同じアカウントで動くNASのプロジェクトを停止します。VM内のLinux直接実行版も停止・自動起動無効になっていることを確認します。設定と状態を他環境と共有せず、この作業フォルダーに用意します。

次のコピーは新規導入時だけです。既存の設定には上書きしません。

```sh
mkdir -p config state
cp mydns.conf.example config/mydns.conf
cp accounts.conf.example config/accounts.conf
chmod 600 config/mydns.conf config/accounts.conf
nano config/accounts.conf
```

各アカウントのID・PASSWORD・DOMAINを記入します。2件目はセクション行と3項目をまとめて有効にします。nanoはCtrl+O → Enterで保存、Ctrl+Xで終了します。

```sh
nano config/mydns.conf
```

異常・復旧の待ち時間を短くするため、該当行を次の値に変更します。重複追加はしません。

```ini
CHECK_INTERVAL=60
FORCE_UPDATE_INTERVAL=3600
DEBUG=1
```

## 4. 構築して起動する

同じDocker環境に `mydns-updater` というコンテナがすでにある場合は、新規試験を重ねず既存の用途を確認します。

```sh
sudo docker compose config --quiet
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs --tail 50
```

`config --quiet` はエラーなしで終了すればComposeの構文確認成功です。起動ログのバージョン、各アカウントの `MyDNS update: OK` と状態ファイルの生成を確認します。

```sh
sudo ls -l state/state.conf
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

起動直後は `starting` です。通常は次の確認を待つと `healthy` になります。必要なら30〜60秒後に再度実行します。通知成功は通常ログ、処理の進行はヘルスチェックでそれぞれ判断します。

## 5. 異常と復旧を確認する

試験用VMのコンテナだけで行います。ここでは更新処理だけを一時停止し、Docker側のヘルスチェックは動かしたままにします。`docker pause` や `docker compose stop` に置き換えません。

開始前の記録を保存します。

```sh
mkdir -p ~/mydns-docker-results
sudo docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' mydns-updater > ~/mydns-docker-results/before.txt
```

再開用のCONTコマンドまで確認してから、次を実行します。`--signal=STOP` は省略しません。

```sh
sudo docker kill --signal=STOP mydns-updater
```

次を30秒程度の間隔で再実行し、`unhealthy` になることを確認します。

```sh
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

CHECK_INTERVAL=60なら、待機期限と120秒の余裕、その後の3回連続失敗を含め、数分（目安5分程度）かかります。負荷や停止させた位置で前後します。CHECK_INTERVAL=300ならさらに長くなります。

異常になった時点で記録を保存します。Dockerの健康状態履歴は件数が限られるため、復旧してからまとめて取ると異常時の記録が残らない場合があります。

```sh
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > ~/mydns-docker-results/health-unhealthy.json
```

**結果にかかわらず、必ず次で更新処理を再開します。**

```sh
sudo docker kill --signal=CONT mydns-updater
```

次の処理進行と確認を待ち、同じinspectコマンドで `healthy` に戻ることを確認します。CHECK_INTERVAL=60なら1〜2分程度が目安です。

```sh
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > ~/mydns-docker-results/health-recovered.json
sudo docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' mydns-updater > ~/mydns-docker-results/after.txt
diff ~/mydns-docker-results/before.txt ~/mydns-docker-results/after.txt
```

差分がなければ、コンテナを再起動せず復旧しています。Docker版ではLinuxの監視スクリプトのUNHEALTHY／RECOVEREDログではなく、Dockerの状態と検査履歴を見ます。異常判定だけで自動再起動はしません。

シグナルの送信方法は [Docker公式のkill説明](https://docs.docker.com/reference/cli/docker/container/kill/) に基づきます。

## 6. 設定変更・定期通知・再起動を確認する

`config/mydns.conf` を編集し、CHECK_INTERVALを300へ戻します。DEBUG=1のまま次の周期以降のログが約5分間隔になることを確認します。

```sh
sudo docker compose logs -f --tail 30
```

Ctrl+Cでログ表示を終了してもコンテナは動き続けます。FORCE_UPDATE_INTERVAL=3600では、アカウントごとの前回通知成功から1時間を過ぎた確認周期で通知します。両アカウントを使う場合は両方の成功を確認します。

続いてDEBUG=0に変更し、次の周期以降に詳細ログが増えなくなることを確認します。IP不変・期限前なら通常ログも増えません。

状態引き継ぎの確認時はDEBUG=1へ戻し、反映を待ってから再起動します。

```sh
sudo docker compose restart
sudo docker compose logs --tail 30
```

IP不変・期限前なら、更新理由ではなくSKIPが表示されます。再起動直後も、状態ファイルの前回成功時刻が基準です。

## 7. 記録して終了する

再作成や削除の前に保存します。

```sh
sudo docker compose logs --no-color > ~/mydns-docker-results/updater.log 2>&1
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > ~/mydns-docker-results/health-final.json
sudo docker version > ~/mydns-docker-results/docker-version.txt
sudo docker compose version > ~/mydns-docker-results/compose-version.txt
git rev-parse HEAD > ~/mydns-docker-results/commit.txt
```

Git以外で取得した場合、最後のコマンドの代わりに取得元・版を記録します。ログにはIPと表示用ドメインが含まれます。認証情報を含む設定ファイル自体を試験結果として公開しないでください。

一時停止中なら手順5のCONTで再開したうえで、試験コンテナを停止します。

```sh
sudo docker compose stop
sudo docker compose ps -a
```

`Exited` を確認してから、同じアカウントを使うNAS側のプロジェクトを再開します。設定・状態・テスト結果の削除は不要です。

試験用VMも止める場合は `sudo poweroff` を実行します。継続運用する場合は停止せず、試験用の値を希望する運用設定へ戻します。既定値はCHECK_INTERVAL=300、FORCE_UPDATE_INTERVAL=86400、DEBUG=0です。

## 確認記録

- 取得した版、Docker／Composeのバージョン
- 模擬テスト6種類とホスト側4＋3項目の成功
- 構築・起動、実通知、状態生成
- 通常のCompose設定でhealthy → unhealthy → healthy
- 再起動せずに復旧したこと
- 設定再読み込み、定期通知、再起動後の状態引き継ぎ
- 試験終了後の停止と運用環境への切り戻し

この手順はコードとコマンドの点検を行ったものです。手順全体のUbuntu VMでの実行結果は、別途記録します。
