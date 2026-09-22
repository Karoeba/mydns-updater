# Dockerの動作確認手順

[資料一覧](README.md) ／ [Dockerの導入・運用](docker.md) ／ [テストの説明](testing.md)

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
- 「困ったときだけ」「必要な場合だけ」は、該当する場合のみ実行します。正常時は飛ばします。
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

<details>
<summary>再開するとき・場所が分からなくなったときだけ</summary>

初回の取得と場所の確認が済んだ場合は、この欄を飛ばして手順2へ進みます。
別のPCから接続したときや、続きを始めるときは最初に次を実行します。

```sh
cd ~/mydns-updater-docker
pwd
ls compose.yaml
```

`compose.yaml` が表示されたら再開できます。`No such file or directory` が出たら、そのまま次へ進みません。新しいフォルダーを作って埋め合わせず、ダウンロードした場所と名前を確認します。`no configuration file provided: not found` も、まずこの操作で場所を確認してください。

確認できたら、中断していた手順へ戻ります。

</details>

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

**設定ファイルがない新規導入時だけ、次のコピーを行います。** 既存設定を使う場合はこの枠を飛ばし、下の「確認」から進みます。

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

**この節は自動復帰を使わず、手動で再開する試験です。** 自動復帰を有効にしている場合は、この節の代わりに[Docker自動復帰の動作確認](docker-systemd-recovery.md#5-定期実行による自動復帰を1回試す)を行います。本ページのbefore.txt・after.txtや手順7の保存一覧は、手動復旧試験を行った場合のものです。

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
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > ~/mydns-docker-results/health-unhealthy.json
```

### 5-3. 再開して正常に戻ったことを確かめる

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

自動復帰の試験では再起動回数が増えるのが正常です。この節の「再起動せずに復旧」と混同しないでください。

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

**Gitで取得した場合は下の5行を実行します。ZIPで取得した場合は最初の4行だけを実行し、最後のgitコマンドは飛ばします。**

テスト結果を後から見直すため、再作成や削除の前に保存します。各ファイルの意味は [保存した記録の見方](#保存した記録の見方) を参照してください。

```sh
sudo docker compose logs --no-color > ~/mydns-docker-results/updater.log 2>&1
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > ~/mydns-docker-results/health-final.json
sudo docker version > ~/mydns-docker-results/docker-version.txt
sudo docker compose version > ~/mydns-docker-results/compose-version.txt
git rev-parse HEAD > ~/mydns-docker-results/commit.txt
```

Git以外で取得した場合は、上の枠の最後の `git rev-parse` を実行せず、取得元・版をメモとして残します。ログにはIPと表示用ドメインが含まれます。認証情報を含む設定ファイル自体を試験結果として公開しないでください。

**確認：** 正しい場所に記録があるかを確認します。

```sh
ls -lh ~/mydns-docker-results
cat ~/mydns-docker-results/health-final.json
```

一覧にbefore.txt、after.txt、health-unhealthy.json、health-recovered.json、health-final.json、updater.log、docker-version.txt、compose-version.txt、commit.txtが並び、サイズが0でないことを確認します。Git以外で取得した場合はcommit.txtの代わりに取得元のメモを残します。最後のJSONは `"Status":"healthy"` が目印です。

### 7-3. 試験側を止めてNASへ戻す

**試験を終えてNASへ戻す場合だけ行います。** VMのDockerで継続運用する場合は、この節の停止を飛ばして7-4へ進みます。NAS側は停止したままにし、試験用の設定を運用時の値へ戻してください。

通常は手順5で再開済みです。途中で中断し一時停止したままの場合だけ、先に手順5-3のCONTで再開してください。
その後、試験コンテナを停止します。

```sh
sudo docker compose stop
sudo docker compose ps -a
```

`Exited` を確認してから、同じアカウントを使うNAS側のプロジェクトを再開します。設定・状態・テスト結果の削除は不要です。

### 7-4. Windowsへ記録をコピーする

**Windowsへ記録を持ち帰る場合だけ行います。** Ubuntu内に保存するだけなら、このコピー操作は不要です。

VMはコピーが終わるまで起動しておきます。Ubuntu側で `hostname -I` を実行し、VMのIPアドレスを控えます。

**ここからはWindowsのPowerShellです。** UbuntuへSSH接続中なら `exit` で抜けるか、Windowsで別のPowerShellを開きます。`PS C:\Users\...>` のような表示を確認してください。

次のユーザー名とIPアドレスを自分のUbuntuのものに置き換えます。

```powershell
scp -r tester@192.168.1.50:~/mydns-docker-results "$HOME\Downloads"
```

Ubuntuのパスワードを入力します。完了したらWindowsのダウンロードを開き、mydns-docker-resultsフォルダー内に上記のファイルがあることを確認します。取り直した場合は更新日時も確認してください。

**試験を終了してVMも使い終えた場合だけ**、コピー完了後にUbuntu側で `sudo poweroff` を実行します。継続運用する場合は電源を切らず、試験用の設定値を戻します。既定値はCHECK_INTERVAL=300、FORCE_UPDATE_INTERVAL=86400、DEBUG=0です。


## 保存した記録の見方

記録は「どの環境で、何を確認できたか」を後から見直すために保存します。不具合の相談や、テスト結果をまとめるときにも使えます。プログラムを動かすためのファイルではありません。

Windowsへコピーしたら、ファイルを右クリックしてメモ帳などで開きます。拡張子が `.json` や `.log` でも文字として読めます。長い1行になっている場合は、メモ帳の折り返し表示や検索を使ってください。

| ファイル | 記録していること | 見るところ |
| --- | --- | --- |
| updater.log | 起動、IP確認、通知結果など | 日時とアカウント番号を見る。`MyDNS update: OK` は通知成功、`STARTUP` は起動、`SKIP` は更新不要で見送った記録 |
| health-unhealthy.json | 一時停止して異常になった時点の健康状態と最近の検査結果 | `"Status":"unhealthy"` が異常。`progress overdue` は処理が進まないまま期限を過ぎたという意味 |
| health-recovered.json | 再開し、正常へ戻った時点の健康状態 | `"Status":"healthy"` と `"FailingStreak":0` を確認。0は連続失敗がないこと |
| health-final.json | 再起動確認を終えた最後の健康状態 | 同じく `healthy` と連続失敗0を確認 |
| before.txt・after.txt | 一時停止試験の前後のコンテナID、開始時刻、再起動回数（左から順） | 2つが同じなら、試験の前後でコンテナの作り直しや再起動はない。手順5のdiffで比べられる |
| docker-version.txt | Dockerのバージョンと実行環境 | ClientとServerのVersion、OS/Archを見る。結果を相談するときの環境情報 |
| compose-version.txt | Composeのバージョン | `Docker Compose version` の後ろの番号 |
| commit.txt | 試したコードを特定する番号 | 内容を読み解く必要はない。どのコードで試したかを後から照合するために残す |

まずはupdater.logの日時・OKと、健康状態のStatusを見るだけで十分です。healthyは「処理が進んでいるか正常に待っている」という意味で、通知成功はupdater.logで別に確認します。

**ファイル名だけで成功とは判断しません。** health-recovered.jsonという名前でも、中のStatusがunhealthyなら、保存時点ではまだ異常です。healthyへ戻ったことを画面で確認してから保存し直します。before.txtとafter.txtは、手順6の手動再起動の前に保存した組で比べます。

健康状態の履歴にある時刻の末尾の `Z` はUTCです。日本時間で比べる場合は9時間を足します。updater.logは設定したTZの時刻なので、日本設定ならJSTです。

記録は保存した時点の写しです。今の状態を自動表示するものではありません。また、健康状態のファイルに残る検査履歴は最近の一部だけです。

テスト結果を確認し終えるまではまとめて残しておきます。不要になったらこの記録フォルダーを削除しても動作には影響しません。ただし、運用中のconfigやstateとは別物なので、取り違えないでください。共有する場合はIPやドメイン名を確認し、通常は結果の要約だけで十分です。

## 確認記録

- 取得した版、Docker／Composeのバージョン
- 模擬テスト6種類とホスト側4＋3項目の成功
- 構築・起動、実通知、状態生成
- 通常のCompose設定でhealthy → unhealthy → healthy
- 再起動せずに復旧したこと
- 設定再読み込み、定期通知、再起動後の状態引き継ぎ
- 試験終了後の停止と運用環境への切り戻し

これまでの実機確認と、未確認の範囲は[テストの確認状況](testing.md#作者による確認状況)を参照してください。
