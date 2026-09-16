# 参考：UbuntuにDockerを用意する

[資料一覧](../README.md) ／ [Dockerの動作確認](../docker-testing.md)

Ubuntu Server 24.04 LTSの新しい試験環境に、Docker EngineとComposeプラグインを導入する手順です。DS1522+上のUbuntu VMでも使用できます。Docker Desktopは不要です。

VMの準備から始める場合は [Ubuntu VM構築例](synology-vm.md) を参照してください。以下はUbuntu側の端末で実行します。DSMのNAS本体では実行しません。

## 1. 既存環境を確認する

Dockerがすでに使える場合は、導入し直さず手順4で確認します。この手順はDocker未導入のUbuntuを想定しています。別のDockerパッケージやcontainerdを使用中の場合は、削除せず [公式の前提条件](https://docs.docker.com/engine/install/ubuntu/#uninstall-old-versions) と既存用途を確認してください。

Linux直接実行版を試したVMでは、同じアカウントが重複稼働しないよう、導入済みの監視と更新を停止して自動起動も無効にします。

```sh
sudo systemctl disable --now mydns-updater-healthcheck.timer
sudo systemctl disable --now mydns-updater
sudo systemctl is-active mydns-updater.service
```

導入済みの環境で最後が `inactive` なら停止しています。`is-active` の終了コードが0以外になるのは、この場面では想定どおりです。Linux版を導入していないVMでは、この操作は不要です。

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
sudo apt update
```

エラーがあれば、インストールへ進む前に内容を確認してください。

## 3. DockerとComposeをインストールする

```sh
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

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
