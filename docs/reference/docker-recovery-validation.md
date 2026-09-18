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

## NASで確認できた環境

利用者のDS1522+で、Docker Engine 24.0.2、API 1.43、linux/amd64を確認した。
SSHからsudoで実行した場合、次のコマンドが見つかった。

| コマンド | パス |
| --- | --- |
| docker | /usr/local/bin/docker |
| sh | /bin/sh |
| timeout | /bin/timeout |
| flock | /bin/flock |
| date | /bin/date |
| awk | /bin/awk |

これは存在の確認。各オプションの対応とDSMタスク実行時の環境は未確認。

## 追加の方式検証

停止済みのコンテナを起動しないよう、docker execで内部のPID 1にTERMとCONTを送り、
終了後の再起動をunless-stoppedに任せる方式を試験する。
更新スクリプトはTERMを受けると終了する処理を既に持つ。

tests/test-docker-cooperative-recovery.shは試験用の小さな処理を使う。
実際のupdate.shの待機中の終了も確認する。
回数制限、DSMスケジューラへの組み込みはまだ行っていない。
試験対象はランナーのDockerと、使い捨て環境内に起動したDocker 24.0.2。
後者はSynology独自ビルドやNAS実機そのものの試験ではない。

- 内部からの終了依頼で再起動できるか。
- 古い起動時の依頼を拒否できるか。
- 手動停止後の依頼で起動しないか。
- 依頼を受け付けた直後に手動停止しても停止を維持するか。
- DockerのSTOP操作が再起動ポリシーに与える影響。
- Dockerを経由せずプロセスを一時停止した場合の復帰。

### 一時停止テストについて

Docker 24.0.2のkill処理は、STOP信号でも手動停止の記録を書き込む。
そのため、以前のヘルスチェック検証で使ったdocker kill --signal STOPを、
今回の自動復帰の正常系テストにそのまま使うことはできない。
本番コンテナに別の停止コマンドを試す前に、隔離した試験環境で手順を確定する。

- [Docker 24.0.2のkill処理](https://github.com/moby/moby/blob/v24.0.2/daemon/kill.go)
- [動作中のコンテナ内でコマンドを実行する機能](https://docs.docker.com/reference/cli/docker/container/exec/)

## 待機中の終了について

元のupdate.shでは、300秒の待機中にTERMを送っても、待機が終わるまで終了しなかった。
このため、待機を子プロセスで行い、終了依頼を受けたらその子プロセスも終了・回収するよう修正した。
IP確認の間隔や更新の判断は変更しない。

Dockerの試験では実際のupdate.shが短時間で終了して再起動すること、
Linuxの試験ではTERMによる終了後に待機用の子プロセスとヘルスチェック記録が残らないことを確認する。
自動復帰はまだ有効にならない。

NASで方式を試す場合は、[専用コンテナでの確認手順](synology-recovery-probe.md)を使う。
