# scripts

放原型、数据迁移、记忆索引测试和开发辅助脚本。

任何脚本都不得读取或写入 API Key、Token、密码等凭据。

- `test_stream_client.swift`：用 `URLProtocol` 离线验证 API 地址、SSE、流式工具调用、任务规划器、Safari 正文读取脚本、AppleScript/键鼠/屏幕参数映射、工具结果回传、失败重试批次重放、一键授权偏好、非流式兜底和错误脱敏。
- `test_agent_api_store.swift`：用临时 SQLite 数据库和人格目录验证智能体 API、独立 Markdown 心智库、相关性读取、日记追加、自动记忆抽取与凭据脱敏。
- `test_new_agent_vault.swift`：在隔离的临时用户目录中实际调用创建智能体流程，验证 Release 首启无演示智能体，并确认新智能体自动生成完整心智库。
- `test_memory_import.swift`：验证聊天记录 JSON 解析、人格/记忆分类、敏感信息拒绝、自我连续性人格和第一人称唤醒提示词。
- `test_group_chat.swift`：验证群聊 @ 解析、最长名字优先、提及顺序、房间与消息持久化、房间头像设置、邀请/移出成员、房间删除和共享日记记忆。
- `mock_chat_server.py`：本机 OpenAI-compatible 调试服务；支持流式与非流式响应，不校验密钥。
