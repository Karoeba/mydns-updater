# Dockerの動作確認手順

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。始める前に[取得する版の確認](current-version.md)を確認してください。

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

## 2. 試験用の間隔に変更する

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

## 3. 通常動作を確認する

```sh
sudo docker compose logs --tail 50
sudo ls -l state/state.conf
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
```

**成功：** running healthy、state.confの存在、約1分ごとのCHECKログを確認します。
各アカウントの通知成功はMyDNS update: OKで判断します。既存stateがある場合、通知期限前のSKIPは正常です。

## 4. 設定変更・定期通知・再起動を確認する

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

## 基本試験の完了

ここでは停止せず、[試験コース](test-start.md)で最初に選んだ次のページへ進みます。

| コース | 次のページ |
| --- | --- |
| D1 監視のみ | [異常表示と手動再開の試験](docker-health-testing.md) |
| D2 自動復帰 | [自動復帰の模擬試験](docker-recovery-mock.md)（終了後、導入・実動作の試験へ） |

このページへ戻る操作はありません。
