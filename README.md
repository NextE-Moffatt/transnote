# TransNote — 一个原生 macOS 应用：右击英译中，并可加入笔记

在任意 App 里选中英文 → **右击** → 「服务 / Services」或「快速操作」→ **英译中**，
应用窗口会弹出并显示原文和译文，可一键追加到 Markdown 笔记。

选中中文时会自动反向翻成英文。

## 右击菜单里的两项

| 菜单项 | 行为 |
| --- | --- |
| 英译中 | 打开窗口，填入选中文本并自动翻译；译文自动复制到剪贴板 |
| 英译中并加入笔记 | 同上，但翻译完成后立刻追加到笔记文件 |

## 应用本身怎么用

    open -a TransNote

窗口分三块：上面是原文输入框（可以直接粘贴或手打），中间是「翻译 / 加入笔记 / 复制译文」按钮，
下面是译文。

## 生词本

主窗口的**「生词本」按钮**（或菜单「操作 → 生词本」，快捷键 ⌘L）会打开一个独立窗口，
把之前记录下来的条目全部列出来：

- 四列：**时间 / 原文 / 音标 / 译文**，默认按记录顺序（最早在前）
- **点列头排序**：点「原文」按字母排，点「时间」按时间排；再点一次切换升/降序，
  列头会显示小三角
- **记录顺序按钮**：清掉列头排序，回到「记录的先后顺序」；并且每点一次在
  **最早在前（↑）** 和 **最新在前（↓）** 之间切换，按钮上的箭头就是当前方向。
  如果当前是按列排序，点一下会先回到记录正序，这样第一次点总是可预期的
- **按时间筛选**：下拉选择 全部时间 / 今天 / 昨天 / 最近 7 天 / 最近 30 天 / 自定义…
  选「自定义…」后，右边的两个日期框变为可用，指定起止日期即可
- 顶部**搜索框**实时过滤，原文、译文、音标、词典释义都参与匹配
- 选中一行后可点「朗读」「复制原文」「复制译文」；**双击一行等于复制原文**
- **删除**：选中一行或多行（按住 ⌘ 或 ⇧ 多选），按 **Delete 键**或点「删除」按钮。
  会先弹确认框，确认后**自动备份**笔记文件再改写。备份在
  ~/.transnote/backups/翻译笔记-<日期时间>.md，删错了直接把它拷回去即可。
- **朗读**：英文用美式嗓音（Samantha），中文条目自动切中文嗓音（Tingting），完全离线
- **导出 CSV**：把**当前显示的内容**导出成 CSV——已经算上搜索、时间筛选和排序，
  所以可以「只看最近 7 天 → 导出」，直接就是这段时间的生词表。
  五列：原文 / 音标 / 词典释义 / 译文 / 时间。文件带 UTF-8 BOM，Excel 打开不乱码，
  Anki（工具 → 导入文件）也能直接读
- 右侧「打开笔记文件」用系统默认的 Markdown 编辑器打开原始文件
- 主窗口里新记一条时，生词本如果开着会自动刷新
- 底部状态栏会说明当前状态，例如：
  「共 10 条 · 当前显示 3 条 · 最近 7 天 · 按原文升序」

排序、搜索、时间筛选三者是叠加的：可以「只看最近 7 天 + 搜 trajectory + 按原文排序」。

## 快捷键

**全局快捷键**（任何 App 里都能按，由应用用 Carbon RegisterEventHotKey 注册，不需要辅助功能权限）：

| 快捷键 | 作用 |
| --- | --- |
| ⌥⌘T | 翻译剪贴板内容 |
| ⌥⇧⌘T | 翻译剪贴板内容并加入笔记 |

### 全局快捷键怎么拿到文字

按优先级依次尝试，日志里会记录实际用了哪一种：

1. **模拟 ⌘C**：直接把当前选区复制过来。它复制的一定是「此刻的选区」，最可靠。
   代价是会占用剪贴板——不过应用随后本来就会把译文写进剪贴板，所以不影响使用。
2. **辅助功能 API** 直接问焦点元素要 AXSelectedText。它不碰剪贴板，
   但实测中**有时会返回陈旧的选区**（明明换了新文字，仍返回上一段），所以只当兜底。
3. 都拿不到才退回读**剪贴板**（这条不需要任何权限）。

前两种都需要在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 TransNote：

    打开应用 → 菜单「操作 → 启用「选中即翻译」（辅助功能授权）…」
    → 系统会弹出提示 → 到「隐私与安全性 → 辅助功能」里打开 TransNote
    → 重启应用：killall TransNote; launchctl kickstart -k gui/$UID/com.transnote.app

授权后就是「选中文字 → 直接按 ⌥⌘T」，不需要先复制。没授权时只能翻剪贴板，
状态栏会提示，而且日志里会写「已授权=否」。

### 签名身份（为什么必须用它）

ad-hoc 签名的「指定要求」只有一句 cdhash：

    designated => cdhash H"bc7fbf01..."

**每次重新编译 cdhash 都会变**，于是 macOS 里那条辅助功能授权就对不上新二进制了，
表现就是「明明打开了开关，应用还是说自己没授权」。

所以 build.sh 会调用 make-identity.sh 在登录钥匙串里建一个固定的自签名身份
（TransNote Local Signing），用它签名后指定要求变成：

    designated => identifier "com.transnote.app" and certificate root = H"59d151a4..."

它引用的是证书，不随重新编译变化，**授权一次就能长期有效**。
这个证书不加入系统信任列表，也不影响 Gatekeeper，只放在登录钥匙串里。

如果哪天授权又对不上了，重置一次再重新授权即可：

    tccutil reset Accessibility com.transnote.app

### 关于剪贴板模式的两个细节

- 应用会把译文复制到剪贴板（方便你直接粘贴），所以如果没授权又反复按同一个快捷键，
  第二次读到的会是上一次的译文。**这种情况现在会被识别并拦下来**，提示你「剪贴板里还是上一次的译文」，
  不会再出现中英来回自翻的死循环。
- 按住快捷键不放会连发，已做 0.35 秒防抖。
- 用「模拟 ⌘C」取选区时会短暂占用剪贴板；如果你把 copyToClipboard 关掉，
  原来的剪贴板内容会被选中文字替换掉（默认开着，所以最终留在剪贴板上的是译文）。

**应用内快捷键**（TransNote 窗口是当前窗口时）：

| 快捷键 | 作用 |
| --- | --- |
| ⌘↩ | 翻译 |
| ⌘S | 加入笔记 |
| ⌘⇧C | 复制译文 |
| ⌘C / ⌘V / ⌘A | 正常可用的复制、粘贴、全选 |

改键位：编辑 ~/.transnote/config.json 里的 hotkeyTranslate / hotkeyAddNote，
写法是「修饰键+按键」，例如 opt+cmd+T、ctrl+shift+D、cmd+shift+1。
修饰键可用 cmd / opt / ctrl / shift，按键支持 a-z、0-9、return、space、tab、escape 等。
把某一项设成空字符串 "" 就取消该快捷键。改完重启应用生效（killall TransNote && open -a TransNote），
用 --hotkeys 可以检查是否解析和注册成功。

### 想让快捷键直接作用于「选中的文字」

服务的快捷键由系统分发，能拿到真正的选区，比应用内热键更好用。设置方法：

1. 先把应用内的热键让开：把 config.json 里 hotkeyTranslate 和 hotkeyAddNote 都设成 ""，
   然后 killall TransNote && open -a TransNote。
2. 打开「系统设置 → 键盘 → 键盘快捷键 → 服务 → 文本」，
   给「英译中」和「英译中并加入笔记」各指定一个快捷键。

这样就不需要先复制，选中后直接按即可。

## 安装 / 卸载

    cd /path/to/transnote
    ./install.sh      # 构建 + 安装到 /Applications + 注册系统服务
    ./uninstall.sh    # 卸载

install.sh 会自动把旧版基于 Automator 快速操作的实现从 ~/Library/Services 里移除，
避免右击菜单出现重复项。

## 配置

配置文件：~/.transnote/config.json（改完立即生效，不用重装）

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| engine | auto | 翻译引擎，见下表 |
| sourceLanguage | en | 源语言 |
| targetLanguage | zh-CN | 目标语言 |
| autoDirection | true | 选中中文时自动反向翻成英文 |
| notesPath | ~/Documents/翻译笔记.md | 笔记文件，支持 ~ |
| copyToClipboard | true | 翻译后自动复制译文到剪贴板 |
| mymemoryEmail | 空 | 填上邮箱可把 MyMemory 免费额度从约 5000 词/天提到 50000 词/天 |
| chunkBytes | 450 | 单次请求最大字节数（长文本会自动切块） |
| timeoutSeconds | 25 | 网络超时秒数 |
| hotkeyTranslate | opt+cmd+T | 全局「翻译剪贴板」快捷键，留空则关闭 |
| hotkeyAddNote | shift+opt+cmd+T | 全局「翻译剪贴板并加入笔记」快捷键，留空则关闭 |
| dedupe | true | 同一个词已经记过就不再重复记（忽略大小写和首尾引号） |

引擎可选值：

| engine | 说明 |
| --- | --- |
| auto | 先用有道，失败再自动改用 MyMemory（默认，推荐） |
| youdao | 只用有道公开接口（国内直连、速度快、实测 0.2 秒返回，无需 key） |
| mymemory | 只用 MyMemory（免费额度约 5000 词/天，超额会报错） |

## 命令行用法

    APP=/Applications/TransNote.app/Contents/MacOS/TransNote

    $APP --selftest              # 自检：配置、路径、翻译、反向翻译
    $APP --print "Hello world"   # 只翻译并打印
    echo "Hello" | $APP --print  # 从 stdin 读
    $APP --note "Hello world"    # 翻译并加入笔记
    $APP --dump-ui               # 不开窗口，检查界面对象是否都建好了
    $APP --hotkeys               # 检查全局快捷键的解析与注册
    $APP --lookup "unsigned"     # 查一个词/一句话，打印音标、词典释义、译文和判定
    $APP --vocab                 # 打印解析出来的生词条目
    $APP --vocab-ui [关键词]     # 建生词本窗口并检查表格/搜索，不显示窗口
    $APP --vocab-export out.csv [搜索词] [排序列] [asc|desc] [时间序号]   # 导出 CSV
    $APP --vocab-delete-test <文件> <块序号>   # 在指定文件上试删除（不动真实笔记）
    $APP --pingpong-test         # 复现「反复按导致自翻」的场景，验证已拦住
    $APP --trigger-hotkey        # 按一次全局快捷键的逻辑（读剪贴板 → 翻译）
    $APP --trigger-hotkey-note   # 同上并加入笔记
    $APP --service-test "text"   # 模拟一次右击服务调用
    $APP --background            # 后台启动：只注册快捷键，不显示窗口
    $APP --register              # 刷新系统服务注册
    $APP --version

日志在 ~/.transnote/transnote.log。

## 笔记格式

每次追加一条：

    ## 2026-09-18 15:57

    **原文（英文）**

    > unsigned

    **音标**

    > [ˌʌnˈsaɪnd]

    **词典释义**

    > adj. 未签名的，未署名的；（计算机）无符号的；（体育／娱乐）未签约的

    **译文（中文）**

    > 无符号

    ---

句子没有中间两段：

    ## 2026-09-18 15:57

    **原文（英文）**

    > Deep learning models require substantial compute.

    **译文（中文）**

    > 深度学习模型需要大量的计算。

    ---

文件不存在时会自动创建，并加上「# 翻译笔记」标题。**旧格式的记录照样能读**。

### 单词自动走词典

判定规则：不含空格、不含数字和奇怪符号，且只有「一个词」——所以 state-of-the-art 算单词，
unsigned int 和整句话算句子。

- **单词**：先查词典（dict.youdao.com），把音标和多义项一起记下来，再走翻译拿简短译文。
  词典给的是真正的词典内容，比机器翻译有用——unsigned 会告诉你「（计算机）无符号的」，
  而机器翻译只给「无符号」。
- **句子**：只走翻译，和以前一样。
- 词典查不到（网络问题、生僻词）就静默跳过，不影响翻译。
- 单词和句子用同一套结构，音标和词典释义是可选段落；旧记录没有这两段也照样解析。

## 源码结构与构建

    src/TransNoteEngine.h/.m   翻译引擎：分块、双引擎、回退、笔记写入（Foundation + NSURLSession）
    src/TNHotKeys.h/.m         全局快捷键：解析 "opt+cmd+T" 并注册 Carbon 热键
    src/TNSelection.h/.m       读取当前选中文字：辅助功能 API + 模拟 ⌘C 兜底
    src/TNNotes.h/.m           解析翻译笔记.md 里的条目
    src/TNVocab.h/.m           生词本窗口：搜索 + 表格 + 复制
    src/main.m                 应用主体：窗口界面、菜单、服务回调、快捷键、命令行模式
    src/makeicon.m             用 AppKit 绘制图标并生成 .icns
    build.sh                   编译 + 生成图标 + 组装 .app + 用固定身份签名
    make-identity.sh           创建本地自签名签名身份（只需一次，可重复运行）
    install.sh / uninstall.sh  安装 / 卸载（含登录项）
    legacy/                    旧的实现（Automator 快速操作 + Python 脚本），保留备用

构建只需要命令行开发者工具里的 clang，不需要 Xcode。

## 如果右击菜单里没有

1. 打开「系统设置 → 键盘 → 键盘快捷键 → 服务 → 文本」，勾选「英译中」和「英译中并加入笔记」。
2. 有些 App 把服务收在「服务」或「快速操作」子菜单里。
3. 重跑 ./install.sh 即可重新注册（它会重启 pbs 强制刷新服务列表）。

## 已知限制

- 翻译依赖网络。有道用的是其公开 demo 接口（aidemo.youdao.com），并非商业授权接口，
  长期可用性无法保证；MyMemory 作为兜底。两者都失败时窗口会显示具体的错误原因。
- 有道接口不需要 key，也没有观察到额度限制；MyMemory 匿名额度约 5000 词/天。
- 应用是本地构建 + ad-hoc 签名，没有做 Apple 公证。因为它不是从网上下载的，
  所以不会被 Gatekeeper 拦截；但如果以后你把它拷贝到别的机器，对方需要右键「打开」一次。
- 安装时会写入登录项 ~/Library/LaunchAgents/com.transnote.app.plist，
  让应用开机后在后台常驻，这样全局快捷键随时可用（后台常驻不会弹窗，也不占 Dock 之外的资源）。
  不想要的话执行：launchctl bootout gui/$UID/com.transnote.app && rm ~/Library/LaunchAgents/com.transnote.app.plist

## 为什么没有用 Apple 自带的离线翻译

这台机器上有三个硬性障碍：

1. **Swift 工具链损坏**。CommandLineTools 里 swift/module.modulemap 和 bridging.modulemap
   重复定义 SwiftBridging 模块，导致任何 import Foundation 的 Swift 代码都编译失败；
   同时编译器 build 号（6.0.3.1.10）与 SDK 里记录的不一致。这些文件归 root 所有，sudo 不可用。
   （Objective-C 不受影响，所以这个应用是用 ObjC 写的。）
2. **系统里没有「翻译」App**，因为中国大陆区域不提供，所以 Shortcuts 的「翻译文本」动作也不存在。
3. Translation.framework 唯一公开入口是 SwiftUI 的 .translationTask，而 SwiftUI 在上面那个
   工具链下无法编译。

如果以后重装了 Command Line Tools 并装上「翻译」App，可以改回完全离线的方案。
