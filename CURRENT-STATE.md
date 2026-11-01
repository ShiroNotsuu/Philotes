# Philotes · 当前交接

更新：2026-10-31

## 定位

桌面级人机陪伴软件。不是全能助手，也不是监控器；核心体验是“在当前话题自然相关时，想起一件有来源的小事”。

## 当前进度

- macOS 原生 SwiftUI 原型已跑通，工程在 `work/Philotes/Philotes.xcodeproj`。
- 信息架构：星海、智能体、状态、设置。
- 星海是统一二维记忆图谱：智能体作为恒星，记忆节点连接代理；支持缩放，回弹问题已修正。
- 每个智能体有自己的名称、Emoji/图片头像、人格、API 配置、SQLite 数据与独立 Markdown 心智库。
- 已接入 DeepSeek / OpenAI-compatible API、SSE 流式回复、Keychain API Key、人格档案和聊天记忆导入。
- 右下角悬浮聊天窗可展开为整页对话；关系面板可见但不做亲密度/KPI。
- Mac 操作已支持应用打开、网页、AppleScript、键鼠、单次屏幕快照/OCR 等确认式动作；不支持静默自动操作。
- 最近记录显示可编译、可运行；本轮不要重新跑完整 Release。

## 下一步

1. 给“记忆闪回”补上真实检索与来源展示，先做关键词 + 时间，再考虑语义索引。
2. 打磨关系面板，避免数字化和监控感。
3. 补工具调用的回归测试与撤销路径。
4. 评估真实模型对话、失败恢复和低内存表现。

## 工作边界

- 日常只改代码、跑离线测试和本地 Debug 构建；不要自动 Archive、签名、导出 ZIP/DMG 或更新 `dist/`。
- 不主动发 Telegram/Discord。
- 不读取或入库 API Key、Token、Cookie、密码；Key 只走 Keychain。
- 先读本文件，不要为了接手而完整加载 `MemoryVault/01-项目/Philotes.md` 或整份长 README；需要具体细节时再定点打开对应章节。
