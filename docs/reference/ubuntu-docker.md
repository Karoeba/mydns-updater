# 参考：UbuntuにDockerを用意する

[資料一覧](../README.md) ／ [Dockerの動作確認](../docker-testing.md)

Ubuntu Server 24.04 LTSの新しい試験環境に、Docker EngineとComposeプラグインを導入する手順です。DS1522+上のUbuntu VMでも使用できます。Docker Desktopは不要です。

VMの準備から始める場合は [Ubuntu VM構築例](synology-vm.md) を参照してください。以下はUbuntu側の端末で実行します。DSMのNAS本体では実行しません。

## 操作を始める前に

コマンドは手で打ち直すより、枠の中をコピーして使うと間違いを減らせます。1つの枠を実行し、その下の確認が済んでから次へ進みます。

Ubuntuへ接続した画面は `tester@mydns-linux-test:~$` のような表示です。名前は環境によって変わります。Windowsの `PS C:\Users\...>` とは区別します。

パスワード入力中に文字が出ないのは正常です。何も表示せず入力待ちに戻るコマンドもあります。ファイルの作成結果は、以下の確認コマンドで確かめます。

## 1. 既存環境を確認する

Dockerがすでに使える場合は、導入し直さず手順4で確認します。この手順はDocker未導入のUbuntuを想定しています。別のDockerパッケージやcontainerdを使用中の場合は、削除せず [公式の前提条件](https://docs.docker.com/engine/install/ubuntu/#uninstall-old-versions) と既存用途を確認してください。

<details>
<summary>Linux直接実行版を導入したVMだけ：更新サービスを停止する</summary>

Linux版を導入していないVMは、この操作を飛ばして手順2へ進みます。導入済みの場合は、同じアカウントの重複稼働を避けるため停止します。

定期監視を導入済みの場合だけ、先に次を実行します。

```sh
sudo systemctl disable --now mydns-updater-healthcheck.timer
```

自動復帰を導入済みの場合だけ、次も実行します。

```sh
sudo systemctl disable --now mydns-updater-recovery.timer
sudo systemctl stop mydns-updater-recovery.service
```

更新サービスを停止します。

```sh
sudo systemctl disable --now mydns-updater
sudo systemctl is-active mydns-updater.service
```

導入済みの環境で最後が `inactive` なら停止しています。`is-active` の終了コードが0以外になるのは、この場面では想定どおりです。停止を確認したら手順2へ進みます。

</details>

Dockerの導入と模擬テストの間はNASの運用を継続できます。実アカウントでVMのDocker版を起動する直前に、同じアカウントのNAS側も停止します。

## 2. Docker公式の配布元を登録する

以下は [Docker公式のUbuntu向け導入手順](https://docs.docker.com/engine/install/ubuntu/#install-using-the-apt-repository) に沿っています（2026年9月確認）。

```sh
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

**確認：** ダウンロードしたファイルを確認します。

```sh
ls -l /etc/apt/keyrings/docker.asc
head -n 1 /etc/apt/keyrings/docker.asc
```

ファイルのサイズが0でなく、次の1行が表示されれば、場所とファイルの形式を確認できています。正式な確認は後の `apt update` で行います。

```text
-----BEGIN PGP PUBLIC KEY BLOCK-----
```

`No such file or directory` なら、保存先やファイル名が違います。先へ進まず、直前のコマンドを確認してください。

次は、最初の行から最後の `EOF` までをまとめて実行します。Ubuntuの版とCPUの種類はコマンド内で取得します。

```sh
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
```

入力待ちが `>` のままなら、複数行の入力がまだ終わっていません。Ctrl+Cで中断し、最初の行からEOFまでをまとめてコピーし直します。

**確認：** 保存した内容を表示します。

```sh
cat /etc/apt/sources.list.d/docker.sources
```

Ubuntu 24.04・DS1522+のVMでは、次の6行です。別のCPUやUbuntuの版ではSuitesとArchitecturesが変わります。

```text
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
```

文字の抜け、余計な行、別の保存先になっていないかを確認してから進みます。

```sh
sudo apt update
```

Dockerの配布元を含む一覧が読み込まれ、エラーなく入力待ちに戻れば次へ進めます。`NO_PUBKEY`、`not signed`、`E:` がある場合は進めません。上の2ファイルの場所・名前・内容を確認し、解決しなければ表示を控えます。確認を無効にして先へ進む設定は行いません。

## 3. DockerとComposeをインストールする

```sh
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

**確認：** 次を実行します。

```sh
sudo systemctl is-active docker
```

`active` ならDockerが動いています。別の表示なら `sudo systemctl status docker --no-pager` で内容を確認します。

この例ではOS起動時にもDockerを起動します。試験コンテナを稼働させたままVMを再起動すると、コンテナ側の再起動ポリシーに応じて再開します。試験終了時は [Dockerの動作確認手順](../docker-testing.md) に沿って停止します。

## 4. 導入結果を確認する

```sh
sudo docker version
sudo docker compose version
sudo docker run --rm hello-world
```

確認する内容：

- `docker version` にClientとServerの情報が表示される。
- `docker compose version` にComposeのバージョンが表示される。
- 最後に `Hello from Docker!` が表示される。

`hello-world` は確認後に終了し、`--rm` によりコンテナを削除します。イメージは残ります。

この資料のDockerコマンドは `sudo` 付きです。Dockerグループへのユーザー追加は必要ありません。sudoなしの設定を選ぶ場合、そのグループはroot相当の権限を持つことを理解したうえで [公式の導入後設定](https://docs.docker.com/engine/install/linux-postinstall/) を参照してください。

## 5. ツールの導入と試験へ進む

[Dockerの動作確認手順](../docker-testing.md) で、コードの取得、模擬テスト、実アカウントの設定、起動、異常・復旧を順に確認します。

UbuntuへのDocker導入は環境準備です。MyDNS.JPへの通知成功を確認したことにはならないため、導入後の確認も行ってください。
