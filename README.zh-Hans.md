<div align="center">

# tmux-persist-revamped

<strong>保存 tmux 的所有会话、窗口和窗格，按定时器自动保存，并在重启后全部恢复。</strong>

[English](README.md) &nbsp;|&nbsp; [日本語](README.ja.md) &nbsp;|&nbsp; 简体中文 &nbsp;|&nbsp; [繁體中文（香港）](README.zh-HK.md)

[![Tests](https://github.com/tmux-revamped/tmux-persist-revamped/actions/workflows/tests.yml/badge.svg)](https://github.com/tmux-revamped/tmux-persist-revamped/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.3.0-blue.svg)](CHANGELOG.md)

<p align="center">
  <a href="#what-it-does">功能</a> &nbsp;|&nbsp;
  <a href="#installation">安装</a> &nbsp;|&nbsp;
  <a href="#usage">用法</a> &nbsp;|&nbsp;
  <a href="#configuration">配置</a> &nbsp;|&nbsp;
  <a href="#key-bindings">按键绑定</a> &nbsp;|&nbsp;
  <a href="#how-it-works">工作原理</a>
</p>

</div>

**每 15 分钟自动保存一次。每个槽位保留最近 5 次保存。无需配置即可重新启动 20 种程序。已在 macOS 和 Linux 上测试。**

---

<a id="what-it-does"></a>

## 功能

保存时会记录服务器上的每个会话、窗口和窗格：窗口名称、索引、布局和缩放状态，当前窗口和当前窗格，每个窗格的工作目录，以及其中运行的程序。恢复时会重建这一结构，让每个 shell 窗格回到原来的目录，并重新启动重启列表中的程序。

同一个插件还会按定时器自动保存、保留保存历史、把整个环境存入命名槽位，并且可以安装登录代理，让 tmux 服务器和已恢复的环境在打开第一个终端之前就已就绪。

## 环境要求

| 项目 | 版本或说明 |
|:------------|:----------------|
| tmux | 3.2 或更高版本 |
| bash | 3.2 或更高版本，因此 macOS 自带的 `/bin/bash` 可以使用 |
| 操作系统 | Apple Silicon 和 Intel 上的 macOS，x86_64 和 arm64 上的 Linux |
| 核心工具 | BSD、GNU 或 uutils coreutils |
| `fzf` | 可选，用于槽位选择器 |
| `launchctl` 或 `systemctl --user` | 可选，用于 macOS 或 Linux 上的登录代理 |

<a id="installation"></a>

## 安装

使用 [TPM](https://github.com/tmux-plugins/tpm) 时，把插件加入 `~/.tmux.conf`，然后按 `prefix + I`：

```tmux
set -g @plugin 'tmux-revamped/tmux-persist-revamped'
```

不使用 TPM 时，克隆仓库，并在 `~/.tmux.conf` 中运行入口脚本：

```sh
git clone https://github.com/tmux-revamped/tmux-persist-revamped ~/.tmux/plugins/tmux-persist-revamped
```

```tmux
run-shell ~/.tmux/plugins/tmux-persist-revamped/persist-revamped.tmux
```

<a id="usage"></a>

## 用法

按 `prefix + C-s` 保存，按 `prefix + C-r` 恢复最近一次保存。插件加载后自动保存即开始工作。

在服务器启动时恢复并更频繁地保存：

```tmux
set -g @persist_revamped_restore_on_start 'on'
set -g @persist_revamped_interval '5'
set -g @persist_revamped_processes 'lazygit k9s'
```

每个操作也是一条命令。以 `bash ~/.tmux/plugins/tmux-persist-revamped/src/persist.sh <command>` 运行，或绑定到按键。

| 命令 | 作用 |
|:--------|:-------|
| `save [slot]` | 立即保存，指定槽位名时保存到该槽位 |
| `restore [slot]` | 恢复最近一次保存，或恢复指定槽位 |
| `merge <session> [slot]` | 只恢复一个会话，且仅在不存在同名会话时恢复 |
| `slots` | 列出命名槽位 |
| `pick` | 用 fzf 选择一个命名槽位并恢复 |
| `preview [slot]` | 显示保存的路径、模式版本、来源主目录，以及窗口和窗格数量 |
| `verify [slot]` | 检查模式头、记录数量和保存的时长 |
| `doctor` | 报告保存目录、找到的工具、停止文件和登录代理 |
| `event` | 供关闭钩子使用，每个防抖周期最多保存一次 |
| `boot-install` | 写入并加载登录代理 |
| `boot-uninstall` | 卸载并删除登录代理 |
| `boot-sync` | 按 `@persist_revamped_boot` 安装或删除登录代理 |

<a id="configuration"></a>

## 配置

在插件加载之前于 `~/.tmux.conf` 中设置选项。

| 选项 | 默认值 | 含义 |
|:-------|:--------|:--------|
| `@persist_revamped_interval` | `15` | 自动保存的间隔，单位为分钟。`0` 关闭自动保存 |
| `@persist_revamped_dir` | `$XDG_STATE_HOME/tmux/persist` | 保存目录。未设置 `XDG_STATE_HOME` 时为 `~/.local/state/tmux/persist`。会展开开头的 `~`，以及 `$HOME` 和 `$HOSTNAME` |
| `@persist_revamped_scope_socket` | `on` | 为默认套接字以外的每个服务器分配独立的保存目录 |
| `@persist_revamped_processes` | 空 | 额外要重新启动的程序，追加到内置列表。每一项都是 shell glob |
| `@persist_revamped_capture_panes` | `off` | `on` 时保存每个窗格的可见文本，并在恢复时重绘，末尾的空行会被去掉 |
| `@persist_revamped_capture_args` | `off` | `on` 时保存每个程序的完整命令行，例如 `vim src/app.ts`，并按原样重新运行。含有 shell 元字符或引号的命令行只按程序名重新启动 |
| `@persist_revamped_redact` | 空 | 额外的、绝不捕获其窗格文本的程序，追加到 `ssh sudo su vault gpg pass op ssh-add openssl` |
| `@persist_revamped_restore_on_start` | `off` | `on` 时在服务器启动时恢复最近一次保存 |
| `@persist_revamped_halt_file` | `<save dir>/no-restore` | 该文件存在期间，跳过启动时恢复 |
| `@persist_revamped_boot` | `off` | `on` 时安装登录代理，在登录时启动 tmux 服务器 |
| `@persist_revamped_boot_command` | `new-session -d` | 登录代理传给 tmux 的参数 |
| `@persist_revamped_boot_label` | `tmux-persist-revamped` | launchd 标签或 systemd 单元名 |
| `@persist_revamped_boot_grace` | `60` | 启动时恢复之后不进行自动保存和事件保存的秒数 |
| `@persist_revamped_backups` | `5` | 每个槽位历史中保留的保存数量，包括当前这一次。最小为 `1` |
| `@persist_revamped_event_debounce` | `0` | 秒数。大于 `0` 时，关闭会话或窗口会触发保存，每个周期最多一次 |
| `@persist_revamped_stale_secs` | `0` | `verify` 会对超过此秒数的保存发出警告。`0` 关闭该检查 |
| `@persist_revamped_vim_sessions` | `off` | `on` 时，如果窗格目录中有 `Session.vim`，就用 `-S` 重新打开 vim、nvim、vi、gvim 或 mvim |
| `@persist_revamped_rewrite_home` | `off` | `on` 时，恢复时把保存中记录的主目录改写为当前主目录，适用于在机器之间迁移的保存 |
| `@persist_revamped_save_key` | `C-s` | 用于保存的前缀键 |
| `@persist_revamped_restore_key` | `C-r` | 用于恢复的前缀键 |
| `@persist_revamped_pick_key` | 空 | 在弹出窗口中打开槽位选择器的前缀键。设置之前不绑定 |
| `@persist_revamped_pre_save_hook` | 空 | 每次保存之前运行的 shell 命令 |
| `@persist_revamped_post_save_hook` | 空 | 每次保存成功之后运行的 shell 命令 |
| `@persist_revamped_pre_restore_hook` | 空 | 每次恢复之前运行的 shell 命令 |
| `@persist_revamped_post_restore_hook` | 空 | 每次恢复之后运行的 shell 命令 |

内置的重启列表是 `vi vim nvim emacs nano man less more tail top htop btop watch ssh mosh irssi weechat mutt claude codex`。运行其他程序的窗格会以 shell 的形式回到正确的目录。

### 内部状态

以下选项由插件自行管理，请勿设置。

| 选项 | 内容 |
|:-------|:------|
| `@persist_revamped_booted` | 启动时恢复已运行或被停止文件跳过后为 `1`，这样重新加载配置时不会再次恢复 |
| `@persist_revamped_boot_ts` | 启动时恢复完成时的纪元秒，即宽限期的起点 |
| `@persist_revamped_last_ts` | 最近一次成功自动保存的纪元秒 |
| `@persist_revamped_event_ts` | 最近一次事件保存的纪元秒 |
| `@persist_revamped_worker_pid` | 自动保存工作进程的进程 ID，重新加载时据此停止旧进程 |

<a id="key-bindings"></a>

## 按键绑定

| 按键 | 作用 | 选项 |
|:----|:-------|:-------|
| `prefix + C-s` | 保存 | `@persist_revamped_save_key` |
| `prefix + C-r` | 恢复最近一次保存 | `@persist_revamped_restore_key` |
| 未绑定 | 在弹出窗口中选择命名槽位 | `@persist_revamped_pick_key` |

`C-s` 和 `C-r` 是 tmux-revamped 家族分配给本插件的按键。使用 `C-` 是为了不松开修饰键就能保存和恢复。

<a id="how-it-works"></a>

## 工作原理

**保存。** 保存时用 `list-windows -a` 和 `list-panes -a` 读取服务器，为每个窗口和窗格写入一条转义后的记录到临时文件，再把完成的文件以带时间戳的名称移入 `history/`。槽位路径 `last.txt` 或 `slots/<name>.txt` 是指向最新文件的符号链接。中断的保存不会留下不完整的文件。

**历史。** 与上一次相同的保存会被丢弃，因此空闲的机器不会塞满历史。超出 `@persist_revamped_backups` 的旧文件会被删除。回滚只需把符号链接指向较旧的文件。

**安全。** 含有窗口的保存绝不会被不含窗口的保存替换。服务器在启动期间以及关闭最后一个会话期间没有任何会话，此时的保存会抹掉整个环境。同一时间只运行一次保存，由一个锁目录保护，被强制终止的保存占用该锁不会超过两分钟。

**恢复。** 恢复时重新创建每个会话，并把每个窗口放回保存时的索引。如果该索引已被占用，窗口会放到一个空闲的索引。每个运行 shell 的窗格会收到一条回到其目录的 `cd`，重启列表中的程序会再次启动。布局、当前窗口、当前窗格和缩放最后应用。

**自动保存。** 只要间隔不是 `0`，加载插件时就会为每个服务器启动一个后台工作进程。它每 60 秒唤醒一次，间隔已到就保存。它从不写入 `status-right`。服务器不再响应或被更新的工作进程接替时，它就退出。

**多个服务器。** 一台机器上的所有 tmux 服务器都读取同一个 `~/.tmux.conf`。只有默认套接字 `${TMUX_TMPDIR:-/tmp}/tmux-<uid>/default` 保存到保存目录的顶层。用 `-L name` 启动的服务器保存到 `servers/name/`，用 `-S path` 启动的服务器保存到以该路径命名的目录。

**登录代理。** 启用 `@persist_revamped_boot` 后，插件在 macOS 上把 launchd 代理写入 `~/Library/LaunchAgents/`，在 Linux 上把 systemd 用户单元写入 `~/.config/systemd/user/`。它在登录时启动 tmux 服务器，因此启动时恢复会在打开任何终端之前完成。服务器退出后，代理不会重新启动它。

**停止文件。** 如果恢复带回了出问题的状态，请创建停止文件，再启动一个干净的服务器。在删除该文件之前，启动时恢复一直处于关闭状态。把 `@persist_revamped_halt_file` 指向 `/tmp` 时，由于 Linux 在开机时清空 `/tmp`，停止只持续到下次开机。

会话组不会被重建。分组的会话会作为拥有自己窗口的独立会话恢复。

## 开发

| 命令 | 作用 |
|:--------|:-------------|
| `make test` | 运行 bats 测试套件 |
| `make lint` | 对所有 shell 文件运行 shellcheck |
| `make coverage` | 用 kcov 测量行覆盖率，低于 95% 时失败，在 Linux 上运行 |

测试套件需要 `bats-core` 和 tmux。

## 许可证

[MIT](LICENSE)

<!-- family:begin -->

## tmux-revamped 插件家族

本插件是 tmux-revamped 家族的一员。每个成员都带有 [`FAMILY.md`](FAMILY.md) 中的同一份约定、`family/` 下的同一套工具和同一个共享库，并由校验和清单保持逐字节一致。这些插件设计为一起安装：任何成员都不会占用另一个成员已占用的按键或 tmux 选项。

在一个成员中发现的缺陷，要在所有成员中排查之后才算修复完成。这项义务写在约定里，而不是靠记忆，`family/bin/sweep` 就是履行它的工具。

| 成员 | 功能 |
|---|---|
| [`tmux-autoreload-revamped`](https://github.com/tmux-revamped/tmux-autoreload-revamped) | 编辑并保存 tmux 配置后自动重新加载，无需按键或命令 |
| [`tmux-battery-revamped`](https://github.com/tmux-revamped/tmux-battery-revamped) | 在 tmux 状态栏显示电池状态，绝不阻塞状态栏渲染 |
| [`tmux-bluetooth-revamped`](https://github.com/tmux-revamped/tmux-bluetooth-revamped) | 在 tmux 状态栏显示所有已连接的蓝牙设备及其电量，不阻塞渲染 |
| [`tmux-cpu-revamped`](https://github.com/tmux-revamped/tmux-cpu-revamped) | 在 tmux 状态栏显示 CPU 负载、温度和频率，绝不阻塞渲染 |
| [`tmux-disk-revamped`](https://github.com/tmux-revamped/tmux-disk-revamped) | 在 tmux 状态栏显示磁盘使用量，绝不阻塞状态栏渲染 |
| [`tmux-extract-revamped`](https://github.com/tmux-revamped/tmux-extract-revamped) | 用 fzf 从屏幕上选取 URL、路径、哈希或其他片段并输入到光标处，纯 shell 实现 |
| [`tmux-fzf-revamped`](https://github.com/tmux-revamped/tmux-fzf-revamped) | 在弹出窗口的 fzf 选择器中切换、关闭、重命名或创建 tmux 会话、窗口和窗格 |
| [`tmux-git-revamped`](https://github.com/tmux-revamped/tmux-git-revamped) | 在 tmux 状态栏显示当前窗格的 git 分支、变更和托管平台计数，不阻塞状态栏 |
| [`tmux-gpu-revamped`](https://github.com/tmux-revamped/tmux-gpu-revamped) | 在 tmux 状态栏显示 NVIDIA、AMD、Intel 和 Apple GPU 的负载、温度、频率、功耗和显存 |
| [`tmux-kube-revamped`](https://github.com/tmux-revamped/tmux-kube-revamped) | 在 tmux 状态栏显示当前 Kubernetes 上下文和命名空间，直接解析 kubeconfig，无需 kubectl |
| [`tmux-launcher-revamped`](https://github.com/tmux-revamped/tmux-launcher-revamped) | 以当前窗格的目录在弹出窗口或新窗口中启动任意 TUI 应用，只需一个可配置的按键 |
| [`tmux-logging-revamped`](https://github.com/tmux-revamped/tmux-logging-revamped) | 将任意窗格保存到文件：实时日志、完整回滚记录或一次性截图 |
| [`tmux-music-revamped`](https://github.com/tmux-revamped/tmux-music-revamped) | 在 tmux 状态栏显示正在播放的曲目，绝不阻塞状态栏渲染 |
| [`tmux-network-revamped`](https://github.com/tmux-revamped/tmux-network-revamped) | 在 tmux 状态栏显示网络吞吐量，绝不阻塞渲染 |
| [`tmux-pain-control-revamped`](https://github.com/tmux-revamped/tmux-pain-control-revamped) | tmux 的标准窗格与窗口管理按键绑定，适配各版本，对 vim 友好，可完全配置 |
| [`tmux-persist-revamped`](https://github.com/tmux-revamped/tmux-persist-revamped) | **本插件**，保存 tmux 的所有会话、窗口和窗格，按定时器自动保存，并在重启后全部恢复 |
| [`tmux-plugin-template`](https://github.com/tmux-revamped/tmux-plugin-template) | tmux-revamped 插件的起点：共享库、bats 测试框架、CI 和家族工具 |
| [`tmux-pomodoro-revamped`](https://github.com/tmux-revamped/tmux-pomodoro-revamped) | tmux 状态栏中的番茄钟计时器，所有状态都保存在 tmux 选项中，不使用临时文件 |
| [`tmux-ram-revamped`](https://github.com/tmux-revamped/tmux-ram-revamped) | 在 tmux 状态栏显示内存、交换空间和内存压力，在后台采样，渲染从不等待 |
| [`tmux-reorder-revamped`](https://github.com/tmux-revamped/tmux-reorder-revamped) | 用鼠标在 tmux 状态栏上拖动窗口标签来移动该窗口 |
| [`tmux-scroll-revamped`](https://github.com/tmux-revamped/tmux-scroll-revamped) | 将鼠标滚轮交给能自行滚动的应用，其他情况下进入 tmux 复制模式 |
| [`tmux-sensible-revamped`](https://github.com/tmux-revamped/tmux-sensible-revamped) | 合理的 tmux 默认设置，按 tmux 版本和终端启用，不改动你已设置的选项 |
| [`tmux-tiling-revamped`](https://github.com/tmux-revamped/tmux-tiling-revamped) | tmux 的平铺式窗口管理：8 种布局，包括 BSP dwindle 和 spiral，并可撤销布局 |
| [`tmux-time-revamped`](https://github.com/tmux-revamped/tmux-time-revamped) | tmux 状态栏的本地时钟和世界时钟，按时段着色，附带倒计时和夏令时提醒 |
| [`tmux-weather-revamped`](https://github.com/tmux-revamped/tmux-weather-revamped) | 在 tmux 状态栏显示来自 wttr.in 的天气，在后台获取，状态栏从不等待 |

### 检查安装

所有成员都在磁盘上时，一条命令即可报告它们之间的任何冲突：

```sh
family/bin/doctor --live
```

它会读取每个成员和正在运行的 tmux 服务器，并报告重复的按键、重复的状态栏占位符、不符合命名规则的选项，以及约定版本落后的成员。

<!-- family:end -->
