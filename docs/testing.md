# テストの実行と結果の確認

テストは、GitHub上で行う自動テストと、利用者が導入先で行う確認に分かれます。

模擬テストでは通信結果を用意してプログラムの処理を確認します。実際のMyDNS.JPへの通知成功や、NAS・Linux機での継続動作は、実アカウントを設定して別途確認します。

## GitHub Actionsによる自動テスト

PR作成・更新時とmainへのpush時に、次のジョブを実行します。Actionsの「Docker tests」から手動実行もできます。このワークフロー名にはDockerとありますが、Linux直接実行のテストも含みます。

| ジョブ | 実行環境 | 確認する内容 |
| --- | --- | --- |
| Alpine mock tests | Docker（Alpine） | 既存処理37項目、診断20項目、設定分割10項目、配置先指定8項目、ヘルスチェック11項目、Linux用ヘルスチェック7項目。加えてLinuxのDockerホスト側から設定の置き換え4項目・健康状態の遷移3項目 |
| Documentation shell syntax | Ubuntu 24.04 | READMEとdocs内のsh／bashコード枠を構文検査。記載したコマンドは実行しません |
| Linux direct execution | Ubuntu 24.04（Docker不使用） | 配置先指定8項目・ヘルスチェック7項目・監視判定13項目、自動復帰判定16項目、systemdの定期実行5項目・自動復帰5項目とサービス定義の検査 |

配置先指定の8項目は両環境で実行します。サービス定義の検査に加え、CI専用の名前と模擬応答を使い、実際のsystemdタイマーで異常・復旧・停止連動を確認します。実アカウントでの常駐運用の確認とは別です。

結果はPRのChecksまたはActionsの各ジョブのログで確認できます。Docker側のレポートは成果物 `test-reports` として14日間保存されます。コンテナ起動前の失敗ではレポートがない場合があります。

文書の構文検査では、shのコード枠をUbuntuのshとbash、bashのコード枠をbashの `-n` で検査します。引用符やコマンド構文の誤りを検出するもので、インストールの成功、パス・権限の妥当性、手順を通した動作を保証するものではありません。実行場所や操作順は文書の点検と導入先での確認で補います。

### 結果バッジ

README冒頭のバッジはmainブランチへのpushで実行されたワークフローの状態を表示します。クリックするとActionsの実行履歴を開けます。

開発中のPRの結果は、そのPRのChecksで確認してください。バッジは実機確認の結果を表すものではありません。テスト失敗時のマージ禁止には別途リポジトリ設定が必要です。

## Docker自動復帰の検証

v1.9.0ではDocker 24.0.2とCIランナーのDockerで、実際の監視スクリプトと更新スクリプトを組み合わせて検証します。試験コンテナはネットワーク無効で、実アカウントは使用しません。

別の模擬テストで、連続判定・10分の間隔・直近1時間3回・手動解除・再作成・時計変更・要求失敗を確認します。停止の方式確認7項目は利用者のDS1522+（Docker 24.0.2）でも成功しています。方式確認と、今回追加した定期実行全体の実機確認は区別します。

## 手元の環境で模擬テストを実行する

GitHubからダウンロードしたコードを、導入先でも模擬テストできます。実アカウントは使いません。

**以下の3つから、試す環境の節を1つ選んで進めます。** Dockerのコマンドライン・Synology Container Manager・Linux直接実行を、順番にすべて行う手順ではありません。

### Dockerのコマンドライン

展開したフォルダーの直下（ルートの `compose.yaml` がある場所）で実行します。Dockerへアクセスできる権限が必要です。Ubuntuの新規導入では `docker` コマンドの先頭に `sudo` を付けます。

```sh
mkdir -p tests/reports
docker compose -f tests/compose.yaml run --build --rm test
```

模擬テスト中の外部通信は無効です。初回のイメージ取得など、構築には接続が必要です。

結果は `tests/reports` に保存され、成功時は次の6つの結果を表示して終了します。

- `ALL TESTS PASSED (37 checks)`
- `ALL DIAGNOSTIC TESTS PASSED (20 checks)`
- `ALL SPLIT CONFIG TESTS PASSED (10 checks)`
- `ALL LINUX TESTS PASSED (8 checks)`
- `ALL HEALTHCHECK TESTS PASSED (11 checks)`
- `ALL LINUX HEALTHCHECK TESTS PASSED (7 checks)`

途中の失敗ログは異常系テストに含まれるため、6種類すべての最後の結果を確認してください。`tests/reports/result.txt` の `ALL TESTS PASSED` も成功の目印です。構築エラー時に古いレポートが残っている場合があるため、今回の端末表示とファイルの更新日時も確認します。

LinuxのDockerホストでは、設定の置き換え4項目とDockerの健康状態遷移3項目も追加で実行できます。

```sh
sh tests/test-config-reload.sh
```

Dockerにsudoが必要な環境では `sudo sh tests/test-config-reload.sh` とします。成功時は `ALL CONFIG RELOAD TESTS PASSED (4 checks)` と `ALL DOCKER HEALTHCHECK TESTS PASSED (3 checks)` を表示します。実アカウントは使用しません。ヘルスチェックの待機・検査間隔を短縮し、期限切れも模擬的に作る試験です。

### Synology Container Manager

Container Managerでは、プロジェクトのパスを `tests` フォルダーにし、その中の `compose.yaml` を指定します。`tests/reports` を事前に作成し、`update.sh` は1つ上の階層に置いてください。

成功時の表示は上記のDockerテストと同じです。ホスト側の4＋3項目はこの操作では実行されません。設定の上書き反映とContainer Managerでの健康状態の変化は、別途確認します。

### Linux直接実行

展開したフォルダーの直下で実行します。

```sh
sh tests/test-linux.sh
sh tests/test-healthcheck-linux.sh
sh tests/test-health-monitor.sh
sh tests/test-health-recovery.sh
```

`ALL LINUX TESTS PASSED (8 checks)` と `ALL LINUX HEALTHCHECK TESTS PASSED (7 checks)`、`ALL MONITOR TESTS PASSED (13 checks)` に加え、`ALL RECOVERY TESTS PASSED (16 checks)` が出れば成功です。一時ディレクトリ内で模擬通信を使用し、実アカウントや既存設定には触れません。

必要なソフトの準備は [Linux導入手順](linux.md) を参照してください。監視テストにはutil-linuxのflockとcoreutilsのtimeoutを使います。

`tests/test-monitor-systemd.sh` と `tests/test-recovery-systemd.sh` は使い捨てのGitHub Actions環境専用です。導入先で実行せず、タイマーの確認にはLinux導入手順を使用してください。

## 導入先で実際の動作を確認する

模擬テストの成功後、通常の運用環境に設定ファイルを配置して起動します。同じ実アカウントを複数の環境で同時に動かさないでください。

Dockerでは [READMEの起動方法](../README.md#起動方法)、Linuxでは [Linux導入手順](linux.md) に沿って、次を確認します。

1. 起動ログに使用中のバージョンが表示される。
2. 各アカウントの通知が成功し、状態ファイルが生成される。
3. 設定ファイルを上書きすると、再起動せずに次の確認周期で反映される。
4. 再起動後も成功状態を引き継ぎ、IP不変・更新期限前なら通知をスキップする。
5. 定期更新の期限を過ぎた確認周期で、各アカウントの通知が成功する。
6. Dockerでは健康状態が `healthy`、Linuxでは導入手順の確認コマンドが `HEALTHY` になる。

`DEBUG=1` にすると確認周期とスキップ理由も表示されます。Linuxではサービスの常駐動作と、必要に応じてOS再起動後の自動起動も確認してください。

UbuntuのDockerコマンドラインで導入から試す場合は [Dockerの動作確認手順](docker-testing.md) を参照してください。Dockerの導入準備、実アカウントの切り替え、通常設定での異常・復旧と記録方法を説明しています。

Linuxでの異常・復旧、停止連動、OS再起動、結果保存は [Linuxの動作確認手順](linux-testing.md) を参照してください。

### 作者による確認状況

v1.3.0はDS1522+で37項目の既存テスト・20項目の診断テストと、本環境で2アカウントの定期更新を確認済みです。v1.4.0の設定分割もDS1522+で37+20+10項目の模擬テストが成功しています。

v1.7.0はDS1522+上のUbuntu Server 24.04 LTS（x86-64 VM）で、実アカウント2件の更新、定期通知、設定再読み込み、OS再起動後の自動起動・状態引き継ぎを確認しました。監視の一時停止によるUNHEALTHYと再開後のRECOVEREDは画面で確認済みです。ARM機は未検証です。

Ubuntu VM上のDockerでは、実アカウントの更新と、一時停止によるunhealthy・再開によるhealthyへの復帰を確認しました。停止前後の記録では、コンテナの作り直しや再起動が発生していないことも確認しています。

DS1522+のContainer Managerでも、一時停止による `UNHEALTHY: updater progress overdue` と、再開後の「正常」表示を確認しました。

v1.8.0の自動復帰は、CIでは模擬応答による条件・制限の検査と、systemdで実際に停止した試験用サービスを再起動する検査を行います。2026年9月18日、DS1522+上のUbuntu VMで [Linux自動復帰の動作確認](linux-recovery.md#4-動作を試す) を実施し、提示された画面で次を確認しました。

- v1.8.0の起動、実アカウント2件の通知成功、手動ヘルスチェックのHEALTHY。
- STOPによる処理停止後、PROGRESS_OVERDUEを理由とするRESTART_ATTEMPT（1/3）とRESTART_REQUESTEDを記録。
- 自動再起動後に起動番号が変わり、RECOVEREDとHEALTHYを確認。
- 再起動後も成功状態を保持し、両アカウントをSKIP。60秒ごとのIP確認と自動復帰タイマーの継続を確認。
- 手動停止後、更新サービスと自動復帰タイマーがともにinactive。時間を置いた再確認でも停止を維持。

10分の再試行間隔・直近1時間の3回制限・制限解除は自動テストで確認しており、今回のVM試験では実施していません。v1.8.0でのOS再起動後の確認とARM機の動作も未検証です。
