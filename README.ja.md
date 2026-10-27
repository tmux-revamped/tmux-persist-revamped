<div align="center">

# tmux-persist-revamped

<strong>tmuxのすべてのセッション、ウィンドウ、ペインを保存し、タイマーで自動保存して、再起動後にすべて復元します。</strong>

[English](README.md) | 日本語 | [简体中文](README.zh-Hans.md) | [繁體中文（香港）](README.zh-HK.md)

[![Tests](https://github.com/tmux-revamped/tmux-persist-revamped/actions/workflows/tests.yml/badge.svg)](https://github.com/tmux-revamped/tmux-persist-revamped/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.4.0-blue.svg)](CHANGELOG.md)

<p align="center">
  <a href="#what-it-does">概要</a> |
  <a href="#installation">インストール</a> |
  <a href="#usage">使い方</a> |
  <a href="#configuration">設定</a> |
  <a href="#key-bindings">キーバインド</a> |
  <a href="#how-it-works">仕組み</a>
</p>

</div>

**15分ごとに自動保存します。各スロットの直近5件の保存を残します。設定なしで20種類のプログラムを再起動します。macOSとLinuxでテストしています。**

---

<a id="what-it-does"></a>

## 概要

保存では、サーバー上のすべてのセッション、ウィンドウ、ペインを記録します。記録するのは、ウィンドウの名前、インデックス、レイアウト、ズーム状態、アクティブなウィンドウとペイン、各ペインの作業ディレクトリ、そこで動いているプログラムです。復元ではこの構成を組み直し、シェルのペインを元のディレクトリに戻し、再起動リストにあるプログラムをもう一度起動します。

同じプラグインがタイマーによる自動保存、保存の履歴、名前付きスロットへの環境の退避も行います。ログインエージェントを入れれば、最初の端末を開く前にtmuxサーバーと復元済みの環境が用意されます。

## 必要なもの

| 項目 | バージョンや補足 |
|:------------|:----------------|
| tmux | 3.2以降 |
| bash | 3.2以降。macOS標準の`/bin/bash`で動きます |
| OS | Apple SiliconとIntelのmacOS、x86_64とarm64のLinux |
| 基本コマンド | BSD、GNU、uutilsのいずれのcoreutilsでも動きます |
| `fzf` | 任意。スロットのピッカーに使います |
| `launchctl`または`systemctl --user` | 任意。macOSまたはLinuxのログインエージェントに使います |

<a id="installation"></a>

## インストール

[TPM](https://github.com/tmux-plugins/tpm)を使う場合は、`~/.tmux.conf`にプラグインを追加して`prefix + I`を押します。

```tmux
set -g @plugin 'tmux-revamped/tmux-persist-revamped'
```

TPMを使わない場合は、リポジトリをクローンし、`~/.tmux.conf`からエントリーポイントを実行します。

```sh
git clone https://github.com/tmux-revamped/tmux-persist-revamped ~/.tmux/plugins/tmux-persist-revamped
```

```tmux
run-shell ~/.tmux/plugins/tmux-persist-revamped/persist-revamped.tmux
```

<a id="usage"></a>

## 使い方

`prefix + C-s`で保存し、`prefix + C-r`で最後の保存を復元します。自動保存はプラグインを読み込んだ時点で有効です。

サーバーの起動時に復元し、より頻繁に保存する例です。

```tmux
set -g @persist_revamped_restore_on_start 'on'
set -g @persist_revamped_interval '5'
set -g @persist_revamped_processes 'lazygit k9s'
```

すべての操作はコマンドとしても使えます。`bash ~/.tmux/plugins/tmux-persist-revamped/src/persist.sh <command>`として実行するか、キーに割り当ててください。

| コマンド | 動作 |
|:--------|:-------|
| `save [slot]` | 今すぐ保存します。スロット名を指定するとそのスロットに保存します |
| `restore [slot]` | 最後の保存、または指定したスロットを復元します |
| `merge <session> [slot]` | 1つのセッションだけを、同じ名前のセッションがない場合に復元します |
| `slots` | 名前付きスロットを一覧表示します |
| `pick` | fzfで名前付きスロットを選んで復元します |
| `preview [slot]` | 保存のパス、スキーマ、保存元のホーム、ウィンドウとペインの数を表示します |
| `verify [slot]` | スキーマのヘッダー、レコード数、保存の古さを確認します |
| `doctor` | 保存ディレクトリ、見つかったツール、停止ファイル、ログインエージェントを報告します |
| `event` | クローズ時のフックのために、デバウンス期間ごとに1回だけ保存します |
| `boot-install` | ログインエージェントを書き出して読み込みます |
| `boot-uninstall` | ログインエージェントを解除して削除します |
| `boot-sync` | `@persist_revamped_boot`に合わせてログインエージェントを入れるか外します |

<a id="configuration"></a>

## 設定

オプションはプラグインを読み込む前に`~/.tmux.conf`で設定します。

| オプション | 既定値 | 意味 |
|:-------|:--------|:--------|
| `@persist_revamped_interval` | `15` | 自動保存の間隔、分単位です。`0`で自動保存を止めます |
| `@persist_revamped_dir` | `$XDG_STATE_HOME/tmux/persist` | 保存ディレクトリです。`XDG_STATE_HOME`が未設定なら`~/.local/state/tmux/persist`です。先頭の`~`、`$HOME`、`$HOSTNAME`を展開します |
| `@persist_revamped_scope_socket` | `on` | 既定のソケット以外のサーバーに、それぞれ専用の保存ディレクトリを割り当てます |
| `@persist_revamped_processes` | 空 | 再起動するプログラムの追加分で、組み込みのリストに加わります。各項目はシェルのglobです |
| `@persist_revamped_capture_panes` | `off` | `on`で各ペインの表示中のテキストを保存し、復元時に再描画します。末尾の空行は取り除きます |
| `@persist_revamped_capture_args` | `off` | `on`で各プログラムの完全なコマンドライン、たとえば`vim src/app.ts`を保存して再実行します。シェルのメタ文字や引用符を含む行は、プログラム名だけで再起動します |
| `@persist_revamped_redact` | 空 | ペインのテキストを決して保存しないプログラムの追加分で、`ssh sudo su vault gpg pass op ssh-add openssl`に加わります |
| `@persist_revamped_restore_on_start` | `off` | `on`でサーバーの起動時に最後の保存を復元します |
| `@persist_revamped_halt_file` | `<save dir>/no-restore` | このファイルがある間は、起動時の復元を行いません |
| `@persist_revamped_boot` | `off` | `on`でログイン時にtmuxサーバーを起動するログインエージェントを入れます |
| `@persist_revamped_boot_command` | `new-session -d` | ログインエージェントがtmuxに渡す引数です |
| `@persist_revamped_boot_label` | `tmux-persist-revamped` | launchdのラベル、またはsystemdのユニット名です |
| `@persist_revamped_boot_grace` | `60` | 起動時の復元のあと、自動保存とイベント保存を行わない秒数です |
| `@persist_revamped_backups` | `5` | 各スロットの履歴に残す保存の数で、現在の保存を含みます。最小は`1`です |
| `@persist_revamped_event_debounce` | `0` | 秒数です。`0`より大きいと、セッションやウィンドウを閉じたときに、その期間に最大1回保存します |
| `@persist_revamped_stale_secs` | `0` | `verify`はこの秒数より古い保存を警告します。`0`で確認を止めます |
| `@persist_revamped_vim_sessions` | `off` | `on`にすると、ペインのディレクトリに`Session.vim`がある場合、vim、nvim、vi、gvim、mvimを`-S`付きで開き直します |
| `@persist_revamped_rewrite_home` | `off` | `on`で、保存に記録されたホームディレクトリを復元時に現在のものへ書き換えます。別のマシンへ移した保存に使います |
| `@persist_revamped_save_key` | `C-s` | 保存するプレフィックスキーです |
| `@persist_revamped_restore_key` | `C-r` | 復元するプレフィックスキーです |
| `@persist_revamped_pick_key` | 空 | スロットのピッカーをポップアップで開くプレフィックスキーです。設定するまで割り当てません |
| `@persist_revamped_pre_save_hook` | 空 | 各保存の前に実行するシェルコマンドです |
| `@persist_revamped_post_save_hook` | 空 | 保存に成功するたびに実行するシェルコマンドです |
| `@persist_revamped_pre_restore_hook` | 空 | 各復元の前に実行するシェルコマンドです |
| `@persist_revamped_post_restore_hook` | 空 | 各復元の後に実行するシェルコマンドです |

組み込みの再起動リストは`vi vim nvim emacs nano man less more tail top htop btop watch ssh mosh irssi weechat mutt claude codex`です。それ以外を実行していたペインは、正しいディレクトリのシェルとして戻ります。

### 内部状態

以下のオプションはプラグインが自分で管理します。設定しないでください。

| オプション | 内容 |
|:-------|:------|
| `@persist_revamped_booted` | 起動時の復元が実行されるか、停止ファイルで省略されると`1`になり、設定の再読み込みで再び復元しないようにします |
| `@persist_revamped_boot_ts` | 起動時の復元が終わったエポック秒で、猶予期間の始まりです |
| `@persist_revamped_last_ts` | 最後に成功した自動保存のエポック秒です |
| `@persist_revamped_event_ts` | 最後のイベント保存のエポック秒です |
| `@persist_revamped_worker_pid` | 自動保存ワーカーのプロセスIDで、再読み込み時に古いワーカーを止めるために使います |

<a id="key-bindings"></a>

## キーバインド

| キー | 動作 | オプション |
|:----|:-------|:-------|
| `prefix + C-s` | 保存 | `@persist_revamped_save_key` |
| `prefix + C-r` | 最後の保存を復元 | `@persist_revamped_restore_key` |
| 未割り当て | 名前付きスロットをポップアップで選ぶ | `@persist_revamped_pick_key` |

`C-s`と`C-r`は、tmux-revampedファミリーがこのプラグインに割り当てたキーです。修飾キーを離さずに保存と復元ができるよう、`C-`を使っています。

<a id="how-it-works"></a>

## 仕組み

**保存。** 保存では`list-windows -a`と`list-panes -a`でサーバーを読み、ウィンドウとペインごとにエスケープしたレコードを一時ファイルへ書き、完成したファイルをタイムスタンプ付きの名前で`history/`へ移します。スロットのパス、つまり`last.txt`や`slots/<name>.txt`は、最新のファイルへのシンボリックリンクです。中断した保存が不完全なファイルを残すことはありません。

**履歴。** 直前と同じ内容の保存は捨てるため、操作のないマシンで履歴が埋まることはありません。`@persist_revamped_backups`を超えた古いファイルは削除します。巻き戻すには、シンボリックリンクを古いファイルに向け直します。

**安全性。** ウィンドウを含む保存を、ウィンドウのない保存で置き換えることはありません。サーバーは起動中と、最後のセッションを閉じる間はセッションを持たないため、そのときの保存は環境を消してしまいます。保存は一度に1つだけ実行され、ロック用のディレクトリで守られます。強制終了した保存がそのロックを2分を超えて持ち続けることはありません。

**復元。** 復元では各セッションを作り直し、すべてのウィンドウを保存されたインデックスに戻します。そのインデックスが使用中なら、空いているインデックスに置きます。シェルを実行しているペインには元のディレクトリへの`cd`を送り、再起動リストにあるプログラムをもう一度起動します。レイアウト、アクティブなウィンドウとペイン、ズームは最後に適用します。

**自動保存。** 間隔が`0`でなければ、プラグインを読み込むとサーバーごとに1つのバックグラウンドのワーカーが起動します。ワーカーは60秒ごとに起き、間隔が過ぎていれば保存します。`status-right`には書き込みません。サーバーが応答しなくなるか、新しいワーカーに引き継がれると終了します。

**複数のサーバー。** マシン上のすべてのtmuxサーバーは同じ`~/.tmux.conf`を読みます。保存ディレクトリの最上位に保存するのは、既定のソケット`${TMUX_TMPDIR:-/tmp}/tmux-<uid>/default`だけです。`-L name`で起動したサーバーは`servers/name/`に、`-S path`で起動したサーバーはそのパスから名付けたディレクトリに保存します。

**ログインエージェント。** `@persist_revamped_boot`を有効にすると、macOSでは`~/Library/LaunchAgents/`にlaunchdのエージェントを、Linuxでは`~/.config/systemd/user/`にsystemdのユーザーユニットを書き出します。これがログイン時にtmuxサーバーを起動するので、起動時の復元はどの端末を開くよりも前に実行されます。サーバーが終了しても、エージェントは再起動しません。

**停止ファイル。** 復元で壊れた状態が戻ってきたときは、停止ファイルを作ってからクリーンなサーバーを起動してください。ファイルを消すまで、起動時の復元は止まったままです。`@persist_revamped_halt_file`を`/tmp`に向けると、Linuxは起動時に`/tmp`を消すため、停止は次の起動までになります。

セッショングループは作り直しません。グループ化されたセッションは、独自のウィンドウを持つ別々のセッションとして戻ります。

## 開発

| コマンド | 内容 |
|:--------|:-------------|
| `make test` | batsのテストスイートを実行します |
| `make lint` | すべてのシェルファイルにshellcheckを実行します |
| `make coverage` | kcovで行カバレッジを測り、95パーセント未満なら失敗します。Linuxで動きます |

テストスイートには`bats-core`とtmuxが必要です。

## ライセンス

[MIT](LICENSE)

<!-- family:begin -->

## tmux-revamped ファミリー

このプラグインは tmux-revamped ファミリーの一員です。すべてのメンバーが [`FAMILY.md`](FAMILY.md) の同じ規約、`family/` 配下の同じツール、同じ共有ライブラリを持ち、チェックサムの一覧によってバイト単位で同一に保たれています。メンバーは一緒にインストールする前提で作られており、ほかのメンバーが使うキーや tmux オプションを使うメンバーはありません。

あるメンバーで見つかった不具合は、修正完了とする前に全メンバーで同じ不具合を探します。この義務は記憶に頼らず規約に書かれており、`family/bin/sweep` がその作業を行います。

| メンバー | 機能 |
|---|---|
| [`tmux-autoreload-revamped`](https://github.com/tmux-revamped/tmux-autoreload-revamped) | tmuxの設定を編集して保存するだけで、キーもコマンドも使わずに自動で再読み込みされます |
| [`tmux-battery-revamped`](https://github.com/tmux-revamped/tmux-battery-revamped) | tmuxのステータスバーに電池の状態を表示し、ステータスの描画を一切止めません |
| [`tmux-bluetooth-revamped`](https://github.com/tmux-revamped/tmux-bluetooth-revamped) | 接続中のすべてのBluetooth機器とその電池残量をtmuxのステータスバーに表示し、描画を止めません |
| [`tmux-cpu-revamped`](https://github.com/tmux-revamped/tmux-cpu-revamped) | CPUの負荷、温度、周波数をtmuxのステータスバーに表示し、描画を一切止めません |
| [`tmux-disk-revamped`](https://github.com/tmux-revamped/tmux-disk-revamped) | tmuxのステータスバーにディスク使用量を表示し、ステータスの描画を一切止めません |
| [`tmux-extract-revamped`](https://github.com/tmux-revamped/tmux-extract-revamped) | 画面上の URL、パス、ハッシュなどのトークンを fzf で選び、カーソル位置に入力します。純粋なシェルだけで動きます |
| [`tmux-fzf-revamped`](https://github.com/tmux-revamped/tmux-fzf-revamped) | ポップアップ内の fzf ピッカーから、tmux のセッション、ウィンドウ、ペインの切り替え、終了、名前変更、作成を行います |
| [`tmux-git-revamped`](https://github.com/tmux-revamped/tmux-git-revamped) | アクティブなペインのgitブランチ、変更、プロバイダーの件数を、描画を止めずにtmuxのステータスバーに表示します |
| [`tmux-gpu-revamped`](https://github.com/tmux-revamped/tmux-gpu-revamped) | NVIDIA、AMD、Intel、Apple の GPU の負荷、温度、クロック、電力、メモリを tmux のステータスバーに表示します |
| [`tmux-kube-revamped`](https://github.com/tmux-revamped/tmux-kube-revamped) | 現在の Kubernetes コンテキストと名前空間を、kubectl を使わずに kubeconfig から解析して tmux のステータスバーに表示します |
| [`tmux-launcher-revamped`](https://github.com/tmux-revamped/tmux-launcher-revamped) | 任意の TUI アプリを、現在のペインのディレクトリでポップアップまたはウィンドウとして起動します。アプリごとにキーを設定できます |
| [`tmux-logging-revamped`](https://github.com/tmux-revamped/tmux-logging-revamped) | 任意のペインをファイルに保存します。ライブのログ記録、スクロールバック全体、1 回限りのスクリーンショットに対応します |
| [`tmux-music-revamped`](https://github.com/tmux-revamped/tmux-music-revamped) | 再生中の曲をステータスバーに表示し、ステータスの描画を止めません |
| [`tmux-network-revamped`](https://github.com/tmux-revamped/tmux-network-revamped) | ネットワークのスループットをステータスバーに表示し、描画を止めません |
| [`tmux-pain-control-revamped`](https://github.com/tmux-revamped/tmux-pain-control-revamped) | tmux のペインとウィンドウの操作キー。tmux のバージョンに対応し、vim と共存でき、どの prefix キーも無効にできます |
| [`tmux-persist-revamped`](https://github.com/tmux-revamped/tmux-persist-revamped) | **このプラグイン**、tmuxのすべてのセッション、ウィンドウ、ペインを保存し、タイマーで自動保存して、再起動後にすべて復元します |
| [`tmux-plugin-template`](https://github.com/tmux-revamped/tmux-plugin-template) | tmux-revampedプラグインの出発点です。共有ライブラリ、batsハーネス、CI、ファミリーのツールを含みます |
| [`tmux-pomodoro-revamped`](https://github.com/tmux-revamped/tmux-pomodoro-revamped) | すべての状態をtmuxオプションに保持し、一時ファイルを使わない、tmuxステータスバーのポモドーロタイマーです |
| [`tmux-ram-revamped`](https://github.com/tmux-revamped/tmux-ram-revamped) | RAM、スワップ、メモリプレッシャーをtmuxのステータスバーに表示します。計測はバックグラウンドで行うため描画を待たせません |
| [`tmux-reorder-revamped`](https://github.com/tmux-revamped/tmux-reorder-revamped) | tmuxのステータスバー上でウィンドウのタブをマウスでドラッグして、そのウィンドウを移動します |
| [`tmux-scroll-revamped`](https://github.com/tmux-revamped/tmux-scroll-revamped) | 自分でスクロールできるアプリにはマウスホイールを渡し、それ以外ではtmuxのコピーモードに入ります |
| [`tmux-sensible-revamped`](https://github.com/tmux-revamped/tmux-sensible-revamped) | tmuxのバージョンと端末に合わせて適用され、ユーザーが設定したオプションには触れない、妥当な初期設定です |
| [`tmux-tiling-revamped`](https://github.com/tmux-revamped/tmux-tiling-revamped) | tmuxのタイル型ウィンドウ管理です。BSPのdwindleとspiralを含む8つのレイアウトと、レイアウトの取り消しがあります |
| [`tmux-time-revamped`](https://github.com/tmux-revamped/tmux-time-revamped) | ステータスバーにローカル時計と世界時計を時間帯ごとの色で表示し、カウントダウンと夏時間の警告も出します |
| [`tmux-weather-revamped`](https://github.com/tmux-revamped/tmux-weather-revamped) | wttr.inの天気をバックグラウンドで取得し、ステータスバーを待たせずに表示します |

### インストールの確認

全メンバーがディスク上にあれば、1 つのコマンドでメンバー間の衝突を報告できます。

```sh
family/bin/doctor --live
```

各メンバーと実行中の tmux サーバーを読み取り、重複したキー、重複したステータスのプレースホルダー、命名規則に合わないオプション、規約のバージョンが古いメンバーを報告します。

<!-- family:end -->
