# 参考：DS1522+でUbuntuの試験環境を作る

[資料一覧](../README.md) ／ [Linux導入手順](../linux.md)

Synology DS1522+のVirtual Machine Manager（VMM）にUbuntu Server 24.04 LTSを用意した際の参考手順です。2026年9月の構成例で、DSM・VMM・配布ISOの版によって画面や名称は異なります。

NAS内に独立したLinuxの仮想マシン（VM）を作ります。VMにはDockerを入れず、Linux直接実行版を試します。x86-64環境の確認であり、Raspberry PiやNanoPiなどのARM機を検証したことにはなりません。

VM作成と模擬テストの間は既存のDocker版を動かせます。同じ実アカウントでLinux版を起動する前にDocker版を停止し、試験終了後はLinux版を停止してからDocker版へ戻します。

## 1. NASの準備を確認する

DSMで次を確認します。

1. **ストレージマネージャー**：VM保存先のファイルシステムがBtrfsであること。
2. **空き容量**：今回の目安として50GB程度以上。
3. **リソースモニター**：VMへ2GBを割り当てられるメモリの余裕。

50GB・2GBは今回の構成案です。NASの他のアプリもメモリを使います。

VMMのVMデータはBtrfsボリュームへ保存します。ext4しかない場合は、この実験のために既存ボリュームを初期化しないでください。[Synology公式仕様](https://www.synology.com/ja-jp/dsm/7.4/software_spec/vmm)

## 2. Virtual Machine Managerを入れる

DSMの「パッケージセンター」で **Virtual Machine Manager** を探し、インストールします。すでにある場合は開くだけです。

初期設定ではVMを保存するBtrfsボリュームを指定します。ネットワークの切り替えやNAS再起動を求められた場合は、ほかの稼働サービスへの影響を確認してから進めてください。

## 3. Ubuntuのインストール用ファイルを用意する

Windowsで [Ubuntu 24.04 LTSの公式ページ](https://releases.ubuntu.com/24.04/) を開き、**Server install image → 64-bit PC (AMD64) server install image** をダウンロードします。

確認時のファイル名は `ubuntu-24.04.5-live-server-amd64.iso` です。末尾が `live-server-amd64.iso` のServer版を選びます。Server版はWindowsのようなデスクトップ画面を備えず、文字で操作します。

VMMの「イメージ」からISOファイルを追加し、ダウンロードしたファイルを登録します。画面表記は導入しているVMMの版により多少異なります。[VMMのイメージ管理](https://kb.synology.com/sv-se/DSM/help/Virtualization/image?version=7)

## 4. 仮想マシンを作る

VMMの「仮想マシン」→「作成」でLinuxを選び、次を目安に設定します。

| 項目 | 設定 |
| --- | --- |
| 名前 | `mydns-linux-test` |
| CPU | 2 vCPU |
| メモリ | 2GB。余裕があれば4GB |
| 仮想ディスク | 30GB |
| ネットワーク | 自宅LANへ接続する仮想スイッチ |
| 起動用ISO | 手順3で登録したUbuntuのISO |
| NAS起動時のVM自動起動 | 試験中は無効 |

NASの実ディスクをVMへ直接渡す操作は不要です。新しい30GBの仮想ディスクだけを使います。

作成したVMを起動し、「接続」で画面を開きます。Ubuntuのインストール画面が出れば次へ進めます。[VMMの仮想マシン設定](https://kb.synology.com/en-global/DSM/help/Virtualization/virtual_machine?version=6)

## 5. Ubuntuをインストールする

選択画面では、矢印キーで移動、Enterで決定、チェック項目はSpaceで切り替えます。

| 画面・項目 | 選ぶ内容 |
| --- | --- |
| 言語 | 選びやすい言語。Englishでもよい |
| キーボード | 手元のキーボードに合わせる |
| インストールの種類 | 通常のUbuntu Server |
| ネットワーク | DHCPの自動取得。IPが割り当てられることを確認 |
| Proxy | 自宅でプロキシを使っていなければ空欄 |
| Mirror | 通常は既定値 |
| Storage | 今作った30GBの仮想ディスク全体を使用 |
| 名前・ユーザー名 | 自分で決める。ユーザー名の例：`tester` |
| Server name | `mydns-linux-test` |
| Password | Ubuntuへログインするパスワード |
| Ubuntu Pro | 試験ではスキップでよい |
| SSH | **Install OpenSSH serverを有効**。鍵の取り込みは不要 |
| 追加アプリ | 今回は選ばなくてよい |

ディスクへの書き込みを確定する前に、表示されている容量が今回の30GBであることを確認します。

完了したら再起動します。インストール媒体の取り外しを求められたら、VMMのVM設定で起動用ISOを外し、画面の案内に従います。

`mydns-linux-test login:` が出たら、設定したユーザー名とパスワードでログインします。[Ubuntu公式インストール手順](https://ubuntu.com/server/docs/tutorial/basic-installation/)

## 6. WindowsからUbuntuを操作する

Ubuntuで次を入力します。

```sh
hostname -I
```

表示された自宅LAN内のIPアドレスを控えます。これはNAS本体ではなく、Ubuntu VMのIPアドレスです。

WindowsでPowerShellを開き、次の形式で接続します。ユーザー名とIPは自分のものへ置き換えます。

```text
ssh tester@192.168.1.50
```

初回に接続先の確認が出ます。VMM画面のIPと合っていることを確認して進み、Ubuntuのパスワードを入力します。

`tester@mydns-linux-test:~$` のような表示になれば成功です。**以下のコマンドは、このUbuntuへ接続した画面で実行します。NASへのSSH接続ではありません。**

つながらない場合は、VMMの接続画面で次を確認します。

```sh
sudo systemctl status ssh --no-pager
```

SSHが未導入なら、Ubuntuで次を実行します。

```sh
sudo apt update
sudo apt install openssh-server
sudo systemctl enable --now ssh
```

自宅LANでの接続のために、ルーターのポートをインターネットへ開放する必要はありません。

---


## 次に進む

Ubuntuへ接続できたら、試す方法を選びます。Docker版を試す場合は [UbuntuへのDocker導入](ubuntu-docker.md) へ進み、その後 [Dockerの動作確認](../docker-testing.md) を行います。

Dockerを使わないLinux直接実行版は、[Linux導入手順](../linux.md) の「必要なソフトを準備する」から進めます。コマンドはUbuntu側で実行し、NAS本体のSSH画面には入力しません。

導入後は [Linuxの動作確認手順](../linux-testing.md) で通知・監視・再起動後の動作を確認できます。VMの構築だけなら、ここで中断して構いません。
