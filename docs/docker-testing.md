# Dockerの動作確認手順

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。始める前に[取得する版と更新時の確認](current-version.md)を確認してください。

[資料一覧](README.md) ／ [Dockerの導入・運用](docker.md) ／ [テストの説明](testing.md)

Ubuntu上のDocker EngineとComposeで、実アカウントによる詳しい動作確認を行います。
**先に[Docker導入手順の1〜4](docker.md)を終え、通知成功とhealthyを確認してください。**
このページでは取得・初回設定のコピーを繰り返しません。

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

## 1. 導入済みの場所と版を確認する

Ubuntu側で、導入に使った作業フォルダーへ戻ります。

```sh
cd ~/mydns-updater-docker
pwd
ls -l compose.yaml update.sh lib/*.sh
grep '^VERSION=' update.sh
```

**確認：** 場所がmydns-updater-dockerで、update.sh・compose.yaml・lib内の6ファイルが表示され、版が1.11.0なら続けます。
取得先を変えた場合はcdのパスを合わせます。
見つからない場合は、別の場所へ設定を作らず、導入時の場所を確認してください。

## 2. 模擬テストを済ませたことを確認する

[導入手順の模擬テスト](testing.md#dockerのコマンドライン)を同じ版で済ませた場合は、実行し直さず手順3へ進みます。
まだなら実行し、終了コード0とALL TESTS PASSEDを確認してここへ戻ります。
模擬テストと、この後の実アカウントによる確認は別です。

## 3. 実アカウントのまま試験用の間隔に変更する

NASやLinux直接実行版など、同じ実アカウントを使う別環境は停止したままにします。
導入済みのaccounts.confはそのまま使い、記入例で上書きしません。

```sh
nano config/mydns.conf
```

共通設定の該当行を変更します。重複追加はしません。

```ini
CHECK_INTERVAL=60
FORCE_UPDATE_INTERVAL=3600
DEBUG=1
```

Ctrl+O、Enterで保存し、Ctrl+Xで終了します。

```sh
grep -E '^(CHECK_INTERVAL|FORCE_UPDATE_INTERVAL|DEBUG)=' config/mydns.conf
```

**確認：** 上の3項目が同じ値で、それぞれ1行ずつ表示されます。
設定は次の確認周期で反映されます。変更前が300秒なら、その待ち時間が残ることがあります。

## 4. 通常動作を確認する

```sh
sudo docker compose logs --tail 50
sudo ls -l state/state.conf
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
```

**成功：** running healthy、state.confの存在、約1分ごとのCHECKログを確認します。
各アカウントの通知成功はMyDNS update: OKで判断します。既存stateがある場合、通知期限前のSKIPは正常です。

**次は選択です。**
自動復帰をまだ使っておらず、手動での異常・復旧表示も試すなら手順5へ進みます。
自動復帰の検証を行う場合は手順5を飛ばし、手順6で通常動作を確認してから、自動復帰の手順へ進みます。

## 5. 異常と復旧を確認する

**この節は自動復帰を使わず、手動で再開する試験です。** すでに自動復帰を有効にしている場合は、この節を飛ばして手順6へ進みます。自動復帰は手順6の通常動作確認後に、[Docker自動復帰の手順](docker-systemd-recovery.md)で確認します。本ページのbefore.txt・after.txtや手順7の保存一覧は、手動復旧試験を行った場合のものです。

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

通常動作の確認が済んだら、自動復帰も試す場合は[Docker自動復帰](docker-systemd-recovery.md)を手順1から進めます。
同じ版で導入済みの設定は作り直さず確認し、手順5の試験と記録まで終えて、このページの手順7へ戻ります。
**その資料の「VMでの試験を終了する場合」はまだ行いません。** 最後の停止・切り戻しはここでまとめて行います。
自動復帰を使わない場合は、そのまま手順7へ進みます。

## 7. 記録して終了する

### 7-1. 最後の健康状態を確認する

```sh
sudo docker inspect --format '{{.State.Health.Status}}' mydns-updater
```

`healthy` と表示されたら保存へ進みます。`starting` なら30秒ほど待って再確認します。

### 7-2. 記録を保存する

先に保存先を用意します。手順5を飛ばした場合でも必要です。

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
手順5を実施した場合だけ、before.txt、after.txt、health-unhealthy.json、health-recovered.jsonも確認します。
自動復帰を試した場合は、その資料で保存したmydns-recovery-results内の記録を別に保持します。Git以外で取得した場合はcommit.txtの代わりに取得元のメモを残します。最後のJSONは `"Status":"healthy"` が目印です。

### 7-3. 試験側を止めてNASへ戻す

**試験を終えてNASへ戻す場合だけ行います。** VMのDockerで継続運用する場合は、この節の停止を飛ばして7-4へ進みます。NAS側は停止したままにし、試験用の設定を運用時の値へ戻してください。

通常は手順5で再開済みです。途中で中断し一時停止したままの場合だけ、先に手順5-3のCONTで再開してください。
自動復帰を使った場合だけ、先にタイマーと実行中の確認を停止します。

```sh
sudo systemctl disable --now mydns-updater-docker-recovery.timer
sudo systemctl stop mydns-updater-docker-recovery.service
```

使っていなければ上の操作は飛ばします。その後、試験コンテナを停止します。

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
- 模擬テスト7種類とホスト側4＋3項目の成功
- 構築・起動、実通知、状態生成
- 手順5を選んだ場合：healthy → unhealthy → healthy、再起動せず手動再開できたこと
- 自動復帰を選んだ場合：別資料での定期実行・RESTART_ATTEMPTからRECOVERED、手動停止の維持
- 設定再読み込み、定期通知、再起動後の状態引き継ぎ
- 試験終了後の停止と運用環境への切り戻し

これまでの実機確認と、未確認の範囲は[テストの確認状況](testing.md#作者による確認状況)を参照してください。
