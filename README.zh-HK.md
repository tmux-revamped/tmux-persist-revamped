<div align="center">

# tmux-persist-revamped

<strong>儲存 tmux 的所有工作階段、視窗及窗格，按計時器自動儲存，並在重新開機後全部還原。</strong>

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-Hans.md) | 繁體中文（香港）

[![Tests](https://github.com/tmux-revamped/tmux-persist-revamped/actions/workflows/tests.yml/badge.svg)](https://github.com/tmux-revamped/tmux-persist-revamped/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.4.0-blue.svg)](CHANGELOG.md)

<p align="center">
  <a href="#what-it-does">功能</a> |
  <a href="#installation">安裝</a> |
  <a href="#usage">用法</a> |
  <a href="#configuration">設定</a> |
  <a href="#key-bindings">按鍵綁定</a> |
  <a href="#how-it-works">運作原理</a>
</p>

</div>

**每 15 分鐘自動儲存一次。每個槽位保留最近 5 次儲存。無需設定即可重新啟動 20 種程式。已在 macOS 及 Linux 上測試。**

---

<a id="what-it-does"></a>

## 功能

儲存時會記錄伺服器上的每個工作階段、視窗及窗格：視窗名稱、索引、版面配置及縮放狀態，目前的視窗及窗格，每個窗格的工作目錄，以及其中執行的程式。還原時會重建這個結構，讓每個 shell 窗格回到原本的目錄，並重新啟動重啟清單中的程式。

同一個插件亦會按計時器自動儲存、保留儲存紀錄、把整個環境存入命名槽位，並可安裝登入代理，讓 tmux 伺服器及已還原的環境在開啟第一個終端機之前已經就緒。

## 系統要求

| 項目 | 版本或說明 |
|:------------|:----------------|
| tmux | 3.2 或以上 |
| bash | 3.2 或以上，因此 macOS 內置的 `/bin/bash` 可以使用 |
| 作業系統 | Apple Silicon 及 Intel 上的 macOS，x86_64 及 arm64 上的 Linux |
| 核心工具 | BSD、GNU 或 uutils coreutils |
| `fzf` | 選用，用於槽位選擇器 |
| `launchctl` 或 `systemctl --user` | 選用，用於 macOS 或 Linux 上的登入代理 |

<a id="installation"></a>

## 安裝

使用 [TPM](https://github.com/tmux-plugins/tpm) 時，把插件加入 `~/.tmux.conf`，然後按 `prefix + I`：

```tmux
set -g @plugin 'tmux-revamped/tmux-persist-revamped'
```

不使用 TPM 時，複製儲存庫，並在 `~/.tmux.conf` 中執行入口腳本：

```sh
git clone https://github.com/tmux-revamped/tmux-persist-revamped ~/.tmux/plugins/tmux-persist-revamped
```

```tmux
run-shell ~/.tmux/plugins/tmux-persist-revamped/persist-revamped.tmux
```

<a id="usage"></a>

## 用法

按 `prefix + C-s` 儲存，按 `prefix + C-r` 還原最近一次儲存。插件載入後自動儲存即開始運作。

在伺服器啟動時還原並更頻密地儲存：

```tmux
set -g @persist_revamped_restore_on_start 'on'
set -g @persist_revamped_interval '5'
set -g @persist_revamped_processes 'lazygit k9s'
```

每個操作亦是一個指令。以 `bash ~/.tmux/plugins/tmux-persist-revamped/src/persist.sh <command>` 執行，或綁定到按鍵。

| 指令 | 作用 |
|:--------|:-------|
| `save [slot]` | 立即儲存，指定槽位名稱時儲存到該槽位 |
| `restore [slot]` | 還原最近一次儲存，或還原指定槽位 |
| `merge <session> [slot]` | 只還原一個工作階段，而且只在沒有同名工作階段時還原 |
| `slots` | 列出命名槽位 |
| `pick` | 用 fzf 選擇一個命名槽位並還原 |
| `preview [slot]` | 顯示儲存的路徑、結構版本、來源主目錄，以及視窗及窗格數目 |
| `verify [slot]` | 檢查結構標頭、紀錄數目及儲存的時長 |
| `doctor` | 報告儲存目錄、找到的工具、停止檔案及登入代理 |
| `event` | 供關閉鈎子使用，每個防抖週期最多儲存一次 |
| `boot-install` | 寫入並載入登入代理 |
| `boot-uninstall` | 卸載並刪除登入代理 |
| `boot-sync` | 按 `@persist_revamped_boot` 安裝或移除登入代理 |

<a id="configuration"></a>

## 設定

在插件載入之前於 `~/.tmux.conf` 中設定選項。

| 選項 | 預設值 | 含義 |
|:-------|:--------|:--------|
| `@persist_revamped_interval` | `15` | 自動儲存的間隔，以分鐘計。`0` 關閉自動儲存 |
| `@persist_revamped_dir` | `$XDG_STATE_HOME/tmux/persist` | 儲存目錄。未設定 `XDG_STATE_HOME` 時為 `~/.local/state/tmux/persist`。會展開開頭的 `~`，以及 `$HOME` 和 `$HOSTNAME` |
| `@persist_revamped_scope_socket` | `on` | 為預設 socket 以外的每個伺服器分配獨立的儲存目錄 |
| `@persist_revamped_processes` | 空 | 額外要重新啟動的程式，加到內置清單之後。每一項都是 shell glob |
| `@persist_revamped_capture_panes` | `off` | `on` 時儲存每個窗格的可見文字，並在還原時重繪，末尾的空行會被刪去 |
| `@persist_revamped_capture_args` | `off` | `on` 時儲存每個程式的完整指令行，例如 `vim src/app.ts`，並照樣重新執行。含有 shell 元字元或引號的指令行只按程式名稱重新啟動 |
| `@persist_revamped_redact` | 空 | 額外的、絕不擷取其窗格文字的程式，加到 `ssh sudo su vault gpg pass op ssh-add openssl` 之後 |
| `@persist_revamped_restore_on_start` | `off` | `on` 時在伺服器啟動時還原最近一次儲存 |
| `@persist_revamped_halt_file` | `<save dir>/no-restore` | 此檔案存在期間，略過啟動時還原 |
| `@persist_revamped_boot` | `off` | `on` 時安裝登入代理，在登入時啟動 tmux 伺服器 |
| `@persist_revamped_boot_command` | `new-session -d` | 登入代理傳給 tmux 的參數 |
| `@persist_revamped_boot_label` | `tmux-persist-revamped` | launchd 標籤或 systemd 單元名稱 |
| `@persist_revamped_boot_grace` | `60` | 啟動時還原之後不進行自動儲存及事件儲存的秒數 |
| `@persist_revamped_backups` | `5` | 每個槽位紀錄中保留的儲存數目，包括目前這一次。最少為 `1` |
| `@persist_revamped_event_debounce` | `0` | 秒數。大於 `0` 時，關閉工作階段或視窗會觸發儲存，每個週期最多一次 |
| `@persist_revamped_stale_secs` | `0` | `verify` 會就超過此秒數的儲存發出警告。`0` 關閉此檢查 |
| `@persist_revamped_vim_sessions` | `off` | `on` 時，如窗格目錄中有 `Session.vim`，就用 `-S` 重新開啟 vim、nvim、vi、gvim 或 mvim |
| `@persist_revamped_rewrite_home` | `off` | `on` 時，還原時把儲存中記錄的主目錄改寫為目前的主目錄，適用於在電腦之間搬移的儲存 |
| `@persist_revamped_save_key` | `C-s` | 用於儲存的前綴鍵 |
| `@persist_revamped_restore_key` | `C-r` | 用於還原的前綴鍵 |
| `@persist_revamped_pick_key` | 空 | 在彈出視窗中開啟槽位選擇器的前綴鍵。設定之前不綁定 |
| `@persist_revamped_pre_save_hook` | 空 | 每次儲存之前執行的 shell 指令 |
| `@persist_revamped_post_save_hook` | 空 | 每次儲存成功之後執行的 shell 指令 |
| `@persist_revamped_pre_restore_hook` | 空 | 每次還原之前執行的 shell 指令 |
| `@persist_revamped_post_restore_hook` | 空 | 每次還原之後執行的 shell 指令 |

內置的重啟清單是 `vi vim nvim emacs nano man less more tail top htop btop watch ssh mosh irssi weechat mutt claude codex`。執行其他程式的窗格會以 shell 的形式回到正確的目錄。

### 內部狀態

以下選項由插件自行管理，請勿設定。

| 選項 | 內容 |
|:-------|:------|
| `@persist_revamped_booted` | 啟動時還原已執行或被停止檔案略過後為 `1`，令重新載入設定時不會再次還原 |
| `@persist_revamped_boot_ts` | 啟動時還原完成時的紀元秒，即寬限期的起點 |
| `@persist_revamped_last_ts` | 最近一次成功自動儲存的紀元秒 |
| `@persist_revamped_event_ts` | 最近一次事件儲存的紀元秒 |
| `@persist_revamped_worker_pid` | 自動儲存工作進程的進程 ID，重新載入時據此停止舊進程 |

<a id="key-bindings"></a>

## 按鍵綁定

| 按鍵 | 作用 | 選項 |
|:----|:-------|:-------|
| `prefix + C-s` | 儲存 | `@persist_revamped_save_key` |
| `prefix + C-r` | 還原最近一次儲存 | `@persist_revamped_restore_key` |
| 未綁定 | 在彈出視窗中選擇命名槽位 | `@persist_revamped_pick_key` |

`C-s` 和 `C-r` 是 tmux-revamped 家族分配給本插件的按鍵。使用 `C-` 是為了不放開修飾鍵也能儲存及還原。

<a id="how-it-works"></a>

## 運作原理

**儲存。** 儲存時用 `list-windows -a` 和 `list-panes -a` 讀取伺服器，為每個視窗及窗格寫入一條轉義後的紀錄到暫存檔，再把完成的檔案以帶時間戳記的名稱移入 `history/`。槽位路徑 `last.txt` 或 `slots/<name>.txt` 是指向最新檔案的符號連結。中斷的儲存不會留下不完整的檔案。

**紀錄。** 與上一次相同的儲存會被捨棄，因此閒置的電腦不會塞滿紀錄。超出 `@persist_revamped_backups` 的舊檔案會被刪除。回復舊狀態只需把符號連結指向較舊的檔案。

**安全。** 含有視窗的儲存絕不會被不含視窗的儲存取代。伺服器在啟動期間以及關閉最後一個工作階段期間沒有任何工作階段，此時的儲存會抹去整個環境。同一時間只會執行一次儲存，由一個鎖定目錄保護，被強制終止的儲存佔用該鎖不會超過兩分鐘。

**還原。** 還原時重新建立每個工作階段，並把每個視窗放回儲存時的索引。如該索引已被佔用，視窗會放到一個空閒的索引。每個執行 shell 的窗格會收到一條回到其目錄的 `cd`，重啟清單中的程式會再次啟動。版面配置、目前視窗、目前窗格及縮放最後套用。

**自動儲存。** 只要間隔不是 `0`，載入插件時就會為每個伺服器啟動一個背景工作進程。它每 60 秒喚醒一次，間隔已到就儲存。它從不寫入 `status-right`。伺服器不再回應或被較新的工作進程接手時，它便結束。

**多個伺服器。** 一部電腦上的所有 tmux 伺服器都讀取同一個 `~/.tmux.conf`。只有預設 socket `${TMUX_TMPDIR:-/tmp}/tmux-<uid>/default` 會儲存到儲存目錄的頂層。以 `-L name` 啟動的伺服器儲存到 `servers/name/`，以 `-S path` 啟動的伺服器儲存到以該路徑命名的目錄。

**登入代理。** 啟用 `@persist_revamped_boot` 後，插件在 macOS 上把 launchd 代理寫入 `~/Library/LaunchAgents/`，在 Linux 上把 systemd 用戶單元寫入 `~/.config/systemd/user/`。它在登入時啟動 tmux 伺服器，因此啟動時還原會在開啟任何終端機之前完成。伺服器結束後，代理不會重新啟動它。

**停止檔案。** 如還原帶回了出問題的狀態，請建立停止檔案，再啟動一個乾淨的伺服器。在刪除該檔案之前，啟動時還原會一直關閉。把 `@persist_revamped_halt_file` 指向 `/tmp` 時，由於 Linux 在開機時清空 `/tmp`，停止只會維持到下次開機。

工作階段群組不會被重建。分組的工作階段會作為擁有自己視窗的獨立工作階段還原。

## 開發

| 指令 | 作用 |
|:--------|:-------------|
| `make test` | 執行 bats 測試套件 |
| `make lint` | 對所有 shell 檔案執行 shellcheck |
| `make coverage` | 用 kcov 量度行覆蓋率，低於 95% 時失敗，在 Linux 上執行 |

測試套件需要 `bats-core` 及 tmux。

## 授權條款

[MIT](LICENSE)

<!-- family:begin -->

## tmux-revamped 插件家族

本插件是 tmux-revamped 插件家族的成員。每個成員都帶有 [`FAMILY.md`](FAMILY.md) 中的同一份約定、`family/` 下的同一套工具和同一個共用程式庫，並由校驗和清單確保逐位元組一致。這些成員可以一併安裝：任何成員都不會佔用其他成員使用的按鍵或 tmux 選項。

在一個成員中發現的缺陷，要在全部成員中排查後才算修正完成。這項責任寫在約定之中，而不是依靠記憶，`family/bin/sweep` 負責執行。

| 成員 | 功能 |
|---|---|
| [`tmux-autoreload-revamped`](https://github.com/tmux-revamped/tmux-autoreload-revamped) | 編輯並儲存 tmux 設定後，它會自動重新載入，毋須按鍵，也毋須指令 |
| [`tmux-battery-revamped`](https://github.com/tmux-revamped/tmux-battery-revamped) | 在 tmux 狀態列顯示電池狀態，從不阻塞狀態列繪製 |
| [`tmux-bluetooth-revamped`](https://github.com/tmux-revamped/tmux-bluetooth-revamped) | 在 tmux 狀態列顯示每部已連接的藍牙裝置及其電量，不阻塞繪製 |
| [`tmux-cpu-revamped`](https://github.com/tmux-revamped/tmux-cpu-revamped) | 在 tmux 狀態列顯示 CPU 負載、溫度及頻率，從不阻塞繪製 |
| [`tmux-disk-revamped`](https://github.com/tmux-revamped/tmux-disk-revamped) | 在 tmux 狀態列顯示磁碟用量，從不阻塞狀態列繪製 |
| [`tmux-extract-revamped`](https://github.com/tmux-revamped/tmux-extract-revamped) | 用 fzf 從畫面上揀選 URL、路徑、雜湊值或任何其他字詞，並輸入到游標位置，全部以純 shell 實現 |
| [`tmux-fzf-revamped`](https://github.com/tmux-revamped/tmux-fzf-revamped) | 在彈出視窗的 fzf 選擇器中切換、關閉、重新命名或建立 tmux 工作階段、視窗和窗格 |
| [`tmux-git-revamped`](https://github.com/tmux-revamped/tmux-git-revamped) | 在 tmux 狀態列顯示當前窗格的 git 分支、改動和託管平台數目，而不會阻塞顯示 |
| [`tmux-gpu-revamped`](https://github.com/tmux-revamped/tmux-gpu-revamped) | 在 tmux 狀態列顯示 NVIDIA、AMD、Intel 及 Apple GPU 的負載、溫度、時脈、功耗及記憶體 |
| [`tmux-kube-revamped`](https://github.com/tmux-revamped/tmux-kube-revamped) | 在 tmux 狀態列顯示目前的 Kubernetes 上下文及命名空間，毋須 kubectl，直接解析 kubeconfig |
| [`tmux-launcher-revamped`](https://github.com/tmux-revamped/tmux-launcher-revamped) | 在彈出視窗或新視窗中啟動任何 TUI 應用程式，從目前窗格的目錄開始，每個應用程式可設定一個按鍵 |
| [`tmux-logging-revamped`](https://github.com/tmux-revamped/tmux-logging-revamped) | 將任何窗格儲存到檔案：即時記錄、完整捲動緩衝區或一次性截圖 |
| [`tmux-music-revamped`](https://github.com/tmux-revamped/tmux-music-revamped) | 在 tmux 狀態列顯示正在播放的歌曲，從不阻塞狀態列的繪製 |
| [`tmux-network-revamped`](https://github.com/tmux-revamped/tmux-network-revamped) | 在 tmux 狀態列顯示網絡傳輸量，從不阻塞繪製 |
| [`tmux-pain-control-revamped`](https://github.com/tmux-revamped/tmux-pain-control-revamped) | tmux 的窗格和視窗管理按鍵，配合 tmux 版本，與 vim 相容，每個 prefix 按鍵都可停用 |
| [`tmux-persist-revamped`](https://github.com/tmux-revamped/tmux-persist-revamped) | **本插件**，儲存 tmux 的所有工作階段、視窗及窗格，按計時器自動儲存，並在重新開機後全部還原 |
| [`tmux-plugin-template`](https://github.com/tmux-revamped/tmux-plugin-template) | tmux-revamped 插件的起點：共用程式庫、bats 測試框架、CI 和系列工具 |
| [`tmux-pomodoro-revamped`](https://github.com/tmux-revamped/tmux-pomodoro-revamped) | tmux 狀態列中的番茄鐘計時器，所有狀態都儲存在 tmux 選項中，不使用暫存檔 |
| [`tmux-ram-revamped`](https://github.com/tmux-revamped/tmux-ram-revamped) | 在 tmux 狀態列顯示記憶體、交換空間及記憶體壓力，在背景取樣，繪製從不等待 |
| [`tmux-reorder-revamped`](https://github.com/tmux-revamped/tmux-reorder-revamped) | 用滑鼠在 tmux 狀態列上拖動視窗標籤來移動該視窗 |
| [`tmux-scroll-revamped`](https://github.com/tmux-revamped/tmux-scroll-revamped) | 將滑鼠滾輪交給能自行捲動的應用程式，其他情況下進入 tmux 複製模式 |
| [`tmux-sensible-revamped`](https://github.com/tmux-revamped/tmux-sensible-revamped) | 按 tmux 版本和終端機區分的合理預設設定，不會改動你自己設定的選項 |
| [`tmux-tiling-revamped`](https://github.com/tmux-revamped/tmux-tiling-revamped) | tmux 的平鋪視窗管理：八種版面，包括 BSP dwindle 和 spiral，並支援復原版面 |
| [`tmux-time-revamped`](https://github.com/tmux-revamped/tmux-time-revamped) | 狀態列中的本地時鐘和世界時鐘，按一天中的時段著色，並提供倒數和夏令時間提示 |
| [`tmux-weather-revamped`](https://github.com/tmux-revamped/tmux-weather-revamped) | 在背景從 wttr.in 取得天氣並顯示在狀態列，狀態列毋須等待 |

### 檢查安裝

所有成員都在磁碟上時，一個指令即可報告它們之間的任何衝突：

```sh
family/bin/doctor --live
```

它讀取每個成員和正在運行的 tmux 伺服器，報告重複的按鍵、重複的狀態佔位符、不符合命名規則的選項，以及約定版本落後的成員。

<!-- family:end -->
