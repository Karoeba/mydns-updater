# テストの実行と結果の確認

テストは、GitHub上で行う自動テストと、利用者が導入先で行う確認に分かれます。

模擬テストでは通信結果を用意してプログラムの処理を確認します。実際のMyDNS.JPへの通知成功や、NAS・Linux機での継続動作は、実アカウントを設定して別途確認します。

## 2種類のテストと使う順番

| 種類 | 実アカウント | 行う時期 | 確認できること |
| --- | --- | --- | --- |
| 模擬テスト | 不要 | コード取得後、通常導入前 | 用意した正常・異常応答に対する処理 |
| 導入後の動作確認 | 使用する | 配置・設定・起動後 | 実際の通知、設定変更、状態保存、起動・停止 |

開発版の検証では両方を行います。通常導入では模擬テストは任意ですが、導入後の通知成功と正常状態は確認します。
監視・自動復帰は通常動作の確認後、使う場合だけ追加します。
詳しい操作は[Linux](linux.md)・[Docker](docker.md)・[Container Manager](synology.md)の入口から進めます。

**合否の読み方：** 模擬テストには、故意にエラーを起こす項目があります。
途中のERRORなどではなく、各テストの成功表示と、テストコマンド全体の終了コード0を確認します。
実際の運用ログのエラーまで「試験だから正常」と扱わないでください。

## GitHub Actionsによる自動テスト

PR作成・更新時とmainへのpush時に、次のジョブを実行します。Actionsの「Docker tests」から手動実行もできます。このワークフロー名にはDockerとありますが、Linux直接実行のテストも含みます。

| ジョブ | 実行環境 | 確認する内容 |
| --- | --- | --- |
| Alpine mock tests | Docker（Alpine） | 既存処理37項目、診断20項目、設定分割10項目、配置先指定8項目、ヘルスチェック11項目、Linux用ヘルスチェック7項目。加えてLinuxのDockerホスト側から設定の置き換え4項目・健康状態の遷移3項目 |
| Documentation shell syntax | Ubuntu 24.04 | READMEとdocs内のsh／bashコード枠を構文検査。記載したコマンドは実行しません |
| Linux direct execution | Ubuntu 24.04（Docker不使用） | 配置先指定8項目・ヘルスチェック7項目・監視判定13項目、自動復帰判定16項目、systemdの定期実行5項目・自動復帰5項目とサービス定義の検査 |

v1.10.0では、Docker（Alpineのsh）とLinux直接実行（Ubuntuのsh）の両方で、分割したプログラムの配置試験も行います。
空白を含む配置先・別の作業フォルダーからの起動、6ファイルのそれぞれが欠けた場合の停止を確認します。
さらにコピー後の一式で、通知・設定再読み込み・状態保存・ヘルスチェックの既存テストを実行します。

配置先指定の8項目は両環境で実行します。サービス定義の検査に加え、CI専用の名前と模擬応答を使い、実際のsystemdタイマーで異常・復旧・停止連動を確認します。実アカウントでの常駐運用の確認とは別です。

結果はPRのChecksまたはActionsの各ジョブのログで確認できます。Docker側のレポートは成果物 `test-reports` として14日間保存されます。コンテナ起動前の失敗ではレポートがない場合があります。

文書の構文検査では、shのコード枠をUbuntuのshとbash、bashのコード枠をbashの `-n` で検査します。引用符やコマンド構文の誤りを検出するもので、インストールの成功、パス・権限の妥当性、手順を通した動作を保証するものではありません。実行場所や操作順は文書の点検と導入先での確認で補います。

### 結果バッジ

README冒頭のバッジはmainブランチへのpushで実行されたワークフローの状態を表示します。クリックするとActionsの実行履歴を開けます。

開発中のPRの結果は、そのPRのChecksで確認してください。バッジは実機確認の結果を表すものではありません。テスト失敗時のマージ禁止には別途リポジトリ設定が必要です。

## Docker自動復帰の検証

v1.9.0ではDocker 24.0.2とCIランナーのDockerで、実際の監視スクリプトと更新スクリプトを組み合わせて検証します。試験コンテナはネットワーク無効で、実アカウントは使用しません。

別の模擬テストで、連続判定・10分の間隔・直近1時間3回・手動解除・再作成・時計変更・要求失敗を確認します。停止の方式確認7項目は利用者のDS1522+（Docker 24.0.2）でも成功しています。方式確認と定期実行全体の実機確認は区別します。DSMでの定期実行から自動復帰までの確認結果は、下の「作者による確認状況」に記載しています。

## 手元の環境で模擬テストを実行する

GitHubからダウンロードしたコードを、導入先でも模擬テストできます。実アカウントは使いません。

**以下の3つから、試す環境の節を1つ選んで進めます。** Dockerのコマンドライン・Synology Container Manager・Linux直接実行を、順番にすべて行う手順ではありません。

### Dockerのコマンドライン

展開したフォルダーの直下（ルートの `compose.yaml` がある場所）で実行します。Dockerへアクセスできる権限が必要です。Ubuntuの新規導入では `docker` コマンドの先頭に `sudo` を付けます。

```sh
mkdir -p tests/reports
sudo docker compose -f tests/compose.yaml run --build --rm test
test_result=$?
printf '模擬テストの終了コード: %s\n' "$test_result"
```

模擬テスト中の外部通信は無効です。初回のイメージ取得など、構築には接続が必要です。

結果は `tests/reports` に保存され、成功時は次の7種類の結果を表示して終了します。

- `ALL TESTS PASSED (37 checks)`
- `ALL DIAGNOSTIC TESTS PASSED (20 checks)`
- `ALL SPLIT CONFIG TESTS PASSED (10 checks)`
- `ALL LINUX TESTS PASSED (8 checks)`
- `ALL HEALTHCHECK TESTS PASSED (11 checks)`
- `ALL LINUX HEALTHCHECK TESTS PASSED (7 checks)`
- `ALL PROGRAM LAYOUT TESTS PASSED`

終了コード0と、7種類すべての最後の結果を確認してください。同じ成功表示が複数回出ても正常です。
実行中はログをファイルへためているため、しばらく表示が増えない場合があります。入力待ちへ戻るまで待ちます。`tests/reports/result.txt` の `ALL TESTS PASSED` も成功の目印です。構築エラー時に古いレポートが残っている場合があるため、今回の端末表示とファイルの更新日時も確認します。

LinuxのDockerホストでは、設定の置き換え4項目とDockerの健康状態遷移3項目も追加で実行できます。

```sh
sudo sh tests/test-config-reload.sh
test_result=$?
printf '追加テストの終了コード: %s\n' "$test_result"
```

終了コード0で、成功時は `ALL CONFIG RELOAD TESTS PASSED (4 checks)` と `ALL DOCKER HEALTHCHECK TESTS PASSED (3 checks)` を表示します。実アカウントは使用しません。ヘルスチェックの待機・検査間隔を短縮し、期限切れも模擬的に作る試験です。

### Synology Container Manager

ここでは、模擬テスト用のプロジェクト名を **`mydns-updater-test`** に統一します。
本番用の `mydns-updater` とは別に作ります。実アカウントの設定は不要です。

#### 1. PCでZIPを取得し、NASへ配置する

1. [mainのZIP](https://github.com/Karoeba/mydns-updater/archive/refs/heads/main.zip)をPCへダウンロードして展開します。
2. 展開したフォルダーを開き、update.shがある階層まで進みます。update.sh・Dockerfile・lib・testsなどが入っています。
3. File Stationで共有フォルダー `docker` を開き、その中に `mydns-recovery-check` フォルダーを作ります。
4. 展開したフォルダーの**中身をすべて**、`docker/mydns-recovery-check` へアップロードします。
5. NAS上の `mydns-recovery-check/tests` を開き、`reports` フォルダーがなければ作ります。

この試験用一式は、後で自動復帰の模擬試験にも使います。
同じ版をこの場所へ配置済みなら、再アップロードせず次の配置を確認します。
以下は一部を抜粋した図です。図にないファイルも含め、一式を配置してください。

```text
docker/
├── mydns-updater/                 ← 本番用。今回のアップロード先ではない
└── mydns-recovery-check/          ← ZIPの中身を置く場所
    ├── Dockerfile
    ├── compose.yaml              ← 今回のプロジェクトでは選ばない
    ├── update.sh
    ├── lib/                      ← 6つの.shファイル
    ├── docker-health-recover.sh
    └── tests/                    ← 今回のプロジェクトのパス
        ├── compose.yaml          ← 今回使うYAML
        ├── entrypoint.sh
        ├── その他のテスト用ファイル
        └── reports/              ← 結果の保存先
```

**配置の確認：** mydns-recovery-checkを開くと、すぐにupdate.shとtestsが見える状態です。
その間にZIPの展開フォルダーがもう1段入っていたら、中身を1段上へ移します。

#### 2. Container Managerでテスト用プロジェクトを作る

1. Container Manager →「プロジェクト」→「作成」を開きます。
2. 次の値を指定します。

| 項目 | 指定する内容 |
| --- | --- |
| プロジェクト名 | `mydns-updater-test` |
| パス | `/docker/mydns-recovery-check/tests` |
| 使用するYAML | そのフォルダー内の `compose.yaml` |

3. 配置済みのYAMLを使い、画面の案内に従って構築・開始します。
4. 作成した `mydns-updater-test` のコンテナのログを開き、テストが終了するまで待ちます。

同名のテスト用プロジェクトがすでにある場合は、そのパスが上記と一致するか確認します。
一致する場合は新規作成せず、そのテスト用プロジェクトで構築・開始して今回の結果を確認します。
異なる場合は既存プロジェクトを上書きせず、今回の名前を `mydns-updater-test-110` にして作成します。
コンテナ名は自動で付くため、手入力する必要はありません。

#### 3. 結果を確認して導入手順へ戻る

File Stationで `docker/mydns-recovery-check/tests/reports` を開きます。
以下のresult.txtとtest.logは、このフォルダー内のファイルです。

**成功：** テスト用コンテナが終了コード0で停止し、reports/result.txtにALL TESTS PASSED、
今回のtest.logに上記7種類の成功表示があれば成功です。更新日時も今回の時刻になっていることを確認します。
このコンテナが終了するのは正常で、運用コンテナのように動かし続けるものではありません。

**失敗：** 終了コード0以外、TESTS FAILED、構築エラー、今回の記録がない場合は先へ進みません。
コンテナのログとreports/test.logを確認します。古い成功記録だけで判断しません。

成功時の表示は上記のDockerテストと同じです。ホスト側の4＋3項目はこの操作では実行されません。設定の上書き反映とContainer Managerでの健康状態の変化は、別途確認します。

成功したら、[Synology導入手順の「3. 実アカウントの設定を用意する」](synology.md#3-実アカウントの設定を用意する)へ戻ります。
既存環境を更新するために試した場合は、[更新手順](synology.md#更新する場合)へ進みます。

### Linux直接実行

展開したフォルダーの直下で実行します。

```sh
sh tests/test-program-layout.sh &&
sh tests/test-linux.sh &&
sh tests/test-healthcheck-linux.sh &&
sh tests/test-health-monitor.sh &&
sh tests/test-health-recovery.sh
test_result=$?
printf '模擬テストの終了コード: %s\n' "$test_result"
```

`ALL PROGRAM LAYOUT TESTS PASSED`、`ALL LINUX TESTS PASSED (8 checks)` と `ALL LINUX HEALTHCHECK TESTS PASSED (7 checks)`、`ALL MONITOR TESTS PASSED (13 checks)` に加え、`ALL RECOVERY TESTS PASSED (16 checks)` がすべて出て、終了コード0なら成功です。一時ディレクトリ内で模擬通信を使用し、実アカウントや既存設定には触れません。

必要なソフトの準備は [Linux導入手順](linux.md) を参照してください。監視テストにはutil-linuxのflockとcoreutilsのtimeoutを使います。

`tests/test-monitor-systemd.sh` と `tests/test-recovery-systemd.sh` は使い捨てのGitHub Actions環境専用です。導入先で実行せず、タイマーの確認にはLinux導入手順を使用してください。

## 導入先で実際の動作を確認する

模擬テストの成功後、通常の運用環境に設定ファイルを配置して起動します。同じ実アカウントを複数の環境で同時に動かさないでください。

[Synology](synology.md)・[通常のDocker](docker.md)・[Linux直接実行](linux.md)から自分の環境を選び、次を確認します。

1. 起動ログに使用中のバージョンが表示される。
2. 各アカウントの通知が成功し、状態ファイルが生成される。
3. 設定ファイルを上書きすると、再起動せずに次の確認周期で反映される。
4. 再起動後も成功状態を引き継ぎ、IP不変・更新期限前なら通知をスキップする。
5. 定期更新の期限を過ぎた確認周期で、各アカウントの通知が成功する。
6. Dockerでは健康状態が `healthy`、Linuxでは導入手順の確認コマンドが `HEALTHY` になる。

`DEBUG=1` にすると確認周期とスキップ理由も表示されます。Linuxではサービスの常駐動作と、必要に応じてOS再起動後の自動起動も確認してください。

UbuntuのDockerコマンドラインで導入から試す場合は [Dockerの動作確認手順](docker-testing.md) を参照してください。Dockerの導入準備、実アカウントの切り替え、通常設定での異常・復旧と記録方法を説明しています。

Linuxでの異常・復旧、停止連動、OS再起動、結果保存は [Linuxの動作確認手順](linux-testing.md) を参照してください。

### v1.10.0の確認範囲

コード分割後のDocker・Linux直接実行の模擬テストと、Docker 24.0.2を含む自動復帰試験はGitHub Actionsで実行します。
v1.10.0の導入先での確認結果は次のとおりです。OSの版は利用者申告で、細かな版番号は照合していません。

| 環境 | 確認結果と記録 |
| --- | --- |
| DS1522+のVM・Ubuntu 24／26でLinux直接実行 | 2026年9月24日、両環境の記録を確認。実アカウント1件の通知成功、定期IP取得、再起動後の状態引き継ぎ、一時停止からの自動復帰を確認 |
| DS1522+・Container Manager（Docker 24.0.2、amd64） | 2026年9月25日、組み合わせ試験の全項目成功と、実働コンテナの自動復帰・正常状態・復帰後の定期処理を記録で確認 |
| Ubuntu 26.04系VMのDocker | 導入・自動復帰を含む試験完了の利用者報告あり。最終ログは未照合 |
| ARM環境 | 未検証 |

Linux直接実行では、両環境ともコミット `0cb7a18dcd9418cc6afc4d5d255417fd5043176d` のv1.10.0を使用しています。
PROGRESS_OVERDUEによる復帰要求からRECOVEREDまで記録され、復帰後も通知成功の状態を保持しています。
OS再起動後の確認は、手順の実施報告と再起動後として保存された起動ログ・タイマー一覧を合わせて確認しました。
提出された記録には、1時間ごとの通知成功や回数上限に達する試験は含まれていません。

Synologyでは、試験専用コンテナの `ALL DOCKER RECOVERY INTEGRATION TESTS PASSED` を確認しました。
実働コンテナは日本時間01:23:02に復帰を要求し、01:24:02にRECOVEREDを記録しています。
前後でコンテナIDは同じ、開始時刻が変わり、再起動回数は0から1へ増加しました。
v1.10.0の起動後に2アカウントの状態を引き継ぎ、次の周期でもIP取得とSKIPが続き、保存時の健康状態はhealthy・連続失敗0です。
DSMの定期実行で試したことは利用者報告に基づき、復帰の結果は提出ログで照合しています。
この保存範囲にはMyDNS.JPへの通知成功ログは含まれず、取得コミットの記録もありません。稼働版は起動ログで確認しています。

回数制限などの詳細な条件は自動テストで確認し、導入先で上限まで繰り返したとは扱いません。
下記の旧版の確認結果とは分けて扱います。

導入先では、使う環境の更新手順でlibの配置・バージョン・正常表示を確かめます。
続いて通知期限後の成功、設定変更の反映、停止・再開を確認します。
自動復帰を有効にしている場合だけ、環境別の手順で一時停止からの自動復帰と手動停止を1回ずつ確認します。
複数環境で同じアカウントを同時に動かさず、先の環境を停止してから次へ移ります。

### 作者による確認状況

v1.3.0はDS1522+で37項目の既存テスト・20項目の診断テストと、本環境で2アカウントの定期更新を確認済みです。v1.4.0の設定分割もDS1522+で37+20+10項目の模擬テストが成功しています。

v1.7.0はDS1522+上のUbuntu Server 24.04 LTS（x86-64 VM）で、実アカウント2件の更新、定期通知、設定再読み込み、OS再起動後の自動起動・状態引き継ぎを確認しました。監視の一時停止によるUNHEALTHYと再開後のRECOVEREDは画面で確認済みです。ARM機は未検証です。

Ubuntu VM上のDockerでは、実アカウントの更新と、一時停止によるunhealthy・再開によるhealthyへの復帰を確認しました。停止前後の記録では、コンテナの作り直しや再起動が発生していないことも確認しています。

DS1522+のContainer Managerでも、一時停止による `UNHEALTHY: updater progress overdue` と、再開後の「正常」表示を確認しました。

v1.8.0の自動復帰は、CIでは模擬応答による条件・制限の検査と、systemdで実際に停止した試験用サービスを再起動する検査を行います。2026年9月18日、DS1522+上のUbuntu VMで [Linux自動復帰の動作確認](linux-recovery.md#4-動作を試す) を実施し、提示された画面で次を確認しました。

- v1.8.0の起動、実アカウント2件の通知成功、手動ヘルスチェックのHEALTHY。
- STOPによる処理停止後、PROGRESS_OVERDUEを理由とするRESTART_ATTEMPT（1/3）とRESTART_REQUESTEDを記録。
- 自動再起動後に起動番号が変わり、RECOVEREDとHEALTHYを確認。
- 再起動後も成功状態を保持し、両アカウントをSKIP。60秒ごとのIP確認と自動復帰タイマーの継続を確認。
- 手動停止後、更新サービスと自動復帰タイマーがともにinactive。時間を置いた再確認でも停止を維持。

10分の再試行間隔・直近1時間の3回制限・制限解除は自動テストで確認しており、今回のVM試験では実施していません。v1.8.0でのOS再起動後の確認とARM機の動作も未検証です。


### v1.9.0：Dockerの自動復帰

2026年9月22日、DS1522+のContainer Manager（Docker 24.0.2）で、利用者から提示された画面により次を確認しました。

- DSMの毎分実行によって監視記録が更新され、通常時の状態が正常であること。
- 実働コンテナの処理を一時停止後、13:05:04（日本時間）にPROGRESS_OVERDUEによるRESTART_ATTEMPT（1/3）とRESTART_REQUESTEDを記録。
- 13:06:03にRECOVEREDを記録し、コンテナがrunning healthyへ戻ったこと。
- 再起動回数は1、監視状態はconsecutive=0 pending=0 blocked=0。
- v1.9.0の起動後、13:10にもIP確認が続き、両アカウントがIP不変・期限前としてSKIPされたこと。

これはDSMの定期実行を含む1回の復帰確認です。実働コンテナで回数上限までの試験は行っていません。
Ubuntu VMに新しくDocker環境を用意し、v1.9.0の試験をすべて問題なく完了したとの利用者報告を受けています。systemdによる定期監視・自動復帰を含む手順の実施報告です。
今回は記録ファイル・画面の提供はなく、個々のログや時刻の照合は行っていません。上記のSynologyの画面確認、およびGitHub Actionsの検証とは証拠の種類を分けて記載しています。
