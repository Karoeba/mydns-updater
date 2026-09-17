# ドキュメント一覧

[プロジェクトのREADME](../README.md) はDockerとSynology Container Managerでの導入・運用を説明します。

| 資料 | 内容 |
| --- | --- |
| [Dockerの動作確認](docker-testing.md) | コマンドラインでの導入、模擬テスト、実通知、異常・復旧 |
| [Linux導入・運用](linux.md) | 準備、配置、設定、サービス起動、定期監視、更新 |
| [Linuxの自動復帰](linux-recovery.md) | 再起動条件、回数制限、導入、確認、手動解除 |
| [Linuxの動作確認](linux-testing.md) | 実通知、異常・復旧、再起動、結果の保存 |
| [テストの実行と結果](testing.md) | GitHub Actionsと手元での模擬テスト |
| [参考：UbuntuへのDocker導入](reference/ubuntu-docker.md) | Docker EngineとComposeの準備 |
| [参考：DS1522+のUbuntu VM構築](reference/synology-vm.md) | Linuxの試験環境を用意する構成例 |

[変更履歴](../CHANGELOG.md) と [ライセンス](../LICENSE) はリポジトリのルートに置いています。設定の記入例は実際にコピーして使うため、プログラムと同じ階層にあります。

## 手順の読み方

番号付きの手順は、各段階の確認が済んでから次へ進みます。
「困ったときだけ」は問題が起きた場合、「必要な場合だけ」はその操作を希望する場合に限って実行します。
継続運用と試験終了など、選択肢がある箇所はどちらか一方を選びます。すべてのコマンドを実行する必要はありません。
