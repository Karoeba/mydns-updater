# Docker・Synologyの自動復帰：実装前の検証

この資料は開発中の検証メモです。自動復帰の導入手順ではありません。

## Linux版とそろえる条件

- 任意で有効化し、初期状態は無効。
- 進行期限超過を3回連続で検出した場合だけ対象とする。
- 再起動要求は10分以上空け、直近1時間に3回まで。要求失敗も数える。
- 上限到達後は手動解除まで停止。正常復帰で回数を消さない。
- 通信・認証・設定エラーや確認処理自体の失敗では再起動しない。
- 手動停止を取り消さない。対象の更新コンテナだけを操作する。

Dockerのhealthcheck自体に3回の失敗判定があるため、unhealthyをさらに3回数える二重判定にはしない。
同じ検査結果を繰り返し読んでも、新しい失敗回数に加算しない。

## 2つの環境の違い

| 項目 | Ubuntu上のDocker | Synology Container Manager |
| --- | --- | --- |
| コンテナ内の更新・ヘルスチェック | 同じupdate.shとCompose設定 | 同じupdate.shとCompose設定 |
| 通常の操作 | Dockerコマンド | DSMの画面、必要時にSSH |
| ホスト側の定期実行候補 | systemdタイマー | DSMタスクスケジューラ |
| ファイルの配置例 | 任意の作業フォルダー | /volume1/docker/mydns-updater |
| 追加確認 | Docker版、権限、コマンド | Container Manager版、Docker版、権限、PATH、コマンドの有無 |

共通の処理を目指すが、Ubuntuでの成功だけでNASも確認済みにはしない。
タスクの間隔や実行時の環境も異なるため、所要時間まで同じと決めつけない。

## 単純な再起動では残る問題

Dockerのrestart処理は停止中のコンテナも起動する。
「動作中か確認 → 再起動」の間に利用者が停止すると、その停止を取り消す可能性がある。
再起動直前の再確認だけでは、この間隔を完全にはなくせない。

Dockerのkill操作も、通常のプロセス異常終了と同じ扱いとは限らない。
既存のunless-stopped設定との関係を、試験用コンテナで確認する。

この点が解決するまでは、本番向けの自動復帰を有効化する手順は用意しない。
コンテナの再作成でIDが変わった場合と、起動時刻が変わった場合も追加確認が必要。

## 自動テスト

tests/test-docker-recovery-semantics.shは、使い捨てのGitHub Actions環境専用。
試験で作成したIDのコンテナだけを操作し、本物の設定やアカウントは使わない。
試験コンテナのネットワークは無効。

1. 動作中を確認した後で手動停止し、その後restartを実行すると再び起動する。
2. プロセスの通常の異常終了ではunless-stoppedにより再起動する。
3. Dockerのstop操作後は停止を維持する。
4. Dockerのkill操作が異常終了による自動再起動の代用になるか確認する。

この試験はDockerの基本動作の確認であり、自動復帰機能の完成試験ではない。
回数制限をDocker向けに組み込んだ試験、およびDS1522+実機確認は今後行う。

## 参照

- [Dockerの再起動ポリシー](https://docs.docker.com/engine/containers/start-containers-automatically/)
- [Dockerのrestart実装](https://github.com/moby/moby/blob/master/daemon/restart.go)
- [Dockerのkill実装](https://github.com/moby/moby/blob/master/daemon/kill.go)
- [Container Manager](https://www.synology.com/en-us/dsm/feature/container-manager)
- [DSMでのタスク作成](https://kb.synology.com/en-br/DSM/tutorial/common_mistake_in_task_scheduler_script)
