# 小说 App：macOS 优先的四端代码布局

日期：2026-10-15。状态：目录与技术方案；没有生成 Flutter/Java 构建文件，接口名称是设计草案。适用 [macOS 开发方案](novel-macos-plan.md)。

## 1. 仓库与交付边界

根仓库 yueqi-reader，项目显示名“阅读软件”。小说与漫画是两个独立 App，不按操作系统或开发/生产环境复制仓库。macOS 是首个交付端；Windows、Android、iOS 保留相同领域模型与用例。

现有根目录保持：

- 小说/client：小说唯一 Flutter 客户端，将来包含四端工程。
- 小说/server：小说领域模块，云同步开发时装配到共享单体。
- 漫画/client、漫画/server：保留独立产品骨架，本批不开发漫画阅读功能。
- packages/：仅确有跨产品复用价值的接口/基础包；小说专属排版仍属于小说产品。
- services/reader_platform：共享服务启动入口与账号/设备/同步/分级模块，R1-A 不部署。
- infra/environments/dev、test、prod：环境配置与部署说明，同一代码版本按环境运行。
- docs/：需求、架构、数据源、任务、验收、技术决策。
- fixtures/：自产/许可有记录的文本、EPUB、模拟 API；不提交私人书库。

## 2. 初始化后的目标结构

以下 client 内部目录是 **MAC-01/02 初始化时的目标**，目前未创建为虚假工程。

```text
小说/client/
├── lib/
│   ├── app/                      # 装配、路由、主题、生命周期
│   ├── features/
│   │   ├── library/              # 书架/合集/元数据
│   │   ├── importer/             # 文件导入与目录/编码预览
│   │   ├── reader/               # TXT/EPUB 阅读与排版
│   │   ├── search/               # 本书/书库检索
│   │   ├── annotations/          # 书签/高亮/笔记
│   │   ├── speech/               # 听书队列/进度/状态
│   │   ├── sources/              # 来源管理与在线搜索
│   │   ├── downloads/            # 缓存/下载/追更
│   │   ├── backup/               # 导出/恢复
│   │   ├── statistics/           # 本地阅读统计
│   │   └── settings/             # 偏好/隐私/快捷键
│   └── infrastructure/           # App 级组合与具体实现装配
├── android/                      # 平台宿主与权限/签名
├── ios/
├── windows/
├── macos/
├── assets/
├── test/
├── integration_test/
└── pubspec.yaml
```

每个 feature 按需分 presentation / application / domain / infrastructure；不为小功能机械建立空层。domain 不依赖 Flutter widget、数据库驱动、平台通道；UI 经用例调用 Repository/Service。跨 feature 通过公开接口协作，避免直接读取对方的数据实现。

英文 Dart 包名使用 novel_app，Java 模块标识 reader-novel。中文目录用于产品归类；初始化时真实验证 Flutter、Java 聚合构建和 CI 的中文路径行为。若插件工具有证据表明不支持，另写路径迁移决策，不平行维护两份代码。

## 3. 可共享包

| 目录 | 职责 | 不承担的内容 |
|---|---|---|
| packages/reader_core | 稳定 ID、语言、分级、通用结果/错误与分页 | 小说排版和任一平台 UI |
| packages/reader_storage | SQLite/迁移/文件与缓存接口基础，独立 App 分库 | 共享两 App 的实体表/缓存目录 |
| packages/reader_ui | 通用主题与基础交互/可访问性组件 | 整套小说/漫画阅读界面 |
| packages/platform_services | 文件授权、安全存储、系统语音、窗口/系统集成的接口及适配边界 | 平台差异直接侵入业务用例 |
| packages/reader_sync | 稳定协议、outbox/重试/冲突客户端，R2 再实现联网 | 来源凭据、正文/图片同步 |
| packages/novel_sources | BookSource、REST/OPDS/有限规则适配、能力/许可模型 | 任意脚本执行或漫画 APK |
| packages/comic_sources | 独立漫画接口与适配，保留后续 | 小说正文解析 |

platform_services 当前只有说明文件。初始化后应区分纯接口与具体 Flutter 插件/平台实现，允许使用成熟插件，不要求自写全部原生绑定。共享接口先收敛最小能力，避免为尚未开发的平台编写假实现并报告成功。

## 4. 平台端口与降级

| 端口 | macOS 首批要求 | 未来端与失败处理 |
|---|---|---|
| FileAccess | 系统文件/目录选择、拖放、托管副本、引用模式权限书签 | Windows 文件权限、Android 文档访问、iOS 沙盒导入分别适配；拒绝权限可重选 |
| SecureStore | 系统安全存储；不在 SQLite 明文存 Token | 各系统安全存储，来源/账号命名空间隔离 |
| SpeechService | 系统实际语音列表、队列、暂停/继续、范围回调、缺失语音提示 | 其他系统分别验证能力；不能实现的回调显式返回 unsupported |
| WindowIntegration | 菜单、快捷键、焦点、全屏、窗口尺寸/位置 | 手机布局/生命周期用相应能力；单纯忽略平台操作时应有明确能力标记 |
| TaskLifecycle | 前台阅读优先、任务取消、睡眠/恢复、持久队列 | 手机后台限制另定，不假定始终可下载/追更 |
| UserNotification | 用户选择启用、本地任务完成提示且不泄露成人内容 | 系统权限受控，拒绝通知不影响阅读 |
| PlatformInfo | 平台能力/架构/应用数据目录 | 不根据绝对路径或机器名推测能力 |

适配器注册由组合入口完成，禁止 UI 到处散布平台判断。用户可见的功能开关由能力集驱动；如系统没有某语言语音，只隐藏/解释该语音，不让整个阅读功能失败。

## 5. SQLite 与文件模型

小说 App 独立 SQLite；阅读模型从第一版可迁移，不需要为了预留同步先部署 Java。

| 实体 | 关键字段/不变约束 |
|---|---|
| book / book_asset | 稳定 book_id、格式、来源身份、内容 hash/revision、语言/原始分级；文件引用另存 |
| import_job | 操作 ID、文件队列、进度、编码选择、错误/取消、已提交条目 |
| chapter / text_block | 文档 spine/章节身份、顺序、原始文本偏移/段落、目录规则版本 |
| reading_position | book_id、revision、锚点类型/值、上下文、历史返回位置；不使用屏幕页码 |
| annotation | annotation_id、范围锚点、quote/prefix/suffix、笔记/标签、修订与删除墓碑 |
| speech_session | 段/句位置、队列 generation、语音设置、听书单独进度、定时停止 |
| search_state | 索引版本、分词策略、待建/完成/失败、源修订，支持取消与重建 |
| collection / membership | 合集、标签、排序与书籍关系 |
| source_config / access_ref | 能力/域名/版本/许可状态；凭据只保存安全存储引用 |
| download_job / cache_entry | 已校验分片、资源版本、quota、offline_pinned、临时与最终路径 |
| backup_manifest | schema/app/内容版本、文件 hash、导出范围、恢复验证结果 |
| reading_session / preferences | 本地统计、空闲边界、全局/单书偏好 |
| change_log / sync_metadata | 稳定操作 ID、实体修订、墓碑；R1 只设计持久变更边界，联网 outbox R2 完成 |

TXT：统一文本规范化版本与偏移单位（如 Unicode code point/UTF-16 必须选择并记录），遇 emoji、组合字符、中日韩标点需验证跨端一致。显示层简繁/替换不能改变原始锚点。

EPUB：CFI 或引擎稳定锚点；选引擎时必须验证文本选择、搜索、朗读回调与锚点互通。原书变更使用 content_revision 区分，恢复失败保留上下文与用户选择，不让错误锚点覆盖已知位置。

文件路径只属于本机 asset locator。跨端同步 book_id/身份映射与内容锚点；不把绝对路径或安全范围书签上传到服务端。

## 6. 任务与恢复模型

- 导入、目录解析、全文索引、下载、备份采用有界队列；状态为 queued/running/paused/failed/cancelled/completed，按任务类型支持子集。
- SQLite 事务与文件临时写入分清：原子替换文件后登记完整状态，崩溃恢复时清理孤立临时文件/修复索引。
- 不把失败任务自动当作成功；重试操作幂等，取消后停止 UI 更新与后台 I/O。
- 阅读位置与笔记优先写入；统计可批量写。开始迁移前备份，迁移失败保留旧库并提供恢复入口。
- 全文索引与普通缓存均可重建；用户导入书籍、固定下载与笔记不可因普通清理被删除。
- 同一数据库先采用单写者/事务协调；多窗口/多实例不在首批，若操作系统重复打开则转交已有实例或明确拒绝并避免双写。

## 7. 技术选择与验证闸门

本轮不锁定精确库版本，不能把候选包的宣传当四端验证。MAC-01/06/12 需要记录：

1. Flutter/Dart 与当前 Xcode/macOS/CPU 架构；Windows、Android、iOS 工程入口能生成但尚未验证须标记。
2. 状态管理/路由/SQLite 方案的真实四端支持与许可证；不把插件仅支持 Android 的能力暴露为全端通用。
3. EPUB 引擎小样：目录、图片、样式、分页/滚动、选字/笔记、CFI/位置、全文搜索、TTS取文、恶意资源限制、大书内存。
4. 中日韩搜索：分词/子串策略、索引大小/建索引时间/命中精度；仅 FTS 表存在不算通过。
5. TTS：实际安装语音、是否离线、长时播放、句段回调、暂停/切书/休眠、耳机断开。
6. 文件引用：权限/书签重启恢复、移动/删除后重新关联、不同架构打包的权限差异。
7. 选定 SDK 后确认最低系统和 CPU 发行范围；当前不承诺 Intel 支持或 universal 包。

失败时先做实测与替代方案，更新能力矩阵和任务状态；不能为了保持原方案承诺绕过平台安全或悄悄丢功能。

## 8. CI、环境与版本规划

- 本轮没有可执行应用，暂不添加宣称通过的 Flutter CI 或构建徽章。MAC-01 建立实际工程后再启用格式/静态分析/测试工作流。
- macOS runner 构建/验证 macOS，Windows runner 验证 Windows，Android 和 iOS 按所需工具链分别配置；iOS/macOS 签名证书由安全环境提供，不提交。
- 路径触发：小说/client 或 novel_sources → 小说检查；reader_core/storage/ui/platform_services → 两 App 相关检查；共享服务或领域 server → 单体集成检查。
- R1 版本可使用小说独立标签，例如 novel-v0.1.0；共享服务和漫画以后各有独立版本，不要求每次一起发布。
- dev/test/prod 改配置，不复制源码/业务分支。真实 API/书源登录/签名信息不放 Flutter 构建常量或仓库；Flutter 客户端无法保守服务器秘密。
- .app/DMG 等构建产物不放 Git 源码，验证后由版本化发布产物保存；本轮只推送目录、上下文和方案。
- 自用先交付当前 Mac 可安装验证的包与说明；公开分发再核验签名/公证/渠道。未获授权不自动发布 Release 或购买证书。

## 9. 后续四端与后端迁移路径

1. macOS R1-A 稳定本地使用，R1-B 在许可通过后接入联网增强。
2. 将小说领域/存储/来源/锚点的无平台测试用于 Windows/Android/iOS。
3. 各端实现/验证平台端口和布局，不复制小说业务规则；逐端形成构建、安装、文件、TTS、生命周期证据。
4. 用户需要多端同步时再实现 Spring Boot 共享身份/设备/同步，MySQL持久化，Redis按需。
5. 服务端同步书架/锚点/笔记/非敏感设置；正文、图片、来源凭据和本机文件定位信息默认不上传。并发/删除/重试遵守现有 [architecture.md](architecture.md) 与 [interfaces.md](interfaces.md)。
6. 漫画以后复用基础接口，保持独立数据/阅读引擎；本批 macOS 小说交付不等待漫画工程实现。

官方技术参考见 [macOS 方案的技术依据](novel-macos-plan.md#9-官方技术依据与核验范围)。
