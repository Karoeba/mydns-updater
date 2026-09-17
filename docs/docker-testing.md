# Dockerの動作確認手順

[資料一覧](README.md) ／ [Dockerの導入・運用](../README.md) ／ [テストの説明](testing.md)

Ubuntu Server 24.04 LTS上のDocker EngineとComposeを使い、公開手順どおりの導入と動作を確認します。Docker未導入なら [UbuntuへのDocker導入](reference/ubuntu-docker.md) から進めます。

ここでのコマンドはUbuntu側の端末で実行します。Synology Container Managerの操作手順ではありません。Ubuntu VMで成功しても、Container Managerの異常・復旧表示は別の確認として残ります。

## 画面の見方

この資料は、Ubuntuへ接続した端末で上から順に進めます。次のような表示ならUbuntu側です。名前は自分の環境によって違います。

```text
tester@mydns-linux-test:~$
```

`PS C:\Users\...` ならWindows側です。Windowsで行う操作は、最後のファイルのコピーだけです。

- コマンドは枠の中をコピーします。画面に出ているユーザー名や入力待ちの記号は足しません。
- 1つの枠を実行したら、その下の「確認」を読んでから次へ進みます。
- 何も表示されず入力待ちに戻る操作もあります。保存したファイルは確認コマンドで確かめます。
- `~` は自分のホームフォルダーです。前に `\` を付けません。
- エラーや違う結果が出たら、次の操作へ進まず、その手順番号と表示を控えます。

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

**確認：** 取得後、次を実行します。

```sh
pwd
ls -l compose.yaml update.sh mydns.conf.example accounts.conf.example
```

`pwd` は現在いるフォルダーを表示します。ユーザー名がtesterなら `/home/tester/mydns-updater-docker` です。その下に指定した4ファイルが表示されれば、正しい場所です。

**別のPCから接続したときや、続きを始めるときも、最初に次を実行してください。**

```sh
cd ~/mydns-updater-docker
pwd
ls compose.yaml
```

`compose.yaml` が表示されたら再開できます。`No such file or directory` が出たら、そのまま次へ進みません。新しいフォルダーを作って埋め合わせず、ダウンロードした場所と名前を確認します。`no configuration file provided: not found` も、まずこの操作で場所を確認してください。

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

模擬テストはここで終了です。次から実アカウントを使います。

## 3. 実アカウントを設定する

同じアカウントで動くNASのプロジェクトを停止します。VM内のLinux直接実行版も停止・自動起動無効になっていることを確認します。設定と状態を他環境と共有せず、この作業フォルダーに用意します。

次のコピーは新規導入時だけです。既存の設定には上書きしません。

```sh
mkdir -p config state
cp mydns.conf.example config/mydns.conf
cp accounts.conf.example config/accounts.conf
chmod 600 config/mydns.conf config/accounts.conf
```

**確認：** 編集前に、作ったファイルの場所を確かめます。

```sh
pwd
ls -ld config state
ls -l config/mydns.conf config/accounts.conf
```

作業場所が `/home/自分のユーザー名/mydns-updater-docker` で、2つのフォルダーと2つの設定ファイルが表示されれば進めます。内容やパスワードを画面へ出す必要はありません。

```sh
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

保存後、共通設定の3項目だけを確認します。

```sh
grep -E '^(CHECK_INTERVAL|FORCE_UPDATE_INTERVAL|DEBUG)=' config/mydns.conf
```

**確認：** 上の設定と同じ3行が、それぞれ1回ずつ表示されれば進めます。別の数字、行の不足・重複があれば、同じファイルを開いて直します。

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

**次へ進む条件：** 両アカウントを設定した場合は両方の通知成功と、`healthy` を確認します。まだ `starting` なら待って同じ状態確認コマンドをもう一度実行します。

## 5. 異常と復旧を確認する

試験用VMのコンテナだけで行います。ここでは更新処理だけを一時停止し、Docker側のヘルスチェックは動かしたままにします。`docker pause` や `docker compose stop` に置き換えません。

### 5-1. 正常な状態を確かめて保存する

まず、次を実行します。

```sh
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

**`healthy` と表示されたら**、開始前の記録を保存します。一時停止はまだ行いません。

```sh
mkdir -p ~/mydns-docker-results
sudo docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' mydns-updater > ~/mydns-docker-results/before.txt
```

保存できたかを確認します。

```sh
ls -l ~/mydns-docker-results/before.txt
cat ~/mydns-docker-results/before.txt
```

**確認：** ファイル名と、長いコンテナID・開始時刻・再起動回数の1行が表示されます。空欄やエラーなら先へ進みません。

### 5-2. 一時停止して異常を確認する

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

### 5-3. 再開して正常に戻ったことを確かめる

**結果にかかわらず、必ず次で更新処理を再開します。**

```sh
sudo docker kill --signal=CONT mydns-updater
```

次のコマンドを実行します。

```sh
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

まだ `unhealthy` なら30秒ほど待って同じコマンドを再実行します。CHECK_INTERVAL=60なら1〜2分程度が目安です。

**画面に `healthy` と表示されたら、初めて次の保存へ進みます。** CONTを送っただけでは、復旧記録を保存しません。

### 5-4. 復旧後の記録を保存する

```sh
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > ~/mydns-docker-results/health-recovered.json
sudo docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.RestartCount}}' mydns-updater > ~/mydns-docker-results/after.txt
diff ~/mydns-docker-results/before.txt ~/mydns-docker-results/after.txt
```

**確認：** 最後の `diff` で何も表示されず入力待ちへ戻れば、前後の記録は同じです。コンテナを再起動せず復旧したことを確認できます。違いが表示されたら、その結果を控えます。

保存内容も確認します。

```sh
cat ~/mydns-docker-results/health-recovered.json
```

先頭付近に `"Status":"healthy"` と `"FailingStreak":0` があれば復旧記録も正常です。

ここから先では **before.txtとafter.txtを上書きしません。** この2つは一時停止試験の前後を比べるための記録です。Docker版ではLinuxの監視スクリプトのUNHEALTHY／RECOVEREDログではなく、Dockerの状態と検査履歴を見ます。異常判定だけで自動再起動はしません。

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
sudo docker compose logs --since 2m
```

**確認：** 今の時刻に近い `[STARTUP]` と、その後の両アカウントの `[SKIP]` を見ます。再起動前のSKIPと混同しないよう、行の時刻を確かめてください。まだ `[CHECK] IPv4 check started` までしかない場合は数秒待ち、同じログ表示コマンドをもう一度実行します。2分以上経って何も表示されない場合は `sudo docker compose logs --tail 30` で最近の記録を見ます。

IP不変・期限前なら、更新理由ではなくSKIPが表示されます。再起動直後も、状態ファイルの前回成功時刻が基準です。

## 7. 記録して終了する

### 7-1. 最後の健康状態を確認する

```sh
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

`healthy` と表示されたら保存へ進みます。`starting` なら30秒ほど待って再確認します。

### 7-2. 記録を保存する

再作成や削除の前に保存します。

```sh
sudo docker compose logs --no-color > ~/mydns-docker-results/updater.log 2>&1
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > ~/mydns-docker-results/health-final.json
sudo docker version > ~/mydns-docker-results/docker-version.txt
sudo docker compose version > ~/mydns-docker-results/compose-version.txt
git rev-parse HEAD > ~/mydns-docker-results/commit.txt
```

Git以外で取得した場合、最後のコマンドの代わりに取得元・版を記録します。ログにはIPと表示用ドメインが含まれます。認証情報を含む設定ファイル自体を試験結果として公開しないでください。

**確認：** 正しい場所に記録があるかを確認します。

```sh
ls -lh ~/mydns-docker-results
cat ~/mydns-docker-results/health-final.json
```

一覧にbefore.txt、after.txt、health-unhealthy.json、health-recovered.json、health-final.json、updater.log、docker-version.txt、compose-version.txt、commit.txtが並び、サイズが0でないことを確認します。Git以外で取得した場合はcommit.txtの代わりに取得元のメモを残します。最後のJSONは `"Status":"healthy"` が目印です。

### 7-3. 試験側を止めてNASへ戻す

一時停止中なら手順5のCONTで再開したうえで、試験コンテナを停止します。

```sh
sudo docker compose stop
sudo docker compose ps -a
```

`Exited` を確認してから、同じアカウントを使うNAS側のプロジェクトを再開します。設定・状態・テスト結果の削除は不要です。

### 7-4. Windowsへ記録をコピーする

VMはコピーが終わるまで起動しておきます。Ubuntu側で `hostname -I` を実行し、VMのIPアドレスを控えます。

**ここからはWindowsのPowerShellです。** UbuntuへSSH接続中なら `exit` で抜けるか、Windowsで別のPowerShellを開きます。`PS C:\Users\...>` のような表示を確認してください。

次のユーザー名とIPアドレスを自分のUbuntuのものに置き換えます。

```powershell
scp -r tester@192.168.1.50:~/mydns-docker-results "$HOME\Downloads"
```

Ubuntuのパスワードを入力します。完了したらWindowsのダウンロードを開き、mydns-docker-resultsフォルダー内に上記のファイルがあることを確認します。取り直した場合は更新日時も確認してください。

試験用VMも止める場合はUbuntu側で `sudo poweroff` を実行します。継続運用する場合は停止せず、試験用の設定値を戻します。既定値はCHECK_INTERVAL=300、FORCE_UPDATE_INTERVAL=86400、DEBUG=0です。

## 確認記録

- 取得した版、Docker／Composeのバージョン
- 模擬テスト6種類とホスト側4＋3項目の成功
- 構築・起動、実通知、状態生成
- 通常のCompose設定でhealthy → unhealthy → healthy
- 再起動せずに復旧したこと
- 設定再読み込み、定期通知、再起動後の状態引き継ぎ
- 試験終了後の停止と運用環境への切り戻し

この手順はコードとコマンドの点検を行ったものです。手順全体のUbuntu VMでの実行結果は、別途記録します。
