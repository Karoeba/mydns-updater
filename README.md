# mydns-updater

MyDNS.JP のIPv4アドレス通知を定期的に実行する、シンプルなDockerコンテナです。

複数のMyDNSアカウントに対応しています。

## Features

- MyDNS.JP IPv4アドレス通知
- 複数アカウント対応
- 更新間隔を設定可能
- Docker Compose対応
- Alpine Linuxベース
- 設定ファイルの編集だけでアカウント追加・無効化が可能

## Requirements

- Docker
- Docker Compose

Synology Container Managerでも使用できます。

## Installation

リポジトリを取得します。

```bash
git clone https://github.com/Karoeba/mydns-updater.git
cd mydns-updater
```

設定ファイルのサンプルをコピーします。

```bash
cp mydns.conf.example mydns.conf
```

`mydns.conf` を編集して、MyDNS.JPのMasterID、Password、ドメイン名を設定します。

```ini
# Update interval in seconds
INTERVAL=3600

[1]
ID=your-master-id
PASSWORD=your-password
DOMAIN=example.mydns.jp
```

`INTERVAL=3600` の場合、3600秒（1時間）ごとに更新します。

複数アカウントを使用する場合は、セクションを追加します。

```ini
[1]
ID=your-master-id
PASSWORD=your-password
DOMAIN=example.mydns.jp

[2]
ID=your-second-master-id
PASSWORD=your-second-password
DOMAIN=example2.mydns.jp
```

使用しないアカウントは `#` を付けてコメントアウトできます。

## Start

```bash
docker compose up -d --build
```

## Logs

```bash
docker compose logs -f
```

正常に更新された場合は、次のように表示されます。

```text
2026-09-12 12:00:00 JST [example.mydns.jp] MyDNS update: OK
```

設定に問題がある場合：

```text
2026-09-12 12:00:00 JST [1] MyDNS update: CONFIG ERROR
```

更新に失敗した場合：

```text
2026-09-12 12:00:00 JST [example.mydns.jp] MyDNS update: FAILED
```

## Configuration

### INTERVAL

更新間隔を秒単位で指定します。

```ini
INTERVAL=3600
```

値が不正な場合は、デフォルトの3600秒が使用されます。

### ID

MyDNS.JPのMasterIDを指定します。

### PASSWORD

MyDNS.JPのMasterIDに対応するPasswordを指定します。

### DOMAIN

ログ表示用のドメイン名を指定します。

## Security

`mydns.conf` にはMyDNS.JPのMasterIDとPasswordが平文で保存されます。

`mydns.conf` はGitリポジトリへコミットしないでください。

このリポジトリの `.gitignore` では、以下のファイルを除外する想定です。

```text
mydns.conf
.env
```

## Notes

v1.0.0 はIPv4のみ対応しています。

MyDNS.JPへの通知には以下のエンドポイントを使用します。

```text
https://ipv4.mydns.jp/login.html
```

ログの時刻はJST（Asia/Tokyo）固定です。

## Version

### v1.0.0

Initial release.

- IPv4 support
- Multiple account support
- Configurable update interval
- Docker Compose support

## Disclaimer

This project is an unofficial tool and is not affiliated with MyDNS.JP.

Use at your own risk.
