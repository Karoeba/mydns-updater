# Synology Container Managerで使う

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。始める前に[取得する版と更新時の確認](current-version.md)を確認してください。

[環境を選ぶ](../README.md#起動方法) ／ [資料一覧](README.md)

NAS本体のContainer Managerで使う手順です。NAS上のUbuntu VMにDockerを入れた場合は、[通常のDockerの手順](docker.md)を使います。
設定項目とログの意味は[共通の説明](../README.md#設定ファイル)にまとめています。

## 目的に合わせて進む

| 目的 | 進む順番 |
| --- | --- |
| 開発版を検証する | 1 準備 → 2 模擬テスト → 3 実アカウント設定 → 4 プロジェクト作成 → 5 起動確認 → 6 詳しい確認 |
| 通常導入する | 1 → 3〜5。模擬テストは任意。その後、自動復帰は使う場合だけ追加 |
| 導入済みの版を更新する | [更新する場合](#更新する場合)へ |

操作はDSMとFile Stationで行います。NAS上のUbuntu VMとは別の環境です。
模擬テストでは実アカウントを使わず、実通知の確認は手順3以降で行います。

## 1. ファイルを用意する

Container Managerが使えるNASで、使用する版のZIPをダウンロードして展開します。
[v1.11.0の試験用ZIP](https://github.com/Karoeba/mydns-updater/archive/refs/heads/v1.11.0-image-package.zip)からプログラム一式を取得できます。

File Stationで、共有フォルダー `docker` の中に `mydns-updater` を作り、展開した中身をアップロードします。
フォルダー名にバージョンは入れません。ZIPの外側のフォルダーを重ねて入れないようにしてください。

次は手順3まで終えた後の配置です。今は取得した一式を置き、config内の実設定は手順3で用意します。
既存環境の更新なら、下の「更新する場合」へ進みます。

```text
docker/mydns-updater/
├── .dockerignore        # 隠しファイルも含めて配置
├── Dockerfile
├── compose.yaml
├── update.sh
├── lib/                 # 6つの.shファイルをフォルダーごと配置
├── mydns.conf.example
├── accounts.conf.example
├── config/
│   ├── mydns.conf
│   └── accounts.conf
├── state/               # state.confは通知成功後に自動生成
└── tests/
    └── compose.yaml     # 同梱のテスト用。手順2では別の試験用フォルダーを使用
```

**確認：** File Stationのmydns-updater直下にDockerfile・compose.yaml・update.shがあります。
lib内にconfig.sh・diagnostics.sh・health.sh・network.sh・runtime.sh・state.shの6ファイルがあることも確認します。
ZIPの外側のフォルダーが余分に1段入っていなければ、次へ進みます。

| NAS上の場所 | コンテナ内で見える場所 |
| --- | --- |
| update.sh（構築時に格納） | /app/update.sh |
| lib/（構築時に格納） | /app/lib/ |
| config/ | /config/ |
| state/ | /state/ |

configとstateの対応付けはComposeが行います。update.shとlibはイメージの構築時に格納します。コンテナ内へ手作業でコピーする必要はありません。
File Stationでは共有フォルダーdockerとして見えますが、SSHでは通常/volume1/dockerです。ボリュームが違う場合は実際の場所を使います。

## 2. 実アカウントを使わない模擬テスト

**開発版の検証では実施します。通常導入だけなら手順3へ進めます。**
[Container Managerでの模擬テスト](testing.md#synology-container-manager)を実行します。
テスト用は別フォルダーに配置し、プロジェクト名も分けます。リンク先にZIPの配置と作成操作を記載しています。

| 用途 | プロジェクト名 | プロジェクトのパス |
| --- | --- | --- |
| 模擬テスト | mydns-updater-test | /docker/mydns-recovery-check/tests |
| 通常運用 | mydns-updater | /docker/mydns-updater |

テスト用は実アカウントを使いません。本番用プロジェクトは、この後の手順4で作ります。

終了コード0とALL TESTS PASSEDを確認したら、このページの手順3へ戻ります。
模擬テストは終了するプログラムなので、最後にコンテナが停止するのは正常です。
実アカウントは不要で、既存の運用も止める必要はありません。

## 3. 実アカウントの設定を用意する

**ここから実アカウントを使います。** 同じアカウントを使う別環境の更新処理を停止します。

新規導入で設定がない場合だけ、File Stationでconfigとstateを用意します。
mydns.conf.exampleとaccounts.conf.exampleをそれぞれコピーし、
config/mydns.confとconfig/accounts.confという名前にします。

accounts.confにID・PASSWORD・DOMAINを記入します。[設定項目の説明](../README.md#設定一覧)
設定済みのファイルを記入例で上書きしません。stateは空で構いません。

**確認：** config内に拡張子.exampleの付かない2ファイルがあることを確認します。
state.confは起動後に生成されるため、手作業で作りません。

## 4. プロジェクトを作成する

1. Container Managerの「プロジェクト」→「作成」を開きます。
2. プロジェクト名を `mydns-updater` にします。
3. パスを、手順1で作った `/docker/mydns-updater` にします。
4. 配置済みのcompose.yamlを指定し、画面の案内に従って構築・開始します。

同じ名前のプロジェクトがある場合は新規作成を重ねず、既存の用途を確認してください。
別環境から実アカウントを移す場合は、先に元の環境を停止します。

## 5. 起動と通知を確認する

付属Composeには定期ヘルスチェックが含まれ、プロジェクトの構築で自動的に有効になります。
ヘルスチェックのためにDSMのタスクを登録する必要はありません。

### 5-1. 通知成功を確認する

コンテナmydns-updaterの「ログ」を開きます。

- `STARTUP`：最新の起動日時と `v1.11.0` を確認します。
- 各アカウントの `MyDNS update: OK`：MyDNS.JPへの通知成功です。
- File Stationの `state/state.conf`：通知成功の記録が生成されます。

既存stateを引き継いだ場合は、IP不変・通知期限前ならすぐには通知しません。
`DEBUG=1` ならIP確認と `SKIP` の理由を確認できます。

### 5-2. 自動で有効になったヘルスチェックを確認する

コンテナの健康状態も確認します。起動直後は判定待ちです。30〜60秒程度待って画面を更新し、「正常」になることを確認します。
この「正常」は処理が進んでいることを示し、通知成功は上のログで別に確認します。
DSMの画面を閉じても定期確認は続きます。

異常表示になっただけでは、自動再起動しません。
処理が固まった場合の復帰も必要なら、[Synologyの自動復帰](synology-recovery.md)を追加します。その際にDSMの定期実行を設定します。
Container Managerの「自動再起動」は、プロセス終了時の再起動設定です。ここで追加する自動復帰とは別です。

**ここまで確認できれば基本の導入は完了です。**
模擬テストが済んでいれば、ここで繰り返す必要はありません。

**困ったときだけ：** コンテナの終了・異常表示、設定・認証エラーが出た場合は、ログを確認してから続けます。
「正常」だけではMyDNS.JPへの通知成功を証明しません。設定した各アカウントの通知結果も確認します。

## 6. 詳しい確認または通常運用へ進む

**通常運用だけの場合：** このまま使えます。自動復帰が必要なら[Synologyの自動復帰](synology-recovery.md)へ進みます。

**開発版を検証する場合：** 次を順番に確認します。設定するのはFile Station上のconfig/mydns.confです。

| 操作 | 成功の目印 |
| --- | --- |
| DEBUG=1へ変更して保存 | 次の周期からCHECK・SKIPなどの詳細ログが出る |
| CHECK_INTERVAL=60へ変更して保存 | 次の周期以降、CHECKログが約1分間隔になる |
| FORCE_UPDATE_INTERVAL=3600へ変更して保存 | 各アカウントの前回通知成功から1時間を過ぎた確認周期でMyDNS update: OKが出る |
| 通知成功後にプロジェクトを停止・開始 | 新しいSTARTUPが出て「正常」になる。IP不変・期限前ならSKIP。stateは削除しない |

変更前の待機時間は残るため、保存した直後に間隔が変わらない場合があります。
すでに自動復帰を使っている場合は、停止・開始の確認前にDSMの該当タスクを一時的に無効にし、正常を確認してから再び有効にします。

自動復帰も試す場合は、続いて[Synologyの自動復帰手順](synology-recovery.md)へ進みます。
**その試験が終わるまでは、元の環境への切り戻しを行いません。**

すべて終えた後は、次のどちらか1つを選びます。

- 継続運用：試験用の設定を戻す。既定値はCHECK_INTERVAL=300、FORCE_UPDATE_INTERVAL=86400、DEBUG=0。
- 試験終了：自動復帰のDSMタスクを使っていれば無効にして適用し、更新プロジェクトを停止してから元の環境を再開する。

## 設定を変更する場合

File Stationなどで、使用中のconfig内の設定ファイルを編集・上書きします。
通常は再起動不要で、次の確認周期から反映されます。

反映を確かめたい場合はDEBUG=1にし、次の周期のログを見ます。
起動時に出た設定値は過去の記録なので、変更後も書き換わりません。
設定項目の説明は[README](../README.md#設定一覧)にあります。

## 更新する場合

[イメージ格納方式への移行・更新](image-migration.md)の共通準備と「Synology Container Manager」を実行します。
ファイルの上書きと停止・開始だけでは反映されません。使用中のYAMLで旧プログラムのマウントを外し、イメージを再構築してからコンテナを再作成します。
config・state・監視用フォルダー・DSMタスクは保持します。

## 自動復帰を追加する場合

通常のヘルスチェックは状態を表示する機能です。
自動復帰を使う場合は、[Synologyの自動復帰手順](synology-recovery.md)へ進みます。

NASのSSHとDSMのタスクスケジューラを使用します。Ubuntu用systemdの操作はNAS本体では行いません。
