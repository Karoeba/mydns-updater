# 通常のDocker・Composeで使う

[環境を選ぶ](../README.md#起動方法) ／ [資料一覧](README.md)

UbuntuなどのDocker EngineとComposeで使う手順です。NAS上のUbuntu VMもこちらです。
NAS本体のContainer Managerで使う場合は[Synologyの手順](synology.md)を選びます。

以下のコマンドはDockerを動かすLinux側の端末で実行します。
Docker未導入なら、先に[UbuntuへのDocker導入](reference/ubuntu-docker.md)を行います。

## 1. 作業フォルダーを用意する

使用する版を取得します。次はv1.9.0の開発ブランチを新しいフォルダーへ取得する例で、公開済みリリースとは別です。
同名フォルダーがすでにある場合は取得を繰り返さず、中身を確認します。

```sh
git clone --branch docker-recovery-validation --single-branch https://github.com/Karoeba/mydns-updater.git mydns-updater-docker
cd mydns-updater-docker
pwd
ls -l compose.yaml update.sh mydns.conf.example accounts.conf.example
```

**確認：** 現在の場所がmydns-updater-dockerで、指定した4ファイルが表示されます。
ZIPで取得済みなら、その中身を置いたフォルダーへ移動して同じ4ファイルを確認します。

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

## 2. 設定ファイルを用意する

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

## 3. 構築して開始する

同じ実アカウントのNASやLinux直接実行版が動いている場合は、先にそちらを停止します。
同じDocker環境にmydns-updaterコンテナがある場合は、新規導入を重ねず用途を確認します。

```sh
sudo docker compose config --quiet
```

何も表示されず入力待ちへ戻れば、Composeの構文確認は成功です。エラーがあれば直してから続けます。

```sh
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs --tail 50
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mydns-updater
```

**確認：** 起動ログのバージョンと各アカウントの `MyDNS update: OK` を確認します。
状態は `running healthy` が目印です。`starting` なら30〜60秒待ち、最後の確認コマンドを再実行します。

通知成功の記録も確認します。

```sh
sudo ls -l state/state.conf
```

ファイルが表示されれば生成されています。既存stateを引き継いだ場合は、IP不変・通知期限前なら通知を見送ります。
DEBUG=0ではその周期のログが増えなくても正常です。

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
プログラムだけを置き換える場合は、次で停止します。

```sh
sudo docker compose stop
```

update.shなど変更されたファイルを上書きしたら、開始します。設定例を実設定へコピーしません。

```sh
sudo docker compose start
sudo docker compose logs --tail 50
```

新しい起動バージョンと、設定エラーがないことを確認します。

**Composeの変更がある場合だけ：** 上のstartの代わりに `sudo docker compose up -d --force-recreate` で再作成します。
Dockerfileや依存ソフトの変更がある場合は `sudo docker compose up -d --build --force-recreate` を使います。
configとstateを削除する必要はありません。

## 詳しい動作確認と自動復帰

通常動作・設定変更・異常表示を順に試す場合は[Dockerの動作確認](docker-testing.md)へ進みます。
この試験では手動で再開し、自動復帰とは分けて確認します。

自動復帰を使う場合は[通常のDockerの自動復帰手順](docker-systemd-recovery.md)へ進みます。
定期実行にはホストのsystemdを使います。Linux直接実行版のサービスとは別です。
