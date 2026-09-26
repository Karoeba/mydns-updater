# 取得する版と更新時の確認

<!-- current-version: 1.11.0 -->
現在の対象版は **v1.11.0** です。試験ブランチは `v1.11.0-image-package`、mainはv1.10.1です。
Releaseと配布用イメージは未公開です。今回は手元でイメージを構築します。
Docker版とLinux直接実行版は同じupdate.sh・libを使います。

## 1. 同じ一式を取得する

新規導入は[Docker](docker.md)、[Synology](synology.md)、[Linux直接実行](linux.md)へ進みます。
更新時は運用先に直接展開せず、別フォルダーへ取得します。Linux側の端末での例です。
同名フォルダーがあれば繰り返さず、取得済みの版を確認してください。

```sh
git clone --branch v1.11.0-image-package --single-branch https://github.com/Karoeba/mydns-updater.git mydns-updater-source-1.11.0
cd mydns-updater-source-1.11.0
git rev-parse HEAD
grep '^VERSION=' update.sh
ls -l Dockerfile .dockerignore compose.yaml update.sh lib/*.sh health-recover.sh docker-health-recover.sh
```

**確認：** VERSIONが `1.11.0`、lib内に6ファイルが表示されます。コミット番号も記録します。
違う版なら配置へ進まず、取得元を確認します。
SynologyではPCで[試験用ZIP](https://github.com/Karoeba/mydns-updater/archive/refs/heads/v1.11.0-image-package.zip)を展開し、update.shをテキストとして開いて `VERSION="1.11.0"` を確認します。
同じ一式を使い、先頭が点の `.dockerignore` も省略せず配置します。

## 2. 保存するものと配置するものを分ける

| 環境 | 配置するもの | 保存するもの |
| --- | --- | --- |
| Docker・Synology | Dockerfile、.dockerignore、compose.yaml、update.sh、lib全体を構築用フォルダーへ | config、state、ホスト側の自動復帰スクリプト・設定・復帰履歴 |
| Linux直接実行 | update.sh、lib全体、health-recover.shを所定の場所へ | /etc/mydns-updater、/var/lib/mydns-updater、/var/lib/mydns-updater-recovery、独自のサービス設定 |

Dockerではプログラムをイメージに格納し、configとstateだけを外部に置きます。
Linuxの配置方法は変わらず、DockerfileやComposeは使いません。
既存の設定をexampleで上書きしたり、state.conf・status・diagnosticを削除したりしません。更新のための `--reset` も不要です。
具体的な操作は[Docker・Synologyの移行](image-migration.md)または[Linuxの更新](linux.md#更新方法)へ進みます。
今回、ホスト側自動復帰スクリプトと共通の更新処理は変更していません。

## 3. 起動した版まで確認する

各環境のログで、最新のSTARTUPが `MyDNS updater v1.11.0 started` であることを確認します。
イメージ名のlocal、healthyやactiveだけでは版は判別できません。日時を見て古いログと区別し、必要なら表示件数を増やします。
Dockerでは `running healthy`、Linuxでは `active (running)` と `HEALTHY` が成功の目印です。
通知成功は各アカウントの `MyDNS update: OK` で別に確認します。
stateを引き継ぐためIP不変・期限前なら通知を省略します。成功ログを出すためにstateを削除せず、次の通知期限を待ちます。
更新前に止めた監視だけを正常確認後に再開します。[検証範囲](testing.md#v1110の確認範囲)は自動試験と実機確認を分けて記載します。
