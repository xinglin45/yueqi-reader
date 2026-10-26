# 小说本地数据与位置协议 v1

日期：2026-10-26。数据库schema **v8**；DocumentAnchor wire schema **v1**，两者独立升级。代码源为[小说schema](../../小说/client/lib/infrastructure/storage/schema.dart)、[领域类型](../../小说/client/lib/domain/catalog.dart)、[锚点](../../小说/client/lib/domain/documents.dart)。实际SQLite导出的[DDL快照](novel-schema-v8.sql)供审阅，不代替源码迁移。

## 存放与表职责

系统Application Support/Cache由StorageLocationProvider提供；各自追加novel或comic。小说DB逻辑名novel.sqlite，正文在同一资料区objects/SHA256，缓存为独立缓存区；数据库只存相对资源href、摘要与受控引用。App私有路径不进领域、锚点、日志或未来同步。reader_storage只提供通用基础，不能依赖任一App。

| 表 / 模型 | 主身份与约束 | 当前使用 |
|---|---|---|
| books / BookSummary | 随机book_id；标题不唯一，中文语言与rating/evidence；row_revision和deleted墓碑 | 本机书架及自产样本 |
| documents / DocumentRevision（Edition） | id、book_id、digest、kind、parser_version；(digest,kind,parser_version)唯一；原始大小/类型/时间 | 托管TXT样本修订；同文件换解析器可保留旧修订 |
| chapters / ChapterRecord | (document_id,id)主键、ordinal唯一、spine_href | 样本、TXT解析目录与EPUB2/3 spine目录均已接入 |
| resources / ResourceRecord | (document_id,href)、摘要、类型、大小、cache_permission三态 | 样本文本为已知自产allowed；其他默认unknown |
| positions / StoredPosition | (book_id,channel)、document_id、anchor JSON、local_seq、更新时间；(book_id,document_id)复合外键 | 阅读/听书独立持久位置；样本/TXT/EPUB主动位置；自动进度待MAC-09 |
| annotations / AnnotationRecord | bookmark/highlight/note；关联书籍/修订；anchor、note、row_revision、deleted | schema/模型已定义；MAC-11产品用例待实现 |
| content_policy / ContentRating | book_id外键；原始/内部评级、最低年龄/来源地区/证据/策略/来源资格 | MAC-16门禁，unknown/prohibited不自动归普通；地区skipped_by_user |
| collections / CollectionRecord | collection/tag/adult；独立id、标签、revision/墓碑 | MAC-08合集/标签管理与固定normal/adult范围；MAC-16成人默认分组保留 |
| collection_books | 书籍与分组复合主键/外键 | MAC-08普通/成人各自的合集标签关系，批量替换不移除成人默认组 |
| source_bindings / SourceBinding | source_id＋source_item_id唯一；对应本地book_id、核验/缓存unknown、仅credential_ref、revision/墓碑 | 未来显式来源绑定，尚无真实接入 |
| jobs / StoredJob | 持久job_id、import/download、状态/进度/安全错误码/时间 | 任务模型基础；调度/恢复产品用例待MAC-04/21 |
| imports | document_id主外键；mode、仅本机grant_id、encoding、awaiting_parser | MAC-04导入索引，托管正文在objects；引用无永久副本 |
| settings | key白名单theme/text_scale；JSON值、row_revision | 深浅色实际持久；其余设置后续 |

row_revision仅本机元数据代际；updated_at是UTC epoch毫秒，不能作为未来跨设备唯一冲突顺序。后续MAC-25补服务修订/设备序号与协议，不创建空转outbox。删除有墓碑，MAC-08已开放可恢复的移出/托管副本回收及个人记录移除；没有永久清库入口。

## 原子边界与故障状态

SQLite事务涵盖书籍、修订、章节与资源引用；外部文件与SQL不属于同一原子事务。先完成受控文件，再提交引用，中断留下未引用对象；audit列出missing/orphaned，不自动回收。missing/corrupt对象明确报错，不用空正文替代。暂存写入失败只清理本次暂存；不会清除已有对象。

查询也经过同一后台连接。所有值绑定参数；SQL仅来自本项目源码，不将来源JSON/脚本拼成SQL。位置写采用expectedSequence比较更新，0只允许首次创建；事务影响行数不符返回conflict。metadata约束/外键错误整批回滚，后续写入仍可继续。

租约针对本机协作进程，不是安全边界；SQLite锁/约束仍为最终保障。未验证网络共享盘、物理断电或真实满盘，不将逻辑回滚测试扩大为这些环境已通过。

## DocumentAnchor

字段固定为schema_version=1、document_kind(txt/epub)、content_revision、chapter_id、spine_href、block_id、offset_unit=utf16_code_unit、start/end（左闭右开）、exact、prefix/suffix与context_sha256。exact最多512 UTF-16单元，上下文各16 Unicode标量，不保存整段正文作为位置。位置和标注均绑定文档修订，不用标题或屏幕页号。

- UTF-16 start/end允许空范围表示游标；拒绝半代理对。📖占2单元，e＋组合音标保持原序列。
- EPUB spine使用manifest内路径；TXT的块ID及章节来自明确解析器版本。MAC-05 TXT与MAC-07受控WebView已接入默认入口，完整排版/自动进度仍在MAC-09。
- 精确偏移与上下文一致→exact；同修订/同块中唯一上下文→context候选；找不到/歧义/修订变化→chapterStart或unresolved。候选/回退不覆盖数据库旧记录，UI应说明旧位置保留。
- SQLite instr返回1起的Unicode标量位置，转0起后通过scalarToUtf16；NSRange/JS直接按UTF-16，桥接数值先验证有限整数，不截断小数。

## 迁移兼容

内部交付含v1→v2→v3→v4→v5→v6序列；v4增加分级策略，迁移只对已知自产普通样本填notRequired，其余来源资格unknown。升级前先生成并核验独立SQLite快照；失败拒绝升级，DDL失败事务回滚。遇到未来版本只读打开、不降级；无法读取或首次初始化失败则显示启动错误，保留原文件。恢复流程见[恢复说明](recovery.md)。

生产入口LocalLibrary已接入；SessionLibrary为会话内组件测试替身，启动失败不切换替身。MAC-04已实现真实导入；schema/类型齐全不代表通用阅读器、书签/下载产品功能已完成。

设备声明/search/lock不在任何书库表中；novel-device为兄弟目录，不可随App书库备份或同步。定义与当前限制见[ADR-0007](../decisions/0007-mac16-local-access-and-privacy.md)。历史schema3快照保持在[旧DDL](novel-schema-v3.sql)。

## MAC-04导入索引

v5只新增imports，不重写旧书籍、样本段落位置与声明。`import-v1`修订保存原始摘要、字节数与格式，尚无解析章节；状态固定awaiting_parser。托管与引用的新增书籍/策略/修订/资源/索引同一SQL事务提交，摘要相同沿用已有书籍与分级，不按标题合并。托管对象损坏/缺失可重新导入相同摘要修复，不重写元数据。

引用只保存不透明设备grant_id，实际安全范围书签位于novel-device/grants。两个字段均不可跨设备同步：未来备份导出须剔除grant_id或转换为待关联；恢复后由用户重新关联同摘要原件。本批未实现MAC-14备份导出。暂存目录import-stage不属于书库正文，单写入租约取得后清理旧暂存。文件与SQL无法跨系统原子提交，崩溃可能留下未引用对象，沿用audit报告而非自动删正文。见[ADR-0008](../decisions/0008-mac04-document-import.md)。

## MAC-05版本化TXT索引

v6新增txt_indices（源导入外键、解析文档、规则、编码、块/单位/章节数与摘要）、txt_chapter_ranges（通用chapters对应块范围）、txt_active（每书活动解析版本），共16表。原始documents/imports及其awaiting_parser状态保留，是否已有可读TXT通过txt_active判断。解析版使用新的document_id与parser_version，原始摘要不变；旧锚点和旧解析版保留。

txt-stage为候选/中断暂存，启动持有写入租约后清理；txt-indices/文档ID只存96字节定长块索引与目录manifest，不存规范化全文。原件仍从objects或设备引用读取。正文块ID/章节ID仅在解析版本内稳定；分章确认不更新positions，旧版本位置由UI提示复核，用户主动保存才替换。未来备份可重建索引，引用授权仍不可便携导出。格式、上限、提交边界及故障处理见[ADR-0009](../decisions/0009-mac05-txt-index.md)。历史schema5快照保留在[旧DDL](novel-schema-v5.sql)。

## MAC-07 EPUB解析与临时资源

无新迁移，schema仍为6、共16表。EPUB解析使用既有documents（epub-v1）、chapters与positions，原始imports记录不变；同原件/解析器复用稳定文档修订，新的解析器版本须新增修订而非改写旧位置。正文及有摘要的资源仅在epub-sessions/会话ID中临时展开，关闭/取消/锁定/启动清理；引用原件不变。此目录不得进入未来书库备份/同步，崩溃到下次启动之间可能残留。具体映射、资源安全与恢复见[ADR-0010](../decisions/0010-mac07-controlled-epub.md)。


## MAC-08 schema7管理与回收

实际20表。新增book_metadata（作者/简介/状态/收藏/手动序号/最后打开/封面摘要/最后文件检查）、shelf_preferences（普通/成人/最近阅读分开）、shelf_actions（有界版本化逆向快照）、file_recycle（可恢复文件移动意图）。imports新增原始display_name；旧记录留空。collections新增scope与范围内有效名称唯一约束。现有位置用于回填在读/最近阅读，不改锚点或原件。

封面字节在covers/objects，回收的托管原件在recycle；二者均在本机小说资料区，不属于可随意清理的Web会话目录。软移出、文件回收和个人记录移除相互独立；逆向快照包含可能敏感的元数据与摘录，未来备份/同步必须沿用分级过滤，不自动外发。最近20候选撤销验证books.row_revision，不覆盖新位置或编辑；回收/恢复也推进book修订。完整约束见[ADR-0011](../decisions/0011-mac08-library-management.md)。


## MAC-09 schema8排版偏好

v8仅新增reading_preferences，共21表；scope='*'为全局默认，其他scope为本地book_id，value存version=1有界排版JSON，updated_at为修改时间。每书读写检查内容访问资格；恢复默认删除覆盖而非复制全局值。损坏JSON结构/值回退安全默认并提示，不改写旧值；无正文、凭据或成年资格。未来永久删除/备份需包含或清理此表，当前只有可恢复书架操作。

位置表与DocumentAnchor wire v1保持；共享ReadingSession按序合并保存reading通道，听书独立。重排/resize/主题切换保留原字符，不保存临时页数。修订/上下文不匹配暂停自动覆盖，复核后才主动替换。schema7历史快照保持在[旧DDL](novel-schema-v7.sql)，决策见[ADR-0012](../decisions/0012-mac09-reading-session-layout.md)。
