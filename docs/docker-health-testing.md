# 通常のDocker：監視のみの試験

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。[取得する版の確認](current-version.md) ／ [試験コース](test-start.md)

D1専用です。[基本試験](docker-testing.md)を終え、Ubuntuの端末で行います。
自動復帰のタイマーは導入しません。Container Managerには[Synology専用の試験](synology-health-testing.md)があります。

```sh
cd ~/mydns-updater-docker
pwd
```

**確認：** mydns-updater-dockerフォルダーです。
更新処理だけを一時停止し、手動再開するまで再起動されないことを確認します。
ここでは更新処理だけを一時停止し、Docker側のヘルスチェックは動かしたままにします。`docker pause` や `docker compose stop` に置き換えません。

## 1. 正常な状態を確かめて保存する

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
sudo docker inspect --format '{{json .State.Health}}' mydns-updater > ~/mydns-docker-results/health-unhealthy.json
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

## 5. 記録して終了する

### 5-1. 最後の健康状態を確認する

```sh
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

`healthy` と表示されたら保存へ進みます。`starting` なら30秒ほど待って再確認します。

### 5-2. 記録を保存する

先に保存先を用意します。

```sh
mkdir -p ~/mydns-docker-results
```

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

一覧にhealth-final.json、updater.log、docker-version.txt、compose-version.txt、commit.txtが並び、サイズが0でないことを確認します。
before.txt、after.txt、health-unhealthy.json、health-recovered.jsonも確認します。
Git以外で取得した場合はcommit.txtの代わりに取得元のメモを残します。最後のJSONは `"Status":"healthy"` が目印です。

### 5-3. 試験側を止めてNASへ戻す

このページの試験は、ここで停止して終了します。

通常は手動再開済みです。途中で中断し一時停止したままの場合だけ、先に上の手動再開のCONTで再開してください。
試験コンテナを停止します。

```sh
sudo docker compose stop
sudo docker compose ps -a
```

`Exited` を確認してから、同じアカウントを使うNAS側のプロジェクトを再開します。設定・状態・テスト結果の削除は不要です。

### 5-4. Windowsへ記録をコピーする

**Windowsへ記録を持ち帰る場合だけ行います。** Ubuntu内に保存するだけなら、このコピー操作は不要です。

VMはコピーが終わるまで起動しておきます。Ubuntu側で `hostname -I` を実行し、VMのIPアドレスを控えます。

**ここからはWindowsのPowerShellです。** UbuntuへSSH接続中なら `exit` で抜けるか、Windowsで別のPowerShellを開きます。`PS C:\Users\...>` のような表示を確認してください。

次のユーザー名とIPアドレスを自分のUbuntuのものに置き換えます。

```powershell
scp -r tester@192.168.1.50:~/mydns-docker-results "$HOME\Downloads"
```

Ubuntuのパスワードを入力します。完了したらWindowsのダウンロードを開き、mydns-docker-resultsフォルダー内に上記のファイルがあることを確認します。取り直した場合は更新日時も確認してください。

**試験を終了してVMも使い終えた場合だけ**、コピー完了後にUbuntu側で `sudo poweroff` を実行します。


## 保存した記録の見方

記録は「どの環境で、何を確認できたか」を後から見直すために保存します。不具合の相談や、テスト結果をまとめるときにも使えます。プログラムを動かすためのファイルではありません。

Windowsへコピーしたら、ファイルを右クリックしてメモ帳などで開きます。拡張子が `.json` や `.log` でも文字として読めます。長い1行になっている場合は、メモ帳の折り返し表示や検索を使ってください。

| ファイル | 記録していること | 見るところ |
| --- | --- | --- |
| updater.log | 起動、IP確認、通知結果など | 日時とアカウント番号を見る。`MyDNS update: OK` は通知成功、`STARTUP` は起動、`SKIP` は更新不要で見送った記録 |
| health-unhealthy.json | 一時停止して異常になった時点の健康状態と最近の検査結果 | `"Status":"unhealthy"` が異常。`progress overdue` は処理が進まないまま期限を過ぎたという意味 |
| health-recovered.json | 再開し、正常へ戻った時点の健康状態 | `"Status":"healthy"` と `"FailingStreak":0` を確認。0は連続失敗がないこと |
| health-final.json | 手動再開を終えた最後の健康状態 | 同じく `healthy` と連続失敗0を確認 |
| before.txt・after.txt | 一時停止試験の前後のコンテナID、開始時刻、再起動回数（左から順） | 2つが同じなら、試験の前後でコンテナの作り直しや再起動はない。上のdiffで比べられる |
| docker-version.txt | Dockerのバージョンと実行環境 | ClientとServerのVersion、OS/Archを見る。結果を相談するときの環境情報 |
| compose-version.txt | Composeのバージョン | `Docker Compose version` の後ろの番号 |
| commit.txt | 試したコードを特定する番号 | 内容を読み解く必要はない。どのコードで試したかを後から照合するために残す |

まずはupdater.logの日時・OKと、健康状態のStatusを見るだけで十分です。healthyは「処理が進んでいるか正常に待っている」という意味で、通知成功はupdater.logで別に確認します。

**ファイル名だけで成功とは判断しません。** health-recovered.jsonという名前でも、中のStatusがunhealthyなら、保存時点ではまだ異常です。healthyへ戻ったことを画面で確認してから保存し直します。before.txtとafter.txtは、このページの一時停止前後に保存した組で比べます。

健康状態の履歴にある時刻の末尾の `Z` はUTCです。日本時間で比べる場合は9時間を足します。updater.logは設定したTZの時刻なので、日本設定ならJSTです。

記録は保存した時点の写しです。今の状態を自動表示するものではありません。また、健康状態のファイルに残る検査履歴は最近の一部だけです。

テスト結果を確認し終えるまではまとめて残しておきます。不要になったらこの記録フォルダーを削除しても動作には影響しません。ただし、運用中のconfigやstateとは別物なので、取り違えないでください。共有する場合はIPやドメイン名を確認し、通常は結果の要約だけで十分です。
