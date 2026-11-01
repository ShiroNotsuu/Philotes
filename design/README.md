# design

放 Philotes 的界面草图、关系面板布局、记忆闪回卡片和视觉参考。

第一原则：关系可见，但不被打分。

## 品牌图标

- `AppIcon.icon`：应用图标的正式源文件，由 Icon Composer 创建，使用 Design Generation 27 的原生 Liquid Glass、系统外观和阴影。
- `appicon-master.png`：由原始角色图生成的 1024px 预览/兼容母版，不再作为应用的正式 AppIcon。
- `brandmark-master.png`：同一角色的紧凑圆角版本，用于侧栏顶部等应用内品牌标识。
- 应用图标源位于 `app/AppIcon.icon/`。
- 侧栏顶部品牌标识复用同一张图，位于 `app/Assets.xcassets/PhilotesBrandMark.imageset/`。
- `scripts/make_app_icon.swift` 支持 `app` 与 `brand` 两种模式，用于从原始方图生成应用图标和紧凑品牌图。
