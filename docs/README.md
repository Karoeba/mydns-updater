# ドキュメント一覧

## 開発中の試験を始める

**[新規導入からの試験コース](test-start.md)を開いてください。**
Docker・Synology・Linuxと、監視のみ・自動復帰を最初に選びます。
取得と模擬試験から、実アカウントでの確認、記録・終了まで番号順に進めます。

## 通常導入の環境を選ぶ

入口は次の3つです。NAS上のUbuntu VMでDockerを使う場合は「通常のDocker」を選びます。

| 環境 | 導入・運用 | 自動復帰を使う場合 |
| --- | --- | --- |
| Synology Container Manager | [Synologyの手順](synology.md) | [DSMの設定と確認](synology-recovery.md) |
| 通常のDocker・Compose | [Dockerの手順](docker.md) | [systemdの設定と確認](docker-systemd-recovery.md) |
| Linuxで直接実行（Dockerなし） | [Linuxの手順](linux.md) | [Linux直接実行の自動復帰](linux-recovery.md) |

- [取得する版の確認](current-version.md)：試験ブランチを取得し、設定・状態・復帰履歴を保持して同じ版を起動するための共通確認。
- [イメージ格納方式への移行](image-migration.md)：Docker・Synologyの再構築、起動確認、問題時の切り戻し。

## 更新・移行は既存利用者向け

開発中の新規導入試験では更新・移行の手順は使いません。
既存の設定・state・復帰履歴を保持して更新する場合だけ、上の移行資料を使います。

## 共通の説明と動作確認

設定一覧・更新間隔・アカウント・通常ログの説明は[README](../README.md#設定ファイル)へまとめています。
Dockerの自動復帰の条件・回数制限・ログの意味は[共通の仕組み](docker-recovery.md)を参照してください。

| 資料 | 内容 |
| --- | --- |
| [開発向け：コードの構成](development.md) | 各ファイルの役割、依存関係、変更時の確認 |
| [テストの説明](testing.md) | GitHub Actions、手元の模擬テスト、実機確認の違いと確認済みの範囲 |
| [Dockerの動作確認](docker-testing.md) | UbuntuのDockerで実通知・設定変更を確認。その後は選んだコースの専用ページへ |
| [Linuxの動作確認](linux-testing.md) | Dockerを使わず実通知・設定変更を確認。その後は選んだコースの専用ページへ |
| [参考：UbuntuへのDocker導入](reference/ubuntu-docker.md) | Docker EngineとComposeの準備 |
| [参考：DS1522+のUbuntu VM構築](reference/synology-vm.md) | 試験用Ubuntuを用意する構成例 |

自動復帰の最終確認と記録の見方は、各環境の自動復帰手順に含めています。
[変更履歴](../CHANGELOG.md)と[ライセンス](../LICENSE)はルートに置いています。

## 手順の読み方

番号付きの手順は、各段階の確認が済んでから次へ進みます。
コマンドは枠の中をコピーし、ユーザー名や入力待ちの記号は付けません。

- 操作する端末がNAS、Ubuntu、Windowsのどれかを確かめます。
- ファイルを配置したら、場所とファイル名を確認してから次へ進みます。
- 「困ったときだけ」「必要な場合だけ」は、条件に当てはまる場合だけ開きます。
- 継続運用と試験終了などの選択肢は、どちらか一方です。
- エラーが出たら、その手順番号と表示を控え、原因を確認してから続けます。

何も表示されないだけで失敗とは限りません。保存はファイルの中身、定期実行は実行記録で確認します。
「次回の予定」「実際に実行した記録」「正常な結果」は、それぞれ分けて判断してください。

## 開発時のレビュー記録

- [v1.10.0独立レビューへの対応](reference/review-4522c80.md)：指摘の判断、修正内容、既存利用への影響と検証範囲。
