# feishu-clone · 飞书 / Lark 多开

把 **飞书** 或 **Lark** 克隆成第二个 App，和原版**同时运行** —— 独立登录、独立锁、一台 Mac 上登两个账号。

```bash
bash clone-feishu.sh
open -n "/Applications/Feishu 测试.app"
```

## 为什么需要这个

飞书 / Lark 基于 Chromium。它的 `ProcessSingleton` 单例锁在 `~/Library/Application Support/LarkShell/`，而且**不随** `--user-data-dir` 移动——所以直接再开一个飞书会被正在跑的那个顶掉、弹回原窗口。本脚本在每个含该字符串的 Mach-O 里把数据目录名 `LarkShell` 字节补丁成 `LarkClone`，让克隆体算出一个完全独立的数据树和锁，两个实例从此干净共存。

## 脚本做了什么

1. 拷贝源 `.app` bundle。
2. 改 `Info.plist`（新 bundle id + 新名字）。
3. 给图标调色相（让你在 Dock 里一眼区分原版和克隆）。
4. 在所有含 `LarkShell` 的二进制里字节补丁成 `LarkClone`。硬断言：补丁后零文件可残留旧名。
5. 封掉自更新（官方更新器会把字节补丁覆盖回去，克隆体变回和原版抢锁——见下文「坑 3」）。
6. 自底向上 ad-hoc 重签。
7. 注册到 LaunchServices。

约 4 分钟跑完。无需 brew、无需 root、无需关 SIP。

## 环境要求

- macOS（Apple Silicon 已验证；Intel 理论可用但未实测）。
- 已装飞书或 Lark，位于 `/Applications/Lark.app`、`/Applications/飞书.app` 或 `~/Applications/` 下任一变体。**自动探测**，无需告诉脚本是哪个；如探测失败用 `SRC=/path/to/App.app` 覆盖。
- 可选：Xcode Command Line Tools 用于图标调色（`xcode-select --install`）。没装的话图标保持原样——纯装饰，不影响功能。

## 参数 / 环境变量（全可选）

| 位置参 | 环境变量 | 默认值 | 用途 |
|---|---|---|---|
| `$1` | — | `Feishu 测试` | 克隆显示名（同时是 .app 文件名） |
| `$2` | — | `com.electron.lark.test` | 新 bundle id（必须和原版不同） |
| `$3` | — | `2.4` | 图标色相旋转弧度（约 137°） |
| — | `SRC` | 自动探测 | 源 `.app` 路径（探测失败时覆盖） |
| — | `OLDDIR` | `LarkShell` | 源数据目录名（9 字节） |
| — | `NEWDIR` | `LarkClone` | 克隆数据目录名（**必须和 `OLDDIR` 等长**） |

## 作为 agent skill 使用

本 repo 同时是一个**跨平台 agent skill**。把目录拷贝/软链到你 agent 的 skills 文件夹即可——自带的 `SKILL.md` 是标准 `name` + `description` frontmatter，四家通用：

| 平台 | 安装路径 |
|---|---|
| **WorkBuddy**（首选） | `~/.workbuddy/skills/feishu-clone/` |
| Claude Code | `~/.claude/skills/feishu-clone/` |
| Codex | `~/.codex/skills/feishu-clone/` |
| Grok | `~/.grok/skills/feishu-clone/` |

**一键安装**（任选一条）：

```bash
# WorkBuddy（首选）
git clone https://github.com/eggyrooch-blip/feishu-clone.git ~/.workbuddy/skills/feishu-clone
# Claude Code
git clone https://github.com/eggyrooch-blip/feishu-clone.git ~/.claude/skills/feishu-clone
# Codex
git clone https://github.com/eggyrooch-blip/feishu-clone.git ~/.codex/skills/feishu-clone
# Grok
git clone https://github.com/eggyrooch-blip/feishu-clone.git ~/.grok/skills/feishu-clone
```

装好后跟 agent 说「克隆飞书」「飞书多开」「clone lark」「second feishu account」等就会触发。**agent 不需要预判装的是飞书还是 Lark**——脚本自动探测。

## 出问题怎么办

**几个月后克隆登不上** —— 飞书服务端开始强制最低版本，冻结的克隆太旧了。直接重跑脚本即可（对着更新过的源 App），克隆体会按新版本重建。这是设计取舍：克隆体故意冻结，让自动更新没法偷偷把字节补丁覆盖回去。

**`FATAL: no file contained 'LarkShell'`** —— 新版飞书把数据目录改名了。在 `~/Library/Application Support/` 下找新的目录名，用 `OLDDIR=<新名> NEWDIR=<新名-clone>`（两者必须等长）重跑。然后欢迎开 issue 或 PR 更新默认值。

**`FATAL: unpatched holders remain`** —— 同上原因，部分残留。查哪个文件还带旧字符串，别强行覆盖断言。

**克隆闪退、无窗口** —— codesign 没把内层重新封好。重跑脚本（每次都从头重建）。还不行就 `codesign --verify --strict --deep "/Applications/<NAME>.app"` 看具体哪个内层件没签。

**图标没变色** —— 没装 CLT。`xcode-select --install` 装完重跑，或接受默认图标，功能不受影响。

**Intel Mac** —— 字节补丁和 ad-hoc 签名都是架构无关的，理论可用但未实测。遇到问题请记录具体哪步失败。

## 已知坑（历史教训）

- **坑 1**：`codesign --deep` 不会重新封内层 helper，必须自底向上逐层签，否则克隆启动即崩。
- **坑 2**：`grep` 处理几百 MB 的 Mach-O 会卡死（巨型行 + NUL 字节）。脚本用 `strings` 检测、`perl -0777` 打补丁绕开。
- **坑 3**（致命，2026-07-20 发现）：飞书克隆体自带完整升级器，会在后台下载官方更新包替换掉克隆体——替换后的官方二进制锁目录名变回 `LarkShell`，字节补丁被覆盖，克隆体回头跟主飞书抢同一把锁，双开静默失效。脚本第五步双层封堵（替换更新器为空脚本 + `chflags uchg` 锁下载目录）。

## repo 文件

- `clone-feishu.sh` —— 主脚本（唯一重要的东西）。
- `recolor-icon.swift` —— 图标调色相辅助（脚本调用，非独立运行）。
- `SKILL.md` —— 让 agent 平台发现这个脚本的 skill 描述。

## License

MIT
