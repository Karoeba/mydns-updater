# Linuxの動作確認手順

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。始める前に[取得する版の確認](current-version.md)を確認してください。

[資料一覧](README.md) ／ [Linux導入手順](linux.md) ／ [模擬テストの説明](testing.md)

**この資料は、実アカウントを設定して起動した後の詳しい確認です。**
まだプログラムを配置していない場合は、先に[Linux導入手順の1〜5](linux.md)を終えてください。
導入前の模擬テストとは別で、ここでは実際にMyDNS.JPへ通知します。

Ubuntuの端末で行います。NAS本体のSSHやDockerコンテナ内では実行しません。
同じ実アカウントを使うNAS・Docker側は停止したままにします。

このページは全コース共通の基本試験です。監視・自動復帰はまだ追加しません。
[試験コース](test-start.md)で選んだ順番に進めます。

## 1. 通常動作を確認する

試験中は経過を見やすくするため、共通設定の該当行を変更します。重複追加はしません。

```sh
sudo nano /etc/mydns-updater/mydns.conf
```

```ini
CHECK_INTERVAL=60
FORCE_UPDATE_INTERVAL=3600
DEBUG=1
```

保存した値を確認します。IDやパスワードは表示しません。

```sh
sudo grep -E '^(CHECK_INTERVAL|FORCE_UPDATE_INTERVAL|DEBUG)=' /etc/mydns-updater/mydns.conf
```

**確認：** 上の3項目が、同じ値で1行ずつ表示されます。
設定は次の確認周期で反映されます。変更前が300秒なら、最大でその待ち時間が残るため、すぐに1分間隔へ変わらないことがあります。

```sh
sudo journalctl -u mydns-updater -n 50 --no-pager
sudo ls -l /var/lib/mydns-updater/state.conf
sudo -u mydns-updater env MYDNS_HEALTH_FILE=/run/mydns-updater/health sh /usr/local/lib/mydns-updater/update.sh --healthcheck
```

**成功：** 起動ログがv1.11.0、CHECKが約1分間隔、state.confが存在し、HEALTHYと表示されます。
各アカウントの通知成功は `MyDNS update: OK` で確認します。
既存stateを引き継いだ場合は、通知期限前のSKIPは正常です。手順2の定期通知まで確認します。

エラーがある場合は、その内容を解決してから手順2へ進みます。

## 2. 設定変更・定期通知・状態の引き継ぎを確認する

共通設定を開きます。

```sh
sudo nano /etc/mydns-updater/mydns.conf
```

`CHECK_INTERVAL=300` へ変更し、`FORCE_UPDATE_INTERVAL=3600` は試験用に残します。DEBUGは最初は1のままにします。

サービスを再起動せず、次の確認周期以降に約5分ごとのCHECK/SKIPログになることを確認します。必要ならDEBUG=0へ変更し、詳細ログが止まることも確認します。

```sh
sudo journalctl -u mydns-updater -f
```

定期通知は「サービス起動から」ではなく、アカウントごとの前回成功から1時間を過ぎた次の周期です。各アカウントの `MyDNS update: OK` が出れば成功です。


Ctrl+Cでログ表示を終了します。通知成功を確認したらDEBUG=1に戻し、状態の引き継ぎを試します。
設定を保存し、次の周期で詳細ログが出た後、次を実行します。

```sh
sudo systemctl restart mydns-updater
sudo journalctl -u mydns-updater -n 30 --no-pager
```

**成功：** 新しいSTARTUPがあり、IP不変・通知期限前ならSKIPになります。
起動直後でまだ結果がなければ、少し待ってログ表示だけを再実行します。
state.confを消して試す必要はありません。

## 基本試験の完了

ここでは停止せず、最初に選んだコースの次のページへ進みます。

| 最初に選んだコース | 次のページ |
| --- | --- |
| L1 監視のみ | [監視の導入と試験](linux-monitor.md) |
| L2 自動復帰 | [自動復帰の導入と試験](linux-recovery.md) |
| L0 追加監視なし | [再起動確認・記録・試験終了](linux-test-finish.md) |

このページへ戻る操作はありません。
