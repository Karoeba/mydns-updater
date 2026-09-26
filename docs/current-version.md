# 取得する版と更新時の確認

<!-- current-version: 1.10.1 -->
現在の対象版は **v1.10.1** です。修正はmainへマージ済みで、Releaseは未公開です。
この資料は取得・配置・起動で違う版を混ぜないための共通確認です。過去の試験結果の版番号は変更しません。

## 1. 同じ一式を取得する

新規導入では、[Docker](docker.md)、[Synology](synology.md)、[Linux直接実行](linux.md)の取得手順を使います。
更新の場合は、運用中のフォルダーへ直接展開せず、別の空のフォルダーへmainを取得してください。

Linux側の端末で、更新用に別フォルダーへ取得する例です。既存の同名フォルダーがあれば中身を確認し、別名を選びます。

```sh
git clone --branch main --single-branch https://github.com/Karoeba/mydns-updater.git mydns-updater-source-1.10.1
cd mydns-updater-source-1.10.1
git rev-parse HEAD
grep '^VERSION=' update.sh
ls -l update.sh lib/*.sh compose.yaml health-recover.sh docker-health-recover.sh
```

**確認：** VERSIONが `1.10.1`、lib内に6ファイルが表示されます。コミット番号も記録します。
今回の修正を取り込んだコミットは `ecf4bd2105c2986a8aea38ebbf6b14c8ae2302ad` です。
その後の文書更新でコミット番号が変わることはあります。版が違う場合は、取得した版に付属する手順を確認してから進めます。

SynologyではPCで[mainのZIP](https://github.com/Karoeba/mydns-updater/archive/refs/heads/main.zip)を取得し、展開先のupdate.shをテキストとして開いて `VERSION="1.10.1"` を確認します。
ZIPは同時に取得した一式を使い、libだけ別のダウンロードから混ぜないでください。
今回の試験対象を再現したい場合だけ、[対象コミットのZIP](https://github.com/Karoeba/mydns-updater/archive/ecf4bd2105c2986a8aea38ebbf6b14c8ae2302ad.zip)を使えます。そこに含まれる文書は今回の修正前です。

## 2. 保存するものと配置するものを分ける

更新時は環境別手順に従って監視・更新処理を停止し、実行中の監視が終わってからバックアップ・配置します。
更新用フォルダー全体を運用先へ上書きしません。初回導入用の設定コピーも繰り返しません。

| 環境 | 同じ取得元から配置するもの | 保持・バックアップするもの |
| --- | --- | --- |
| Docker | 運用フォルダーのupdate.sh、lib全体、compose.yaml | config、state。自動復帰の `/var/lib/mydns-updater-docker-recovery/` と独自のサービス設定 |
| Synology | File Stationのdocker/mydns-updaterへupdate.sh、lib全体、compose.yaml | config、state。docker/mydns-recoveryのstate・run.sh・DSMタスク設定 |
| Linux直接実行 | `/usr/local/lib/mydns-updater/` へupdate.sh、lib全体、health-recover.sh | `/etc/mydns-updater/`、`/var/lib/mydns-updater/`、`/var/lib/mydns-updater-recovery/`、独自のサービス設定 |

復帰履歴のstatusと診断用diagnosticは削除・初期化しません。更新のために `--reset` を実行する必要はありません。
独自の配置先を使っている場合は、表の標準パスを実際の場所に読み替えます。
Docker・Synologyのdocker-health-recover.shは今回変更していません。新規に自動復帰を追加するときは、同じ取得元のファイルを各自動復帰手順で配置します。

Linux更新では上で取得したフォルダーから[配置コマンド](linux.md#更新方法)を実行します。
Docker更新ではそこから必要なファイルだけを運用フォルダーへコピーし、**運用先のcompose.yamlがある場所**で再作成します。
SynologyではPCの展開先から表の運用先へ必要なファイルだけアップロードし、[更新手順](synology.md#更新する場合)で再作成します。

## 3. 起動した版まで確認する

配置後は環境別手順のログ確認を実行します。最新のSTARTUPが `MyDNS updater v1.10.1 started` であることを確認してください。
Dockerのイメージ名 `mydns-updater:local`、healthyやactiveだけでは、起動した版は分かりません。
過去のSTARTUPと混同しないよう日時も見ます。ログ末尾に起動行がない場合は表示件数を増やしてください。

成功の条件は、取得元と起動ログの版が同じで、設定エラーがなく、Dockerでは `running healthy`、Linuxでは `active (running)` と `HEALTHY` が確認できることです。
実通知は別に各アカウントの `MyDNS update: OK` で確認します。既存stateを引き継いだ場合はIP不変・期限前なら通知を省略します。
成功ログを出すためにstateを削除せず、次の通知期限を待ってください。

正常を確認してから、更新前に止めた自動復帰のタイマー・DSMタスクだけを再開します。
試験結果の確認範囲は[テスト記録](testing.md#v1101の確認範囲)にまとめています。
