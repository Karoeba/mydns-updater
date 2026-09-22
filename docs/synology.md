# Synology Container Managerで使う

[環境を選ぶ](../README.md#起動方法) ／ [資料一覧](README.md)

NAS本体のContainer Managerで使う手順です。NAS上のUbuntu VMにDockerを入れた場合は、[通常のDockerの手順](docker.md)を使います。
設定項目とログの意味は[共通の説明](../README.md#設定ファイル)にまとめています。

## 1. ファイルを用意する

Container Managerが使えるNASで、使用する版のZIPをダウンロードして展開します。
今回の試験には[v1.10.0のZIP](https://github.com/Karoeba/mydns-updater/archive/refs/heads/v1.10.0-modular-core.zip)を使います。まだmainにマージしていない開発版です。

File Stationで、共有フォルダー `docker` の中に `mydns-updater` を作り、展開した中身をアップロードします。
フォルダー名にバージョンは入れません。ZIPの外側のフォルダーを重ねて入れないようにしてください。

新規導入時は次のように用意します。既存環境の更新なら、下の「更新する場合」へ進みます。

```text
docker/mydns-updater/
├── Dockerfile
├── compose.yaml
├── update.sh
├── lib/                 # 6つの.shファイルをフォルダーごと配置
├── mydns.conf.example
├── accounts.conf.example
├── config/
│   ├── mydns.conf
│   └── accounts.conf
└── state/
```

設定例をそれぞれコピーし、`config/mydns.conf` と `config/accounts.conf` にします。
accounts.confに自分のID・PASSWORD・DOMAINを記入します。
stateは空のままで構いません。通知成功の記録は起動後に自動生成されます。

**確認：** File Stationでmydns-updaterを開いた直下にcompose.yamlとupdate.shがあり、lib内にconfig.sh・diagnostics.sh・health.sh・network.sh・runtime.sh・state.shがあり、config内に2つの設定ファイルがあることを確認します。
READMEやtestsなどが残っていても構いません。模擬テストを行う場合はtestsも残します。

## 2. プロジェクトを作成する

1. Container Managerの「プロジェクト」→「作成」を開きます。
2. プロジェクト名を `mydns-updater` にします。
3. パスを、手順1で作った `/docker/mydns-updater` にします。
4. 配置済みのcompose.yamlを指定し、画面の案内に従って構築・開始します。

同じ名前のプロジェクトがある場合は新規作成を重ねず、既存の用途を確認してください。
別環境から実アカウントを移す場合は、先に元の環境を停止します。

## 3. 起動と通知を確認する

コンテナmydns-updaterの「ログ」を開きます。

- `STARTUP`：導入したバージョンを確認します。
- 各アカウントの `MyDNS update: OK`：MyDNS.JPへの通知成功です。
- File Stationの `state/state.conf`：通知成功の記録が生成されます。

既存stateを引き継いだ場合は、IP不変・通知期限前ならすぐには通知しません。
`DEBUG=1` ならIP確認と `SKIP` の理由を確認できます。

コンテナの健康状態も確認します。起動直後は判定待ちで、その後「正常」になります。
この「正常」は処理が進んでいることを示し、通知成功は上のログで別に確認します。

**ここまで確認できれば通常の導入は完了です。** 詳細な模擬テストは[テスト手順](testing.md#synology-container-manager)を参照してください。

## 設定を変更する場合

File Stationなどで、使用中のconfig内の設定ファイルを編集・上書きします。
通常は再起動不要で、次の確認周期から反映されます。

反映を確かめたい場合はDEBUG=1にし、次の周期のログを見ます。
起動時に出た設定値は過去の記録なので、変更後も書き換わりません。
設定項目の説明は[README](../README.md#設定一覧)にあります。

## 更新する場合

1. [使用中の版からの変更点](../README.md#更新方法)を確認します。
2. 自動復帰を設定済みの場合だけ、DSMのタスクスケジューラで該当タスクの有効チェックを外し、適用します。実行中の処理が終わってから続けます。
3. configとstateをバックアップし、Container Managerでプロジェクトを停止します。
4. 同じv1.10.0のupdate.sh・libフォルダー全体・compose.yamlを上書きします。設定例を実設定へ上書きしません。
5. 手順1の配置図と照合し、lib内に6つの.shファイルがあることを確認します。
6. プロジェクトで使用中のYAMLにも `./lib:/app/lib:ro` があることを確認します。プロジェクトの「クリーンアップ」後に「構築」でコンテナを再作成・開始します。config・stateやプロジェクトの保存フォルダーは削除しません。
7. 起動ログがv1.10.0で、健康状態が「正常」、設定エラーがないことを確認します。
8. 手順2で自動復帰を止めた場合だけ、有効チェックを戻して適用し、[定期実行の確認](synology-recovery.md#4-定期実行を確認する)を行います。

**v1.9.0からの更新ではComposeの変更があるため、停止・開始だけでは反映されません。**
保存名がdocker-compose.ymlになっている場合もあるため、使用中のファイルを確認します。
Dockerfileや依存ソフトの変更がある場合はイメージも再構築します。

configとstateは保持します。イメージ名の `mydns-updater:local` はそのままで、実行バージョンは起動ログで確認します。

## 自動復帰を追加する場合

通常のヘルスチェックは状態を表示する機能です。
自動復帰を使う場合は、[Synologyの自動復帰手順](synology-recovery.md)へ進みます。

NASのSSHとDSMのタスクスケジューラを使用します。Ubuntu用systemdの操作はNAS本体では行いません。
