# Docker共通：自動復帰の模擬試験

<!-- current-version: 1.11.0 -->
対象版は **v1.11.0** です。[取得する版の確認](current-version.md) ／ [試験コース](test-start.md)

D2・S2のコースで、自動復帰の配置・定期実行を設定する前に行います。
用意した応答と試験専用コンテナを使います。実アカウント用の設定・state・復帰履歴は使いません。

## 作業場所を確認する

最初に環境に合う場所を1つ選び、その端末で作業します。

| コース | 端末 | 作業場所 |
| --- | --- | --- |
| D2 | Ubuntuの端末 | ~/mydns-updater-docker |
| S2 | NAS本体のSSH | /volume1/docker/mydns-recovery-check |

そのフォルダーへcdで移動し、次を確認します。S2はSynology導入の模擬試験で置いた一式を使います。

```sh
pwd
ls -l tests/test-docker-recovery-integration.sh docker-health-recover.sh update.sh
grep '^VERSION=' update.sh
```

**確認：** 表の場所と3ファイルが表示され、版が1.11.0です。

## 模擬試験を実行する


取得したv1.11.0の作業フォルダーで実行します。SynologyではNASへSSH接続した端末、UbuntuではUbuntu側の端末です。
本番のconfigとstateをコピーする必要はありません。本番コンテナは動かしたままで構いません。

```sh
pwd
ls -l update.sh lib/*.sh docker-health-recover.sh tests/test-docker-recovery-integration.sh
```

指定した3ファイルとlib内の6ファイルが表示されたら実行します。見つからない場合は先へ進まず、取得した版と作業場所を確認してください。

```sh
sudo sh tests/test-docker-recovery-integration.sh --disposable-test > recovery-integration.log 2>&1
test_result=$?
cat recovery-integration.log
printf '\n試験の終了コード: %s\n' "$test_result"
```

試験専用コンテナを作り、期限超過から復帰・正常確認・手動停止・履歴解除まで試します。通常2〜3分です。
試験用コンテナのネットワークは無効で、本番設定は読みません。終了時に試験用コンテナを削除します。

```text
ALL DOCKER RECOVERY INTEGRATION TESTS PASSED
試験の終了コード: 0
```

この2行が成功の目印です。途中の `Container ... is restarting` だけでは失敗と判断しません。
失敗した場合は導入を進めず、今回のログを確認します。
この試験だけでは、DSMやsystemdからの定期実行を確認したことにはなりません。

### この試験の記録はすでに保存されています

上の試験コマンドは、実行した作業フォルダーに `recovery-integration.log` を自動で保存します。
別の保存コマンドや、保存のための再試験は不要です。
後から結果を見直したり、不具合を相談したりするときに使います。

Synologyの手順どおりに配置した場合、保存先は次の場所です。

```text
File Station：docker → mydns-recovery-check → recovery-integration.log
SSHでの場所：/volume1/docker/mydns-recovery-check/recovery-integration.log
```

Ubuntuなどでも、試験を実行したフォルダーの直下に同じ名前で保存されます。
保存先が分からない場合だけ、試験した端末で次を実行します。

```sh
pwd
ls -lh recovery-integration.log
```

pwdで作業フォルダーが表示され、その下にログの更新日時とサイズが出れば、ファイルを確認できています。
ファイルが見つからない場合は、試験時の作業フォルダーへ戻って確認します。

### Synologyで記録をPCへ保存する場合

NAS内の記録をそのまま残すだけでも構いません。PCへ持ち帰る場合は次の操作を行います。

1. DSMのFile Stationを開きます。
2. 共有フォルダー `docker` → `mydns-recovery-check` を開きます。
3. `recovery-integration.log` の更新日時が、今回の試験時刻になっていることを確認します。
4. ファイルを右クリックし、「ダウンロード」を選びます。
5. PCのダウンロード先でファイルを確認し、メモ帳などで開きます。

成功時のログには `ALL DOCKER RECOVERY INTEGRATION TESTS PASSED` が含まれます。
画面に表示した「試験の終了コード: 0」は、このログには含まれません。終了コードは試験直後の画面で確認します。
同じ場所で再試験するとログは上書きされるため、前回分も残したい場合は先にダウンロードして名前を変えます。

**この試験で保存する記録はrecovery-integration.logです。**
実アカウントの自動復帰ページに出てくるbefore.txt・after.txtなどは、実働コンテナでの自動復帰試験の記録です。
今回の組み合わせ試験だけを終えた段階では、それらを用意する必要はありません。

## 模擬試験の完了

この試験では実アカウントも、DSM・systemdの定期実行も使っていません。
次は選んだコースの実アカウント用の自動復帰を導入し、定期実行からの復帰を確認します。

- D2：[UbuntuのDocker自動復帰](docker-systemd-recovery.md)
- S2：[SynologyのDSM自動復帰](synology-recovery.md)

このページへの戻り操作はありません。
