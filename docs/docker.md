# 通常のDocker・Composeで使う

<!-- current-version: 1.10.1 -->
対象版は **v1.10.1** です。始める前に[取得する版と更新時の確認](current-version.md)を確認してください。

[環境を選ぶ](../README.md#起動方法) ／ [資料一覧](README.md)

UbuntuなどのDocker EngineとComposeで使う手順です。NAS上のUbuntu VMもこちらです。
NAS本体のContainer Managerで使う場合は[Synologyの手順](synology.md)を選びます。

以下のコマンドはDockerを動かすLinux側の端末で実行します。
Docker未導入なら、先に[UbuntuへのDocker導入](reference/ubuntu-docker.md)を行います。

## 目的に合わせて進む

| 目的 | 進む順番 |
| --- | --- |
| 開発版を検証する | 1 準備 → 2 模擬テスト → 3 実アカウント設定 → 4 起動確認 → 詳しい動作確認 |
| 通常導入する | 1 → 3 → 4。模擬テストは任意。起動確認後、必要なら自動復帰を追加 |
| 導入済みの版を更新する | [更新する場合](#更新する場合)へ |

模擬テストは実アカウント不要です。実通知の確認は設定後に行います。
初回導入を済ませた後に、詳しい動作確認のため設定ファイルを作り直す必要はありません。

## ファイルの配置

Linux側の作業フォルダーを、そのままDockerの運用にも使います。
Linux直接実行版のように/etcなどへコピーする手順ではありません。

```text
~/mydns-updater-docker/
├── Dockerfile
├── compose.yaml
├── update.sh
├── lib/                       ← 6つの.shファイル
├── mydns.conf.example
├── accounts.conf.example
├── config/                    ← 手順3で設定を用意
│   ├── mydns.conf
│   └── accounts.conf
├── state/
│   └── state.conf             ← 通知成功後に自動生成
└── tests/
    ├── compose.yaml           ← 模擬テスト専用
    └── reports/               ← テスト結果
```

| Linux側の場所 | コンテナ内で見える場所 | 用途 |
| --- | --- | --- |
| update.sh | /app/update.sh | 起動用プログラム。読み取り専用 |
| lib/ | /app/lib/ | 機能ごとの処理。読み取り専用 |
| config/ | /config/ | 実際の設定。読み取り専用 |
| state/ | /state/ | 成功記録。書き込み可能 |

表はDockerが対応付ける場所を示しています。コンテナ内へ手作業でコピーする必要はありません。
通常運用は直下のcompose.yaml、模擬テストはtests内のcompose.yamlを使います。

## 1. 作業フォルダーを用意する

mainのプログラム一式を、新しい作業フォルダーへ取得します。
同名フォルダーがすでにある場合は取得を繰り返さず、中身を確認します。

```sh
git clone --branch main --single-branch https://github.com/Karoeba/mydns-updater.git mydns-updater-docker
cd mydns-updater-docker
pwd
ls -l compose.yaml update.sh lib/*.sh mydns.conf.example accounts.conf.example
grep '^VERSION=' update.sh
```

**確認：** 現在の場所がmydns-updater-dockerで、指定した4ファイルとlib内の6ファイルが表示されます。
バージョンは `1.10.1` です。
ZIPで取得済みなら、その中身を置いたフォルダーへ移動して同じ一式を確認します。

<details>
<summary>再開するとき・compose.yamlが見つからないときだけ</summary>

別の端末から接続すると、前回の作業場所には戻りません。ホーム内へ取得した場合は次を実行します。

```sh
cd ~/mydns-updater-docker
pwd
ls compose.yaml
```

`no configuration file provided: not found` は、まず現在の場所を確認します。
違う場所に新しい設定を作らず、取得済みのcompose.yamlがあるフォルダーへ移動してください。

</details>

## 2. 実アカウントを使わない模擬テスト

**開発版の検証では実施します。通常導入だけなら手順3へ進めます。**
[Dockerの模擬テスト](testing.md#dockerのコマンドライン)を実行します。
そのページの「終了コード0」と「ALL TESTS PASSED」を確認できたら、このページの手順3へ戻ります。
実アカウントや本番のconfig・stateは使いません。NAS側の運用も止める必要はありません。

## 3. 実アカウントの設定を用意する

**新規導入で設定がない場合だけ**、次を実行します。設定済みならコピーを飛ばして、ファイルの確認へ進みます。

```sh
mkdir -p config state
cp mydns.conf.example config/mydns.conf
cp accounts.conf.example config/accounts.conf
chmod 600 config/mydns.conf config/accounts.conf
```

配置を確認します。

```sh
ls -ld config state
ls -l config/mydns.conf config/accounts.conf
```

2つのフォルダーと2つの設定ファイルが表示されたら編集します。

```sh
nano config/accounts.conf
nano config/mydns.conf
```

accounts.confにID・PASSWORD・DOMAINを記入します。共通設定は必要に応じて調整します。
nanoはCtrl＋O、Enterで保存し、Ctrl＋Xで終了します。
[設定一覧](../README.md#設定一覧)は全環境共通です。

## 4. 構築して開始する

付属のcompose.yamlには定期ヘルスチェックが含まれています。
この手順で構築すれば自動的に有効になり、別の監視タイマーを追加する必要はありません。
ただし、異常時の自動復帰は別途設定する機能です。

### 4-1. 起動と通知を確認する

同じ実アカウントのNASやLinux直接実行版が動いている場合は、先にそちらを停止します。
同じDocker環境にmydns-updaterコンテナがある場合は、新規導入を重ねず用途を確認します。

```sh
sudo docker compose config --quiet
config_result=$?
printf 'Compose確認の終了コード: %s\n' "$config_result"
```

構文確認自体は成功時に何も表示しません。最後の終了コードが0なら成功です。エラーがあれば直してから続けます。

```sh
sudo docker compose up -d --build
```

**確認：** 構築・起動のエラーがなく終了したら、次で状態を確認します。

```sh
sudo docker compose ps
sudo docker compose logs --tail 50
```

**確認：** 最新のSTARTUPが取得した版と同じ `v1.10.1` で、各アカウントの `MyDNS update: OK` を確認します。
健康状態は次の4-2で確認します。

通知成功の記録も確認します。

```sh
sudo ls -l state/state.conf
```

ファイルが表示されれば生成されています。既存stateを引き継いだ場合は、IP不変・通知期限前なら通知を見送ります。
DEBUG=0ではその周期のログが増えなくても正常です。

### 4-2. 自動で有効になったヘルスチェックを確認する

```sh
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
```

**成功：** `running healthy` と表示されます。
起動直後のstartingは判定待ちです。30〜60秒程度待ち、同じコマンドを再実行します。
定期確認はこのコマンドを閉じた後もDockerが続けます。手動で毎回実行する必要はありません。

unhealthyは異常判定ですが、その表示だけでは自動再起動しません。
処理が固まった場合の復帰も必要なら、基本の導入確認後に[自動復帰](docker-systemd-recovery.md)を追加します。
プロセスが終了した際の再起動設定は、付属Composeに含まれる別の仕組みです。

**ここまでで基本の導入は完了です。**
開発版の検証は[Dockerの動作確認](docker-testing.md)の手順1へ進みます。
通常利用で自動復帰を追加する場合は[Dockerの自動復帰](docker-systemd-recovery.md)へ進みます。
追加しない場合は、そのまま通常運用できます。

**困ったときだけ：** unhealthyや設定・認証エラーが出たら、ログを確認してから続けます。
healthyは処理の進行を示すもので、MyDNS.JPへの通知成功とは別です。

## 停止・再開・ログの確認

以下は、必要な操作だけを選びます。Composeの操作はcompose.yamlのある場所で行います。

| 操作 | コマンド |
| --- | --- |
| ログを表示 | `sudo docker compose logs --tail 50` |
| 停止 | `sudo docker compose stop` |
| 停止したコンテナを再開 | `sudo docker compose start` |
| 状態を表示 | `sudo docker compose ps -a` |

設定ファイルの編集は次の確認周期で反映されます。詳細は[設定変更の反映](../README.md#設定変更の反映)を参照してください。

## 更新する場合

[旧版からの変更点](../README.md#更新方法)を確認し、configとstateをバックアップします。
自動復帰を設定済みの場合だけ、先に [Docker自動復帰タイマー](docker-systemd-recovery.md) を止めます。

```sh
sudo systemctl stop mydns-updater-docker-recovery.timer mydns-updater-docker-recovery.service
```

自動復帰を使っていない場合は上の操作を飛ばします。次に、compose.yamlがある場所で更新コンテナを停止します。

```sh
sudo docker compose stop
```

同じv1.10.1のupdate.sh・libフォルダー全体・compose.yamlを上書きします。設定例を実設定へコピーしません。
v1.9.0からの更新ではlibの読み込み設定が増えるため、停止したコンテナの開始だけでは足りません。
次で配置を確認し、コンテナを再作成します。

```sh
pwd
ls -l update.sh lib/*.sh compose.yaml
grep '^VERSION=' update.sh
sudo docker compose config --quiet
```

update.sh・lib内の6ファイル・compose.yamlが表示され、版が1.10.1、最後の構文確認でエラーがなければ続けます。

```sh
sudo docker compose up -d --force-recreate
sudo docker compose logs --tail 50
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
```

起動バージョンが1.10.1で、設定エラーがなく、30〜60秒後に再確認して `running healthy` になれば成功です。
stateを引き継ぐため、通知期限前は更新成功ログが増えなくても構いません。

**自動復帰を最初に止めた場合だけ：** 確認後に `sudo systemctl start mydns-updater-docker-recovery.timer` で再開します。

Dockerfileや依存ソフトも変更した場合だけ、再作成コマンドに `--build` を追加します。
configとstateを削除する必要はありません。

## 詳しい動作確認と自動復帰

通常動作・設定変更・異常表示を詳しく試す場合は[Dockerの動作確認](docker-testing.md)へ進みます。
導入済みの設定を引き継ぎます。取得や初回設定のコピーを繰り返しません。

自動復帰を使う場合は[通常のDockerの自動復帰手順](docker-systemd-recovery.md)へ進みます。
定期実行にはホストのsystemdを使います。Linux直接実行版のサービスとは別です。
