# Synologyで自動復帰方式を試す（開発用）

この手順は、自動復帰に使う方式を確かめるためのものです。
本番への自動復帰の導入はまだ行いません。

試験専用コンテナを新しく作り、そのコンテナだけを停止・再起動・削除します。
稼働中のmydns-updaterは停止せず、そのままにしてください。
本番のconfigやstateは使いません。

## 1. 試験ファイルを別のフォルダーに用意する

[v1.10.0-modular-coreブランチのZIP](https://github.com/Karoeba/mydns-updater/archive/refs/heads/v1.10.0-modular-core.zip)をダウンロードして展開します。

File Stationで、展開した中身を次の場所にアップロードしてください。

```text
/volume1/docker/mydns-recovery-check/
├── update.sh
├── lib/（6つの.shファイル）
└── tests/
    └── test-docker-cooperative-recovery.sh
```

ほかのファイルも一緒に置いて構いません。
本番のmydns-updaterフォルダーへ上書きしないでください。
Container Managerでプロジェクトを作る必要はありません。

## 2. NASにSSH接続し、配置を確認する

ここからのコマンドはNASのSSH画面で実行します。

```sh
cd /volume1/docker/mydns-recovery-check
pwd
ls -l update.sh lib/*.sh tests/test-docker-cooperative-recovery.sh
```

正しく進めば、最初に/volume1/docker/mydns-recovery-checkが表示され、
その下にupdate.shとtests/test-docker-cooperative-recovery.shの2つとlib内の6ファイルが表示されます。

「No such file or directory」が出た場合は、ここで止めて配置を確認してください。
ZIPの外側のフォルダーが余分に入っている可能性があります。

## 3. 試験を実行する

```sh
sudo sh tests/test-docker-cooperative-recovery.sh --disposable-test > recovery-probe.log 2>&1
probe_result=$?
cat recovery-probe.log
printf '\n試験の終了コード: %s\n' "$probe_result"
```

パスワードを求められたらNASの管理者パスワードを入力します。
入力中は文字が表示されません。

結果はファイルへ保存するため、実行中はほとんど表示されません。
通常は数分で終わります。初回は試験用Alpineイメージの取得に時間がかかる場合があります。

正常終了すると、最後付近に次の2つが表示されます。

```text
ALL COOPERATIVE RECOVERY EXPERIMENTS PASSED (7 checks)
試験の終了コード: 0
```

途中の「container ... is not running」は、停止したコンテナに依頼しても起動しないことを試したときの想定内の表示です。
最後の成功表示と終了コードで判断してください。

最後の項目では、設定ファイルを渡していない実際のupdate.shの終了動作を確認します。
MyDNS.JPへの通信や実アカウントの更新は行いません。

<details>
<summary>成功表示が出ない・終了コードが0以外の場合だけ</summary>

同じ試験を繰り返す前に、recovery-probe.logを共有してください。
試験は終了時に、自分で作ったコンテナの削除を試みます。

強制終了などで試験コンテナが残った場合は、次の読み取り専用コマンドで確認できます。

```sh
sudo docker ps -a --filter label=mydns.test=cooperative-recovery
```

この表示を共有してください。広い範囲のコンテナを一括削除する必要はありません。

</details>

## 4. 記録を渡す

File Stationでmydns-recovery-check内のrecovery-probe.logをパソコンへダウンロードし、
チャットへ添付してください。

記録にはDockerのバージョン、7項目の判定、失敗時のメッセージが入ります。
アカウント設定は読み込みません。

この試験の成功後に、異常の連続回数・再起動の間隔・回数上限・手動解除を組み込む確認へ進みます。
