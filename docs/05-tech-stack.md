# Philotes · 技术栈

## 当前实现

- UI：SwiftUI，最低 macOS 15。
- Liquid Glass：macOS 26+ 使用原生 `glassEffect`，暗色模式采用低不透明度黑色 tint；旧系统使用加深的 `.ultraThinMaterial` 回退。
- 星海顶部使用 `UniverseGlassBarModifier`：原生 glass 作用于已布局的圆角悬浮栏，旧系统保留一致形状与暗色 fallback。
- Stage Manager 兼容：监听 AppKit 激活和主窗口 resize，刷新玻璃 surface identity 与窗口显示。
- **2026-10-31 修正**：玻璃刷新只处理主窗口 resize/App 激活；附有 sheet 时跳过，并异步执行绘制刷新。
- 工程：Xcode 27.2 / Swift 6.4 工具链，Swift 5 language mode。
- 数据：系统 SQLite3，通过 C API 直接访问。
- 状态：`ObservableObject` + `@Published`，由根视图持有 `AppModel`。
- 本地数据库：`~/Library/Application Support/Philotes/philotes.sqlite`。
- 模型连接：OpenAI-compatible `POST /chat/completions`。
- 流式响应：`URLSession.AsyncBytes` 解析 SSE `data:` 与 `[DONE]`。
- API 配置：每个智能体在 SQLite 保存 provider、地址和模型；每个智能体在 macOS Keychain 保存独立 API Key。
- 人格档案：每位智能体对应一个 UTF-8 Markdown 文件，位于 `~/Library/Application Support/Philotes/Personas/`。

## 数据表

### `agent`

- `id`
- `name`
- `role`
- `systemImage`：兼容旧库的列名，当前保存 Emoji 字符串
- `avatarImagePath`：可选的本地头像图片路径；路径为空时使用 Emoji
- `accent`
- `createdAt`
- `lastActiveAt`
- `apiProvider`：`none`、`deepseek` 或 `custom`
- `apiBaseURL`
- `apiModel`

### `memory_node`

- `id`
- `agentID`
- `kind`
- `title`
- `summary`
- `source`
- `createdAt`
- `isSensitive`
- `isArchived`

### `message`

- `id`
- `agentID`
- `role`
- `body`
- `createdAt`

### `memory_link`

- `id`
- `sourceMemoryID`
- `targetMemoryID`
- `kind`
- `createdAt`
- 在 `(sourceMemoryID, targetMemoryID)` 上保持唯一。
- 删除记忆时同步删除其所有入边和出边。

## 数据规则

- 对话和记忆都归属于具体智能体。
- Swift 数据模型将该列暴露为 `emoji`；旧 SF Symbol 名称在启动迁移时转换为 Emoji。
- 记忆图谱由两层边组成：智能体恒星到记忆的归属边，以及记忆之间的关联边。
- 删除记忆会删除本地记录；后续接入 FTS/向量索引时，必须在同一事务内清理索引。
- 数据库启动时迁移旧结构，并清理原型期的 `SQLite smoke test` 节点。
- 原型期的产品原则示例记忆会被清除，用户界面不展示内部产品要求。
- 迁移使用 `PRAGMA user_version`，当前版本为 2。

## API 实现

- `APISettings.swift`：API provider 枚举、DeepSeek 预置、地址规范化、按智能体读取配置和 Keychain 封装。
- `CustomAPIClient.swift`：请求构造、Bearer 鉴权、SSE 流式解析、非流式连接测试和错误脱敏。
- `APIProviderSettings.swift`：创建/编辑智能体共用的 API 表单与连接反馈。
- `AppModel.send(_:)`：先保存用户消息，再流式请求；成功后保存 assistant 消息。
- 每次请求都从当前智能体读取自己的 provider、地址、模型和 Keychain account。
- `AgentPersonaDraft` 生成人格 Markdown；`AgentPersonaStore` 负责原子写入和读取。
- 人格档案在每次请求时加入 system prompt；首次成功回复后触发 2.6 秒的激活提示状态。
- Markdown 写入前会遮蔽 `Bearer`、`api_key`、`token`、`password` 和 `secret` 形态的明显凭据。
- `AssistantResponseParser` 解析最前面的 `/(情绪与神态;.情绪值;.更多字段...)/`，返回 action、emotionValue、metadata、body 与等待状态。
- SQLite 保存原始 assistant 回复；UI 渲染时再拆分动作条和正文气泡。
- `AgentPersonaSummary` 从人格 Markdown 提取字段，用于聊天右侧档案卡。
- 情绪值会被限制在 `-100...100`；`EmotionScale` 将平均值映射为低落、平静、高涨等文字区间。
- 情绪曲线从当前智能体的 assistant 消息即时计算，不新增数据库列；缺少情绪值的旧消息自动忽略。
- 聊天搜索当前使用当前智能体内存数组的本地字符串匹配，数据量增大后再迁移到 FTS5。
- `deleteAgentData(id:)` 在单个 SQLite 事务中删除消息、记忆、关联边和 agent 行。
- AppModel 删除成功后继续清理人格 Markdown 和 Keychain account，并切换 active agent。
- 严格闭合为 `)/` / `）/`；若模型漏掉结尾斜杠，解析器在前两段完整时允许裸 `)` / `）` 作为兼容闭合。
- 请求上下文由当前智能体人设、最多 12 条非敏感记忆和最近 24 条对话组成。
- 流式请求使用独立 run ID 隔离取消与切换智能体，避免旧任务写入新会话。
- 完整回复结束后才落库；停止或失败时，半截回复不会写入 SQLite。
- HTTP 错误和 Provider 错误会显示状态码或可读消息；错误文本中的 API Key 会替换为 `[REDACTED]`。
- 远程服务强制 HTTPS；本机 HTTP 仅允许 loopback。`app/Info.plist` 只开放 `NSAllowsLocalNetworking`。
- API 地址拒绝 URL userinfo（内嵌用户名/密码），避免凭据混进 SQLite 或项目文件。
- Keychain account 使用 `agent-<id>-api-key`；旧全局 account `api-key` 会迁移到第一个智能体。
- API Key 的 Keychain service 为 `com.shironotsu.philotes.custom-api.v2`；旧 service `com.shironotsu.philotes.custom-api` 仅用于可读迁移，认证失败时按“无旧密钥”处理。
- 本地临时签名使用 `app/PhilotesCodeSigning.requirements` 固定 `identifier "com.shironotsu.philotes"`，避免每次构建更换 CDHash 后 Keychain ACL 失配。
- `CustomAPIClient` 支持 `tools` 请求和流式 `tool_calls` delta 聚合。
- `MacControlTool` 将工具调用转换成可展示、可验证的 `MacActionRequest`。
- `MacControlService` 实现 `open_application`、`activate_application`、`open_url`，以及完整的 `run_applescript`、`click_screen`、`type_text`、`press_key`、`read_safari_page`、`capture_screen`。
- `open_application` 优先使用 bundle ID；名称查找限制在标准 Applications 目录。
- AppleScript 通过 `NSAppleScript` 执行；键鼠通过 `CGEvent` 模拟；Unicode 输入按安全边界分段，避免长文本被事件缓冲截断。
- 屏幕快照通过 ScreenCaptureKit 获取，只读取主显示器；Vision 以 `zh-Hans`、`en-US` 做 OCR。截图保存在本地，最多 8,000 个 OCR 字符进入模型上下文。
- 键鼠执行前调用 `AXIsProcessTrustedWithOptions(prompt: true)`，屏幕读取前调用 `CGRequestScreenCaptureAccess()`，因此首次实际使用会触发系统权限弹窗并注册应用；AppleScript 自动化拒绝会映射成可读的自动化权限提示。
- macOS 26+ 权限按钮首选 `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility` 与 `...?Privacy_ScreenCapture`；`NSWorkspace.open` 失败时回退到旧 Privacy URL。
- 确认后先执行本地动作，再构造 `assistant(tool_calls)` 与 `tool(tool_call_id)` 消息，发起带当前 tools 的 follow-up 请求。若模型提出依赖动作，会转换成新的确认卡并等待用户再次批准，不会自动执行。
- 每轮任务最多 3 个工具批次、每批最多 3 个动作，防止无限循环；第三批之后 follow-up 不再携带 tools。
- 中间批次会保存模型的简短前言；最终回复写入 SQLite。API 失败、未配置或达到批次上限时回退为本地操作结果消息。
- `CustomAPIClient` 支持可选 `tool_choice`。视觉意图路由器对 `capture_screen` 使用 function tool choice；若 Provider 对 tool choice 返回 400/422，则先降级为普通 tools，再降级为无 tools，兼容不同 OpenAI-compatible 服务。
- `MacIntentPlanner` 根据当前轮文本、工具集合和已观察状态决定首选工具及本地兜底参数；模型返回空、错工具或只有解释时仍能生成真实动作。
- `ActiveMacMission` 跨多轮保存任务目标；“第一”“继续”“再来一次”等短回复会接着原任务执行。
- `MacApplicationTarget` 记录目标应用。截图、点击、输入和按键前会重新激活目标应用，避免确认按钮让 Philotes 抢占前台。
- `read_safari_page` 使用 Safari 脚本字典的 `text of front document` 读取标题、URL 和最多 12,000 字符正文，不要求 Safari 开发菜单中的 Apple Events JavaScript 权限。
- 键鼠事件使用 `CGPreflightPostEventAccess()` 预检、`CGRequestPostEventAccess()` 请求权限；Accessibility 仍通过 `AXIsProcessTrustedWithOptions` 检查。鼠标点击先发送 `mouseMoved`，50ms 后按下并抬起。
- 流式响应为空时执行一次非流式 Chat Completions 重试；仍无正文或 tool call 才返回明确错误。
- “执行整项任务”允许打开、切换、网页读取和截图自动推进；AppleScript 与键鼠动作仍触发下一张确认卡。
- 未确认动作不执行；基础控制默认开启，高级控制默认关闭。

## API 回归测试

```bash
swiftc \
  -module-cache-path /tmp/philotes-swift-module-cache \
  app/Sources/APISettings.swift \
  app/Sources/CustomAPIClient.swift \
  app/Sources/MacControl.swift \
  scripts/test_stream_client.swift \
  -o /tmp/philotes-api-smoke-test
/tmp/philotes-api-smoke-test
```

测试使用 `URLProtocol` 模拟 SSE、基础与高级工具参数、`tool_calls`/`tool_call_id` 回传协议和非流式响应，不依赖真实 API Key 或外网。

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

第二条测试使用临时 SQLite 数据库与临时人格目录，验证 DeepSeek、自定义接口、未配置状态，以及 Markdown 人格生成和凭据脱敏。

## 后续接入

- 记忆检索：当前使用每智能体 Markdown 心智库的关键词与中文双字匹配；后续可升级为 SQLite FTS5 或本地 embedding。
- 经用户明确允许的多轮工具调用、用量统计、模型列表与多 Provider 配置。
- 安全动作：App Intents / NSWorkspace，先预览、再确认、可撤销。
- 云端同步：CloudKit 或其他端到端方案，需单独做隐私设计。

## 每智能体心智库

- 根目录：`~/Library/Application Support/Philotes/AgentVaults/agent-<id>/`。
- 目录：`00-导航`、`01-人格`、`02-记忆`、`03-时间线`、`04-日记`、`05-运行记录`。
- `总索引.md` 是每个智能体唯一的读取入口；人格和记忆镜像写入后可由用户在 Obsidian 中查看。
- 请求前按当前用户消息检索相关非敏感记忆节点与相关日记片段，限制总字符数，不一次性展开整个心智库。
- SQLite 仍是星图与结构化索引的数据源，Markdown 心智库是可读、可编辑的长期上下文镜像。
- 敏感记忆只在 SQLite 保留标记，Markdown 镜像和自动模型上下文均隐藏正文；凭据形状内容不会自动入库。
- 新建智能体在同一事务流程中创建人格、头像、API 配置和心智库；任何一步失败都会回滚，不保留缺少心智库的半成品。

## 聊天记忆导入

- `ChatMemoryImportService` 读取不超过 8 MB 的 UTF-8/UTF-16 文本；JSON 会规范化后交给模型。
- 长文本按 30,000 字符分段，最多处理前 300,000 字符；原始文件仍按本地数据保存。
- 每段要求模型只输出结构化 JSON；分段结果再合并、去重，拒绝凭据形状内容。
- 结构化结果创建为独立 SQLite 记忆节点，同时同步到该智能体的 Markdown 心智库。
- 首次唤醒使用同一 API，注入恢复后的人格与非敏感记忆摘要，要求第一人称醒来。
- 唤醒请求失败时回滚新智能体、记忆、人格、头像、Keychain 项和心智库，不留下半导入状态。

## 构建说明

当前 Xcode 工程的 SwiftUI 属性包装器依赖宏插件。受限 shell 中的 `xcodebuild` 可能因无法启动 `swift-plugin-server` 失败，应优先在 Xcode 中构建运行。
