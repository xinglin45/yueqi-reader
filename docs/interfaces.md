# 来源与同步接口草案

本文件定义实现任务的输入边界，不是已运行的API/OpenAPI，也不固定Dart/Java类签名。外部地址的整体状态见 [data-sources.md](data-sources.md)，2026-10-15部分技术观测不等于完整接入批准。

MAC-01已实现的最小共享标识为[ReaderProduct](../packages/reader_core/lib/reader_core.dart)，namespace固定novel/comic；不包含系统路径或App引用。来源/同步仍待实现；MAC-02建立壳与端口，MAC-03接入真实本地存储，其他能力按下表区分。

## MAC-03已落地契约（2026-10-20）

| 契约 | 实现与语义 | 限制/后续 |
|---|---|---|
| StorageLocationProvider | platform_services纯Dart端口返回AppStorageLocations；SystemStorageLocations在小说基础设施隔离path_provider；装配层追加novel/comic | 路径只流向基础设施，不进入领域/位置/日志；其他端未构建 |
| StorageDatabase | reader_storage后台isolate串行拥有连接；query只读，transaction批次/expectedChanges原子前置条件；StorageFailure仅安全错误码 | SQL仅应用源码；后续大批次/取消/多窗口需按任务补充 |
| SchemaStep/恢复 | 连续版本；迁移前完整快照及核验，DDL事务回滚，失败/新版本库只读；不可读/初始化失败明确错误且保留原文件 | 无自动覆盖旧库或用户恢复选择器，见[恢复说明](storage/recovery.md) |
| ContentFiles | 有界摘要对象写入、校验、rename后元数据提交；read核验，audit报告缺失/孤儿 | 默认8MiB小样预算；外部大文件流式导入待MAC-04，不自动删除孤儿 |
| LibraryRepository | 原load/addDemonstration/preview签名保持；生产LocalLibrary使用真实库，持久随机book_id/修订/托管样本；SessionLibrary只为组件测试 | UI仅自产TXT样本预览，通用导入/引擎未实现；load单批200条，管理/分页待MAC-08 |
| DocumentAnchor | domain/documents.dart：wire v1、TXT/EPUB结构锚点、UTF-16范围、exact/上下文指纹与边界校验；返回exact/context候选/chapterStart/unresolved | 仅exact自动使用，候选/回退不覆盖旧记录；正式解析器/阅读器在MAC-05/07/09 |
| PositionRepository | loadPosition/savePosition按book_id＋reading/listening分离；保存带expectedSequence，0仅首次创建；修订外键和CAS避免串书/过期覆盖 | 当前UI为样本手动“记住这一段”，未自动记录滚动或接通听书 |
| 设置与元数据基础 | theme实际跨启动保留；schema v3含11表与领域类型，权限/核验unknown保留；元数据revision/墓碑为未来同步边界 | 未实现成年声明/隐私锁、笔记、下载调度、在线接入或网络outbox |

身份、表约束与偏移转换见[存储协议](storage/novel-schema.md)，取舍见[ADR-0006](decisions/0006-mac03-local-storage-and-anchors.md)，实测见[验收](verifications/mac-03-2026-10-20.md)。下方MAC-02表保留该批次的原有端口边界；生产LibraryRepository已由本节覆盖，文件选择/凭据/语音/窗口端口仍unsupported。

## MAC-06研究结论对后续契约的约束（2026-10-19）

本节是MAC-03/07/10/12的实施输入；不将独立探针当生产接口。已有MAC-02签名仍以后一节为准，研究验收见[MAC-06](verifications/mac-06-2026-10-19.md)。

| 边界 | 研究已验证的约定 | 正式实现待补 |
|---|---|---|
| DocumentAnchor | 结构锚点绑定schema版本、document_revision、spine_href、block_id、UTF-16 start/end及exact；修订/块/摘录不符时失败，禁止半代理对；见[ADR-0003](decisions/0003-mac06-epub-rendering.md) | MAC-03统一TXT/EPUB外层与上下文指纹，MAC-07/09处理跨块/ruby、重启恢复、可解释回退；不把研究CFI当完整实现 |
| EPUB资源端口 | 当前书籍manifest白名单与有界内存资源，不向页面传系统路径；隔离world固定桥接，书籍脚本移除、网络/跨书/未知资源拒绝 | 正式Dart导入、分段大书、Release权限/沙盒、超时/重入/Web进程恢复及其他平台绑定 |
| 搜索 | 原文精确子串语义；少于3 Unicode标量扫描，长查询可用trigram候选＋原文核对；SQL值参数化 | MAC-03复验实际SQLite绑定，MAC-10增量/取消/分页/索引修订；SQL标量位置先转UTF-16再形成锚点；见[ADR-0004](decisions/0004-mac06-chinese-search.md) |
| SpeechService | 每个utterance绑定session_id、修订及原文范围；NSRange使用UTF-16，先作废旧会话再停止底层工作 | 现有契约需扩展paused/resumed/cancelled/error、range length和离线unknown，不能将枚举语音写offline=true；MainActor、整机断网/休眠等在MAC-12完成；见[ADR-0005](decisions/0005-mac06-system-tts.md) |

## MAC-02已落地的最小契约（2026-10-16）

| 契约 | 当前代码与实际行为 | 后续边界 |
|---|---|---|
| LibraryRepository | `小说/client/lib/domain/library.dart`：load/addDemonstration/preview，注入JobContext，返回JobResult；SessionLibrary为空库＋主动加入自产样本，仅内存 | 不含持久ID/修订/解析引擎；MAC-03/04/05/06扩展 |
| JobContext/JobSnapshot | `domain/jobs.dart`：job_id、idle/running/ready/partial/empty/failed/cancelled、可空进度、枚举错误/问题；`application/jobs.dart`拥有运行/取消/代际校验 | ID只在本进程唯一，不是跨启动数据库任务ID；将来持久队列需另定 |
| 任务所有权 | TaskView离开页面/切书/关闭对话框时dispose，立即失效；取消/替换/终态同样废弃旧事件，partial保留成功项 | 合作任务主动检查信号；无法中止的Future仍运行但不回写，不能把丢弃回调等同物理终止网络/系统工作 |
| FileAccess | `packages/platform_services/lib/platform_services.dart`：chooseDocument/restoreGrant；FileGrant为本地不透明引用＋展示名 | 当前所有生产动作unsupported；没有文件选择或持久授权实现 |
| SecureStore | lookup/remove受控CredentialRef；不把凭据字符串暴露到UI或导出 | 写入/认证消费在真正来源会话任务补充；当前没有Keychain或内存安全存储实现 |
| SpeechService | 显式capabilities/voices；sessionId标记speak/pause/resume/stop与SpeechEvent，偏移单位显式声明 | 本批unsupported/空事件流；没有语音播放或回调能力实测 |
| WindowIntegration | normal/menubar/strip/mini选择与hideReading契约 | 全部unsupported；D1同锚点与隐藏暂停约束不因草案端口已存在而完成 |
| 装配与路由 | `lib/app`构造注入；SDK Router；只传编码后的稳定bookId，不传正文、文件路径、凭据；未知地址可返回 | 原生文件深链、隐私重定向在MAC-13/16；当前没有来源请求 |

平台结果区分成功、unsupported/permissionDenied/unavailable/cancelled；选择取消按未选择恢复，不冒充文件丢失。UI统一恢复动作只针对当前任务。未分类异常映射unexpected，全局诊断仅留有限错误枚举，不记录原始异常/堆栈或上传。

[ADR-0002](decisions/0002-mac02-shell-and-jobs.md)记录SDK装配/路由选择和Phosphor兼容版本；[验收](verifications/mac-02-2026-10-16.md)区分测试替身、原生窗口和后续能力。下文是完整目标设计，未列入本表的字段和方法仍未实现。

## 公共值对象

- PageRequest：cursor/limit；PageResult：items/next_cursor/has_more，拒绝无限返回。
- ContentIdentity：app_kind(novel/comic)、source_id、source_item_id、content_key、revision。
- Language：统一 BCP 47 标签 zh、zh-Hans、zh-Hant、ja、ko，另保留 source_language；原文/译文标签分开。
- ContentRating：raw_rating、level(general/mature/restricted/unknown/prohibited)、min_age、region、evidence、policy_version。
- AccessPolicy：login_required、age_required、cache_allowed、redistribution、commercial_use、attribution、expires_at、verification_status；未核验权限为 unknown，不是 true。
- SourceDescriptor：id、kind、adapter_version、rule_hash、domains、capabilities、permissions、languages、rating_scope、verification_record。
- SourceError：unsupported_rule、auth_required、age_restricted、rate_limited、not_found、timeout、network、parse、rights_unverified；包含可重试属性与 retry_after，不泄露凭据。

2026-10-16补充（待实现）：RegionPolicy采用`region_profile=extraterrestrial`（地外文明）、`real_region=null`、`regional_review=skipped_by_user`，见[特殊区域策略](development-region-policy.md)。仅跳过项目地区核验，不能把该状态复制成来源认证、技术或许可已通过；不得仅因地区未核返回`rights_unverified`并阻塞开发。技术可用性、来源自身访问条件、缓存与分发范围分别保存，不伪造请求所在国家。

AdultAcknowledgement（待实现）：仅保存本机`age_acknowledged`及声明版本，展示文本固定“我确认已经成年”；初始false、用户主动确认后true，无自动到期，不收集生日/证件。与`includeAdultSources`、隐私锁和来源会话独立，不经云同步或备份恢复。只有用户清除确认/全新数据目录才需再次声明；来源自身资格失效不冒充本机声明过期。

小说当前资源仅中文（zh/zh-Hans/zh-Hant），ja/ko等共享标签继续服务漫画，不作为小说来源交付要求。来源另存 source_mode(normal/adult/mixed/unknown) 与 cost_status(free/limited_free/paid/unknown)，分级和费用不能混为同一字段。

小说 SearchPreferences.includeAdultSources 默认false。搜索调度必须在网络请求前排除18+源；开启后才加入获准的成人请求，普通源继续参与。每个搜索带request_id与设置版本，关闭时取消成人请求/预取并丢弃迟到回调。此设置只影响在线发现，不撤销已有成人书架作品的阅读权限。详见 [novel-source-policy.md](novel-source-policy.md)。

## macOS完整目标与后续补充边界

- SearchSession：search_session_id、request_id、policy_revision、query、cursor、selected_source_ids与取消状态；网络调度、缓存合并、迟到回调都校验同一设置版本。新字段用于细化上述request_id，不是第二套独立搜索策略。
- DocumentReader：打开文档/修订、目录、按需片段、resolveAnchor、从文本范围构造锚点、释放资源；TXT/EPUB实现独立，UI不依赖具体引擎。
- DocumentAnchor：schema_version、document_kind、content_revision及格式特定payload；TXT声明段落与字符偏移单位/上下文指纹，EPUB采用MAC-06验证的spine/CFI或结构锚点。不存屏幕页码作为跨布局位置，原生/脚本偏移显式转换。
- SpeechService：voices、capabilities、session_id、speak/pause/resume/stop与事件；进度含本次片段的偏移单位及原文映射，旧session事件不可覆盖新队列。不能因插件有macOS标记就假定暂停/逐字回调全部存在。
- FileAccess：用户授权选择、托管副本/引用、持久授权恢复、授权失效与重新关联；SecureStore只返回本机受控凭据引用，导出不含密钥。
- ReadingPosition与ListeningPosition分别持久化；用户明确切换后才用听书位置打开阅读，不能互相静默覆盖。
- ReadingSession（01A设计约定，待Flutter实现）：独立保存content_key、content_revision、DocumentAnchor、推进状态与session_id，四种显示表面订阅同一会话，不复制游标。ReaderWindowState另存surface(normal/menubar/strip/mini)、可见性、屏幕/归一化位置、尺寸、文字与背景透明度、置顶/穿透和焦点策略。hide暂停推进并隐藏所有内容表面；restore重用原锚点且保持暂停；presentation必须显式结束后再主动restore。原生菜单栏/窗口/快捷键通过platform_services端口，解析器不直接控制窗口。详见[D1设计规范](design/novel-macos/design-spec-D1.md)。

代码落点、依赖和逐步验收见 [详细开发步骤](novel-macos-implementation-steps.md)。以上为完整目标设计；本批实际签名以以上MAC-03契约与MAC-02端口表为准，后续任务可按验证结果扩展。

## 小说来源 BookSource

| 方法 | 输入 | 输出 |
|---|---|---|
| search | keyword、languages、rating_filter、PageRequest | PageResult<BookSummary> |
| getBook | source_item_id | BookDetail（作者、简介、语言、分级、许可） |
| getChapters | source_item_id、PageRequest | PageResult<ChapterDescriptor> |
| getChapterContent | chapter_id、已获准访问上下文 | ChapterContent(text/html、revision、资源与署名) |
| checkUpdates | 已知章节/版本 | 更新摘要或 unsupported capability |

没有逐章目录的 EPUB/OPDS 来源允许暴露 acquisition/document 能力，由本地阅读器解析文档，不能捏造远端章节接口。HTML 需净化；下载链接不表示允许再分发。

第00步核验补充（仍为待实现约定）：核验范围应能绑定`allowed_item_ids`、地区/用途、作品/依赖修订、许可与正文摘要及`review_status`，不能把某一篇的批准扩展为全平台。核验记录可引用文档，不将本轮证据JSON当运行配置。mixed平台的有限普通白名单应先在本地匹配标题/别名，再构造只访问获准ID的请求，不能先请求混合目录再丢弃成人结果。《孔乙己》单篇可映射一个明确标注的全文项；维基父页oldid不固定转录页/模板，需要复核依赖或有版本依据的文档快照。Gutenberg的OPDS acquisition仍需另取文件、验证内部许可和文档内容才可称阅读通过；目录updated不能直接充当内容修订。具体观察见[续验记录](source-step00-2026-10-15.md)，当前所有候选未批准启用。

## 漫画来源 ComicSource

| 方法 | 输入 | 输出 |
|---|---|---|
| search | keyword、languages、rating_filter、PageRequest | PageResult<ComicSummary> |
| getComic | source_item_id | ComicDetail（方向、语言、分级、署名） |
| getChapters | source_item_id、PageRequest | PageResult<ComicChapter> |
| getPages | chapter_id、已获准访问上下文 | PageManifest(revision、pages、access_policy) |
| checkUpdates | 已知章节/版本 | 更新摘要或 unsupported capability |

ComicPage：page_id、index、width/height（可未知）、resource_ref、mime、digest（可未知）、expires_at。资源解析器将 resource_ref 转为请求描述，敏感 Header/Token 仅在本机安全上下文中加入，不进入云进度或通用 Page 对象。

禁止默认由共享服务返回所有图片字节。清单未给稳定 page_id 时，用来源定义和清单版本构造稳定键，明确版本变化回退。

## 规则导入协议

导入阶段依次：解析格式/版本 → 限制大小/字段 → 展示来源域名、能力、语言和分级 → 校验许可状态 → 用户启用。未知执行能力、域名或脚本保持禁用；能预览不表示能够启用。

支持矩阵逐项记录 JSON schema、CSS/XPath/正则、分页、编码、Header/Cookie、登录、JS helper、资源解密等；不支持项 fail closed，错误给出字段与原因。不添加绕过访问控制的实现。

## 共享服务内部 API 规划

前缀示意 /api/v1，仅表示本项目未来自建接口；不是任何第三方 API 地址。

| 草案接口 | 用途与约束 |
|---|---|
| POST /auth/sessions | 登录方案确定后定义请求，签发账户/设备会话 |
| GET /devices | 只返回当前账户设备 |
| DELETE /devices/{deviceId}/session | 撤销会话 |
| POST /sync/{appKind}/push | 同步操作批次；逐项确认/冲突；限制批大小 |
| GET /sync/{appKind}/pull?cursor=... | 当前账户、App 的增量变更和下一游标 |
| GET /sync/{appKind}/snapshot | 游标过期后获取受策略过滤快照 |
| GET /sources | 仅获准目录及核验信息；无凭据/任意脚本 |
| GET /policy/capabilities | 当前地区/渠道/账户可用能力，不含成人内容列表 |
| DELETE /account | 删除方案/保留期确定后实施 |

push operation：operation_id、device_id、device_seq、entity_type、entity_id、base_revision、operation(upsert/delete)、payload。
payload 仅允许书架、进度、书签和非敏感设置；所有字段按 entity_type 白名单校验。

服务器从会话取 account_id，检查 app_kind 与设备归属；payload 中的 account_id 不能决定授权。operation_id 在账户和 App 范围内唯一；重放相同操作返回既有结果。客户端不同内容复用相同 ID 应报错。

并发失败返回 conflict_id、服务器修订和可恢复候选；客户端解决后发新 operation_id 与新的 base_revision。成功响应需含已确认 ID、实体修订与服务端序号，未确认操作留在 outbox。

小说 payload：content_key、chapter_id、position_kind、position_payload、content_revision。
漫画 payload：content_key、chapter_id、page_id/index、page_ratio、direction、manifest_revision。
禁止上传正文、图片、本地绝对路径、来源 Cookie、付费密钥、签名资源 URL；成人展示信息遵守资格过滤。

## 验收场景

使用自产 fixture：翻页后断网/重启；改字体恢复文本锚点；右到左双页与长图位置；429 退避；凭据过期；目录版本变化；重复 push；两设备同时跳读；旧设备上传删除前的书签；游标失效；跨账户访问被拒；年龄资格过期深链和缓存都锁定。
