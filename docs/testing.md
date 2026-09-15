# テストの実行と結果の確認

GitHub ActionsはPR作成・更新時とmainへのpush時に、37項目の既存模擬テスト、20項目の診断テスト、10項目の設定分割テスト、8項目の配置先指定テストと4項目の設定再読み込みテストを実行します。Actionsの「Docker tests」から手動実行もできます。

結果はPRのChecksとActionsログ、成果物 `test-reports`（14日間保存）で確認できます。コンテナ起動前の失敗ではレポートがない場合があります。

## コマンドラインで実行する

```sh
mkdir -p tests/reports
docker compose -f tests/compose.yaml run --build --rm test
# Linux Docker host only
sh tests/test-config-reload.sh
```

模擬テストは外部通信を無効にし、実アカウントを使いません。初回のイメージ取得には接続が必要です。

結果は `tests/reports` に保存され、成功時は `ALL TESTS PASSED (37 checks)` と `ALL DIAGNOSTIC TESTS PASSED (20 checks)`、`ALL SPLIT CONFIG TESTS PASSED (10 checks)`、`ALL LINUX TESTS PASSED (8 checks)` を表示して終了します。途中の失敗ログは異常系テストに含まれるため、最後の結果を確認してください。

## Synology Container Managerで実行する

Container Managerでは、プロジェクトのパスを `tests` フォルダーにし、その中の `compose.yaml` を指定します。`tests/reports` を事前に作成し、`update.sh` は1つ上の階層に置いてください。

4項目のホスト側テストはこの操作では実行されないため、設定の上書き反映は別途確認します。

## 実機確認

v1.3.0はDS1522+で37項目の既存テスト・20項目の診断テストと、本環境で2アカウントの定期更新を確認済みです。v1.4.0の設定分割もDS1522+で37+20+10項目の模擬テストが成功しています。

GitHubのテストだけではNAS上の動作は保証されないため、導入先で起動・通信・状態保持を確認してください。テスト失敗時のマージ禁止には別途リポジトリ設定が必要です。


## 結果バッジ

README冒頭のバッジはmainブランチへのpushで実行されたワークフローの状態を表示します。開発中のPRの結果は、そのPRのChecksで確認してください。

バッジをクリックするとActionsの実行履歴を開けます。

Linux直接実行のテストは [Linux導入手順](linux.md) を参照してください。
