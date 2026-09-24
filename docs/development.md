# コードの構成と変更時の確認

DockerとLinux直接実行は、同じPOSIX shのプログラムを使います。
対象サービスはMyDNS.JP、更新するアドレスはIPv4です。

## ファイルごとの役割

| ファイル | 役割 |
| --- | --- |
| update.sh | バージョン、配置の確認、読み込み、起動方法の選択 |
| lib/config.sh | 共通設定とアカウント設定の読み取り・検査・再読み込み |
| lib/diagnostics.sh | ログ、連続失敗、復旧、表示の抑制 |
| lib/network.sh | IPv4取得、HTTP通信、応答分類、MyDNS.JPへの通知 |
| lib/state.sh | アカウント別の成功記録の読み取り・保存 |
| lib/health.sh | 進行記録、ヘルスチェック、Docker自動復帰用の状態確認 |
| lib/runtime.sh | 初期値、終了処理、アカウントごとの更新判断、周期実行 |

各モジュールは関数の定義だけを持ち、update.shから読み込んで同じプロセスで動きます。
ファイルを分けても、プロセスや常駐サービスは増えません。
単独で `sh lib/config.sh` などを実行する使い方ではありません。

読み込み順はdiagnostics、health、config、network、state、runtimeです。
読み込みを終えてから初期値を設定し、確認用の起動か、常駐する起動かを選びます。
確認用の起動では、設定ファイルの読み込み・作業フォルダーの作成・通信を行いません。
6ファイルのどれかを読めない場合は、初期化より前にMODULE_UNAVAILABLEを表示して終了します。

## 依存関係と変更時の注意

今回は動作を維持するため、既存の共有変数と関数を引き継いでいます。
ファイルが分かれていても、互いに独立した部品ではありません。

- runtimeが他の機能を呼び出します。更新するかどうかの判断と、通知成功後の保存順序を変えないでください。
- config・network・state・healthはdiagnosticsのログ／終了処理を使います。
- stateはconfigのget_valueを、networkはconfigが用意した設定値を使います。
- REQUEST_OKなどの通信結果、WORK_DIR内の一時ファイル、アカウント別の変数は同じシェルで共有します。変数を追加するときは既存名との衝突を確認します。
- health-monitor.sh・health-recover.sh・docker-health-recover.shは外側の監視です。update.shの確認用引数を通して呼び出します。
- update.shのMYDNS_DOCKER_RECOVERY_PROTOCOLはDocker側の互換性確認に使います。起動用ファイルに残します。

## 配布と配置

update.shとlibは同じ版の一式で扱います。利用者がコードを読む必要はありません。
プログラムは実行ユーザーが読み取れ、管理者だけが変更できるように配置します。
シンボリックリンクのupdate.shだけを別の場所に置く使い方は対象にしていません。

Dockerはupdate.shとlibを読み取り専用でマウントし、Linuxは同じフォルダー内へ配置します。
Dockerイメージへのプログラム格納は今回の範囲に含めません。
更新時は実行を停止して一式を置き換え、設定・状態は維持します。
詳しい操作は[Docker](docker.md#更新する場合)・[Synology](synology.md#更新する場合)・[Linux](linux.md#更新方法)の手順を使います。

## 変更後に確認すること

[テストの説明](testing.md)に従い、DockerとLinux直接実行の両方を確認します。
GitHub Actionsでは既存の動作、自動復帰、サービス定義、文書中のシェル構文を検査します。
tests/load-library.shは内部関数の模擬試験に使い、tests/test-program-layout.shは実際の起動用ファイルを使って配置を確認します。
内部関数だけの試験が成功しても、起動・配置の試験を省略しないでください。

設定・状態・ログ・終了コード・確認用引数は、利用者や外側の監視が使う境界です。
今後これらを変更する場合は、互換性と移行手順を合わせて検討します。
