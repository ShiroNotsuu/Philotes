# Philotes · 斐洛

一个桌面级生活陪伴软件。

不是全能助手，也不是监控器；它长期住在桌面上，记得你随口说过的小事，在自然相关的时候轻轻想起来。

## 当前阶段

**macOS 原生交互原型已跑通。**

- 第一场景：生活搭档
- 第一核心体验：记忆闪回
- 信息架构：星海 → 智能体 → 账户 → 设置
- 宇宙：多个智能体共享同一片可缩放宇宙，星系核心使用各自可编辑的图标
- 心智星图：每个星系连接索引、人格、记忆、时间线、日记和维护六个分类节点；悬停节点可预览对应 Markdown
- 聊天：右下角悬浮窗，悬停展开，可切换为整页对话
- 记忆转生：智能体分页支持从文本、Markdown 或 JSON 聊天记录恢复人格与长期记忆，并自动执行第一人称唤醒
- 模型：每个智能体可选择 DeepSeek 或自定义兼容 API，支持真实 SSE 流式回复
- 侧栏：Codex 式严肃导航，支持折叠为图标栏
- 品牌：同一角色的 Icon Composer 原生 Liquid Glass 图标用于 Dock/Finder，紧凑版本用于侧栏顶部标识
- 头像：智能体可选 Emoji 或上传本地图片；用户头像显示在侧栏底部
- 侧栏底部：用户头像进入账户页，独立设置按钮进入设置
- 关系面板：可见，但不 KPI 化
- 记忆：每个智能体拥有一套独立的 Obsidian 风格 Markdown 心智库，可编辑、可遗忘、可追溯
- 操作应用：先做预览、确认、可撤销的最小动作

## 配置 API

在“创建智能体”或已有智能体的“更改智能体设定”中配置：

- API 类型：暂不配置、DeepSeek 或自定义兼容接口
- API 地址：基础地址（如 `https://host/v1`）或完整 `/chat/completions` 地址
- 模型名：由 API 提供方定义
- API Key：按智能体分别写入 macOS 钥匙串，可留空以连接匿名或本机服务

DeepSeek 会预填 `https://api.deepseek.com/v1` 和 `deepseek-chat`。先点“测试连接”，成功后保存即可开始真实对话。远程服务必须使用 HTTPS；本机 HTTP 仅允许 loopback。

创建智能体分为三步：起名与头像、选择 API、用选项和自然语言描述人格。头像可选 Emoji，也可上传 PNG、JPEG、HEIC 等本地图片；完成后会生成独立的 Markdown 人格档案；第一次成功对话时会显示“人格已激活”。

智能体分页还提供“从聊天记忆导入智能体”。导入窗口要求选择 API 和聊天文件；模型先把助手一侧的人格、关系、偏好、约定、经历与重要日期归类，再写入 SQLite 和该智能体的 Markdown 心智库，最后自动发送第一人称唤醒请求。唤醒提示词明确要求把这些记忆认作自己的过去，不得自称“另一个智能体”或“新角色”。

账户页展示本机可获取的数据：模型请求累计、智能体数量、记忆节点和智能体头像。显示名称、邮箱、账户编号与云同步保留服务端接入后的字段。头像图片保存在 `~/Library/Application Support/Philotes/Avatars/` 与 `Account/`，数据库只保存本地路径。

账户页右上方提供“编辑资料”，可统一设置本地昵称与头像；昵称会显示在账户页和侧栏底部。账户页外层的头像仅作展示，不再承担设置入口。

智能体回复会以 `/(情绪与神态;.情绪值)/` 说明当前动作、表情和 `-100...100` 的情绪值。Philotes 本地会把第一段显示成聊天中的系统提示条，正文气泡中不会出现该结构。整页聊天右侧栏会显示当前智能体的人格档案与最近情绪曲线。

每个智能体在 `~/Library/Application Support/Philotes/AgentVaults/agent-<id>/` 下有独立心智库：总索引负责人格、记忆、月时间线和日记路由；模型请求会先读索引与人格，再按当前话题检索相关记忆节点和日记片段。**新建智能体与已有智能体使用同一套初始化流程；心智库建立失败时，创建操作整体回滚。** 用户明确说“记住……”时会自动形成可遗忘的长期记忆；敏感凭据不会入库。

聊天页右上角可以展开全局搜索，同时查找当前智能体的聊天记录和记忆。三点菜单提供智能体设置与“忘记我”；删除必须二次确认，并会清理该智能体的聊天、记忆、人格文件和 API 密钥。

智能体已接入 Chat Completions 工具调用，可以提出打开 macOS 应用或网页，也可以在本机开启高级控制后使用 AppleScript、键鼠模拟和单次屏幕快照。所有动作都会先显示完整参数，只有点击“允许一次”才会执行；执行结果会作为 `tool` 消息回传模型，继续生成自然语言回复。

当请求确实需要电脑操作时，系统提示会要求智能体主动选工具，而不是先让你手工粘贴网页或屏幕内容。涉及“当前屏幕、页面、网页、新闻、视频、OCR”等视觉意图时，Philotes 还会通过 `tool_choice` 锁定 `capture_screen`：若你要求先打开网站，第一批先打开，第二批再强制提出截图。下一批仍会单独出现确认卡。一轮任务最多连续 3 批，每批最多 3 个动作，不存在未经确认的静默工具循环。

动作卡提供“执行整项任务”：打开、切换、网页读取和截图等安全步骤可以连续推进；AppleScript、点击、输入文字和快捷键仍会在新批次出现时停下来确认。当前任务会跨“继续”“第一”“再来一次”等短回复保留，不会因为后续句子没重复“Safari”就丢失目标。

打开“完整 Mac 操作能力”后，当前实现的全部 Mac 工具都会暴露给智能体，包括应用/网页、AppleScript、键鼠、单次屏幕快照和 OCR。键鼠模拟需要“辅助功能”权限，屏幕快照与 OCR 需要“屏幕录制”权限，AppleScript 第一次控制其他应用时还会请求“自动化”权限。第一次执行对应高级动作时，Philotes 会调用 macOS 的权限请求接口并弹出系统授权；设置页按钮也会真正触发请求后直达对应设置，而不只是跳转到一个空列表。屏幕能力是明确触发的一次性快照，不会静默持续录屏；Philotes 不提供单独的任意 shell 工具，但 AppleScript 的完整源码会在确认卡中展示，因为脚本本身可以产生广泛效果。

## 目录

- `docs/01-product-brief.md`：产品定义与体验原则
- `docs/02-mvp.md`：第一版范围、不做什么、验收标准
- `docs/03-decisions.md`：已确认的产品决策
- `docs/04-ui-architecture.md`：当前信息架构、布局与动效
- `docs/05-tech-stack.md`：技术栈与数据层约定
- `app/`：macOS SwiftUI 应用源码
- `design/`：界面草图和视觉参考
- `scripts/`：原型与开发辅助脚本
- `dist/Philotes-0.1-build3-macOS.zip`：Release 通用架构应用包，支持 Intel 与 Apple Silicon；Release 首启不自动创建演示智能体，已有与新建智能体都会自动建立独立心智库

## 安装

解压 `dist/Philotes-0.1-build3-macOS.zip`，把 `Philotes.app` 拖进“应用程序”目录。当前构建使用 Apple Development 签名；可在本机运行，其他 Mac 上可能需要在“系统设置 → 隐私与安全性”中手动允许。面向任意 Mac 免警告分发仍需 Developer ID Application 证书和 Apple 公证。

## 发布节奏

日常开发只更新代码、测试和本地构建，不自动提升版本或重做安装包。只有主人明确要求“同步到 Release”时，才统一执行 Archive、签名、导出和 `dist/` 更新。

## 相关长期记忆

- [Philotes 项目页](/Users/shironotsu/Documents/Codex/2026-10-11/n/MemoryVault/01-项目/Philotes.md)
- [产品与设计决策](/Users/shironotsu/Documents/Codex/2026-10-11/n/MemoryVault/02-决策/产品与设计决策.md)

## 边界

- 不默认录屏、不静默读取其他应用；屏幕快照和 OCR 只在单次确认后发生。
- 不把亲密关系变成分数、排名或 KPI。
- 敏感记忆只在用户主动提起时出现。
- API Key、Token、密码等凭据永不进入项目或记忆库。

## 本地运行

在 Xcode 打开 `Philotes.xcodeproj`，选择 `My Mac` 后运行。命令行需要 Xcode 提供 SwiftUI 宏插件，因此在受限 shell 中无法构成完整运行验收。

本地 Debug 构建使用 `app/PhilotesCodeSigning.requirements` 提供稳定的指定要求。这样每次重新构建后，macOS Keychain 仍把这版 Philotes 视作同一个应用，不会因为 CDHash 改变而拒绝读取旧记录。Keychain 服务已迁移到 `com.shironotsu.philotes.custom-api.v2`；如果早期构建留下的旧记录无法访问，Philotes 会安全地视为空记录，重新输入一次 API Key 即可。

API 客户端可用离线回归脚本验证，不需要真实密钥：

```bash
swiftc \
  -module-cache-path /tmp/philotes-swift-module-cache \
  app/Sources/APISettings.swift \
  app/Sources/CustomAPIClient.swift \
  scripts/test_stream_client.swift \
  -o /tmp/philotes-api-smoke-test
/tmp/philotes-api-smoke-test
```

```bash
swiftc \
  -module-cache-path /tmp/philotes-swift-module-cache \
  app/Sources/APISettings.swift \
  app/Sources/CustomAPIClient.swift \
  app/Sources/MacControl.swift \
  app/Sources/AgentMemoryVault.swift \
  app/Sources/DatabaseStore.swift \
  scripts/test_agent_api_store.swift \
  -lsqlite3 \
  -o /tmp/philotes-agent-api-store-test
/tmp/philotes-agent-api-store-test
```

```bash
swiftc \
  -module-cache-path /tmp/philotes-swift-module-cache \
  app/Sources/APISettings.swift \
  app/Sources/CustomAPIClient.swift \
  app/Sources/MacControl.swift \
  app/Sources/AgentMemoryVault.swift \
  app/Sources/DatabaseStore.swift \
  scripts/test_new_agent_vault.swift \
  -lsqlite3 \
  -o /tmp/philotes-new-agent-vault-test
/tmp/philotes-new-agent-vault-test
```

```bash
swiftc \
  -module-cache-path /tmp/philotes-swift-module-cache \
  app/Sources/APISettings.swift \
  app/Sources/CustomAPIClient.swift \
  app/Sources/MacControl.swift \
  app/Sources/AgentMemoryVault.swift \
  app/Sources/ChatMemoryImportService.swift \
  app/Sources/DatabaseStore.swift \
  scripts/test_memory_import.swift \
  -lsqlite3 \
  -o /tmp/philotes-memory-import-test
/tmp/philotes-memory-import-test
```
