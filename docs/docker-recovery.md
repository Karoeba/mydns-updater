# Dockerの自動復帰：共通の仕組み

<!-- current-version: 1.10.1 -->
対象版は **v1.10.1** です。始める前に[取得する版と更新時の確認](current-version.md)を確認してください。

[資料一覧](README.md)

v1.9.0で追加した任意の機能です。Synology Container Managerも通常のDockerも、同じ監視スクリプトを使います。
設定しなければ、これまでどおり異常の表示だけを行います。

操作手順は、自分の環境を1つ選んでください。

| 環境 | 導入・確認の手順 |
| --- | --- |
| Synology Container Manager | [DSMで定期実行する](synology-recovery.md) |
| UbuntuなどのDocker | [systemdで定期実行する](docker-systemd-recovery.md) |
| Linuxで直接実行（Dockerなし） | [Linux直接実行の自動復帰](linux-recovery.md) |

## 復帰する条件

| 項目 | 動作 |
| --- | --- |
| 対象 | 処理の進行期限超過が3回連続した場合 |
| 定期確認 | 約1分ごと。30秒以内の連続実行は回数に加えない |
| 再起動の間隔 | 前回の要求から10分以上 |
| 回数上限 | 直近1時間に3回まで。4回目が必要になった時点で手動解除待ち |
| 上限後 | 確認は続けるが、手動解除するまで復帰を要求しない |
| 手動停止・一時停止 | 停止中、Dockerのpause中のコンテナは起動・解除しない |

通信・認証・設定エラーがあっても、処理が進んでいれば再起動しません。
進行記録が読めない、壊れている、確認コマンドが失敗する場合も再起動せず、原因の確認が必要です。

Dockerが表示するunhealthyをさらに3回数えるのではなく、毎回、同じ進行記録を新しく検査します。
3分を超えて監視が途切れた場合は連続回数を数え直します。
期限には更新処理側の待機時間なども含むため、プロセスが止まった瞬間から3分で復帰するとは限りません。

復帰要求の履歴はホスト側に保存します。コンテナ・OSの再起動、正常復帰でも回数は消しません。要求の失敗や結果不明も1回に含めます。
時計が大きく過去に戻った場合も、手動解除待ちになります。

この上限は、この機能が出す復帰要求の上限です。プロセスの異常終了に対するDockerのunless-stoppedによる再起動回数を制限するものではありません。


## 本番導入前に組み合わせを試す

取得したv1.10.1の作業フォルダーで実行します。SynologyではNASへSSH接続した端末、UbuntuではUbuntu側の端末です。
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
後半に出てくるbefore.txt・after.txtなどは、実働コンテナでの自動復帰試験の記録です。
今回の組み合わせ試験だけを終えた段階では、それらを用意する必要はありません。

成功と記録を確認したら、[Synologyの手順](synology-recovery.md#通常運用のコンテナを確認する)または[通常のDockerの手順](docker-systemd-recovery.md)へ戻ります。

## ログの見方

| 表示 | 意味 |
| --- | --- |
| RESTART_ATTEMPT | 復帰を試みる。対象と直近1時間の回数を表示 |
| RESTART_REQUESTED | 終了を依頼した。まだ正常復帰の確定ではない |
| RESTART_REQUEST_UNCONFIRMED | 要求結果が不明。終了で通信が切れる場合もあるため、次の確認で判断 |
| RECOVERED | 要求後の確認が正常になった |
| BLOCKED | 回数上限や時計の巻き戻りで、手動解除待ち |

`--status` のblocked=1は手動解除待ち、pending=1は要求後の正常確認待ちです。
consecutiveは現在の連続期限超過回数、last_attemptは最後の要求時刻（UNIX秒、0は未要求）です。


### 状態表示の見方

| 表示 | 意味 |
| --- | --- |
| consecutive | 続けて期限超過を検出した回数。正常なら0 |
| pending | 復帰要求後の正常確認待ち。確認完了なら0 |
| blocked | 制限による手動解除待ち。通常は0 |
| last_attempt | 最後に復帰を試みたUNIX秒。未試行なら0 |

正常時は毎回ログを出しません。ログが空、または更新されないだけでは定期実行の失敗とは判断できません。
監視記録の更新時刻と、コンテナの健康状態、エラーログを組み合わせて確認します。
`--status` 自体は監視の実行や履歴のリセットを行いません。

## 試験の違いと確認状況

| 試験 | 確認すること |
| --- | --- |
| GitHub Actions | 模擬応答で条件・回数制限を検査し、試験用Dockerで復帰動作を確認 |
| 導入先の試験専用コンテナ | そのDocker環境で実際に復帰できるか。実アカウント不要 |
| 定期実行の確認 | DSMまたはsystemdから監視が呼び出されるか |
| 実働コンテナで1回確認 | 定期実行、異常検知、再起動、正常確認がつながるか |

実働コンテナで試す間はIP確認と通知が一時的に止まります。
回数上限まで繰り返す必要はありません。詳細な確認結果は[テストの確認状況](testing.md#作者による確認状況)にまとめています。

## 制限

- ローカルのDockerソケットを使用します。リモートDocker、rootless Docker、Podmanは対象外です。
- コンテナのPID 1が付属のupdate.shで、再起動ポリシーがunless-stoppedの構成が対象です。
- 1つの履歴フォルダーを複数コンテナやLinux直接実行版と共有しないでください。
- プロセスが終了要求に応答できない種類の停止や、Docker自体の異常は復帰できない場合があります。回数制限で要求の繰り返しを抑えます。
- この監視を有効にしても、通知成功やDNS応答の正常性は保証しません。
- 管理者がDockerのkill操作を行った場合、再起動ポリシーが抑止されることがあります。異常の再現に以前のdocker kill --signal STOPを使わないでください。



## 保存した記録の見方

ここからは、**実働コンテナで自動復帰を試した後の記録**について説明します。
本番導入前の組み合わせ試験のログは、[この試験の記録はすでに保存されています](#この試験の記録はすでに保存されています)を参照してください。

Synology・通常のDockerそれぞれの手順で記録用コマンドを実行すると、ホーム内のmydns-recovery-resultsへ保存されます。
後から結果を確認したり、不具合の相談で試験時の状態を伝えたりするためのものです。運用に必要なファイルではありません。

| ファイル | 後で確認すること |
| --- | --- |
| before.txt・after.txt | 左からID、開始時刻、再起動回数。今回の試験では回数が1増える |
| recovery.log | 今回の時刻のRESTART_ATTEMPTとRECOVERED |
| updater.log | 新しい起動バージョン、起動後の処理。DEBUG=1ならIP確認も分かる |
| health-final.json | 保存時点のStatusがhealthyであること |
| docker-version.txt | 試験したDockerのバージョンと環境 |

メモ帳などで開き、ファイル名ではなく内容と時刻を確認します。
health-final.jsonという名前でも、中のStatusがunhealthyなら、保存時点ではまだ異常です。
これらは保存時点の写しで、今の状態を自動表示するものではありません。

## 必要な場合だけ：記録をWindowsへコピーする

### SynologyのFile Stationで探す場合

`~/mydns-recovery-results` の `~` は、**SSHにログインしたユーザーのホームフォルダー**です。
作業中のdockerフォルダーや、PCのホームを意味するものではありません。

ユーザーホームサービスが有効で、SSHとDSMに同じユーザーでログインしている場合は、File Stationで次を開きます。

```text
home/
└── mydns-recovery-results/
    ├── before.txt
    ├── after.txt
    ├── recovery.log
    ├── updater.log
    ├── health-final.json
    └── docker-version.txt
```

管理者としてhomesが見える場合は、`homes → SSHにログインしたユーザー名 → mydns-recovery-results` からも探せます。
homeは自分用、homesは各ユーザーのホームをまとめた場所です。
[Synologyのユーザーホームの説明](https://kb.synology.com/en-global/DSM/tutorial/user_enable_home_service)

1. File Stationで上記のフォルダーを開きます。
2. 中のファイルの更新日時が今回の試験時刻と合うことを確認します。
3. 必要なファイルを選択して右クリックし、「ダウンロード」でPCへ保存します。

**見つからない場合だけ：** 試験したNASのSSH画面で次を実行します。

```sh
whoami
printf '記録の保存先: %s/mydns-recovery-results\n' "$HOME"
ls -lh "$HOME/mydns-recovery-results"
```

最初にSSHのユーザー名、次に保存先とファイル一覧が表示されます。
DSMに別のユーザーでログインしていると、homeからは別の場所が見えます。
rootへ切り替えた端末で保存した場合などは、File Stationから見えない場所になっていることもあります。
homeが表示されない場合はユーザーホームサービスや権限も関係します。記録を取るためだけに設定や権限を変更する必要はありません。
下のコピーコマンドで取得できるなら、その方法で構いません。

### Windowsのコマンドでコピーする場合

以下は、実働コンテナの試験記録をフォルダーごとコピーする手順です。
組み合わせ試験のrecovery-integration.logをSynologyから取得する場合は、[File Stationでダウンロード](#synologyで記録をpcへ保存する場合)できます。

各環境の手順で作ったmydns-recovery-resultsは、その端末のログインユーザーのホームにあります。
SSH接続中のLinux画面で、Windows向けのコピーコマンドを実行しないでください。

次は**WindowsのPowerShell**で行います。`PS C:\Users\...` のような入力待ち表示を確認します。
ユーザー名とIPアドレスを、記録を保存したNASまたはUbuntuのものへ置き換えます。

```powershell
scp -r user@192.168.1.50:~/mydns-recovery-results "$HOME\Downloads"
```

完了後、Windowsのダウンロード内にmydns-recovery-resultsがあり、ファイルの更新日時が今回の試験と合うことを確認します。
NASとUbuntuの両方の記録を保存する場合は、先に保存したフォルダーをmydns-recovery-results-synologyなどへ変更し、混ざらないようにします。
