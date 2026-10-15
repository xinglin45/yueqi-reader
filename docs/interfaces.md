# 来源与同步接口草案

本文件定义实现任务的输入边界，不是已运行的 API/OpenAPI，也不固定 Dart/Java 类签名。所有外部示例地址在 [data-sources.md](data-sources.md)中待核验。

## 公共值对象

- PageRequest：cursor/limit；PageResult：items/next_cursor/has_more，拒绝无限返回。
- ContentIdentity：app_kind(novel/comic)、source_id、source_item_id、content_key、revision。
- Language：统一 BCP 47 标签 zh、zh-Hans、zh-Hant、ja、ko，另保留 source_language；原文/译文标签分开。
- ContentRating：raw_rating、level(general/mature/restricted/unknown/prohibited)、min_age、region、evidence、policy_version。
- AccessPolicy：login_required、age_required、cache_allowed、redistribution、commercial_use、attribution、expires_at、verification_status；未核验权限为 unknown，不是 true。
- SourceDescriptor：id、kind、adapter_version、rule_hash、domains、capabilities、permissions、languages、rating_scope、verification_record。
- SourceError：unsupported_rule、auth_required、age_restricted、rate_limited、not_found、timeout、network、parse、rights_unverified；包含可重试属性与 retry_after，不泄露凭据。

## 小说来源 BookSource

| 方法 | 输入 | 输出 |
|---|---|---|
| search | keyword、languages、rating_filter、PageRequest | PageResult<BookSummary> |
| getBook | source_item_id | BookDetail（作者、简介、语言、分级、许可） |
| getChapters | source_item_id、PageRequest | PageResult<ChapterDescriptor> |
| getChapterContent | chapter_id、已获准访问上下文 | ChapterContent(text/html、revision、资源与署名) |
| checkUpdates | 已知章节/版本 | 更新摘要或 unsupported capability |

没有逐章目录的 EPUB/OPDS 来源允许暴露 acquisition/document 能力，由本地阅读器解析文档，不能捏造远端章节接口。HTML 需净化；下载链接不表示允许再分发。

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
