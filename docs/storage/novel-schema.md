# 小说本地数据与位置协议 v1

日期：2026-10-20。数据库schema **v4**；DocumentAnchor wire schema **v1**，两者独立升级。代码源为[小说schema](../../小说/client/lib/infrastructure/storage/schema.dart)、[领域类型](../../小说/client/lib/domain/catalog.dart)、[锚点](../../小说/client/lib/domain/documents.dart)。实际SQLite导出的[DDL快照](novel-schema-v4.sql)供审阅，不代替源码迁移。

## 存放与表职责

系统Application Support/Cache由StorageLocationProvider提供；各自追加novel或comic。小说DB逻辑名novel.sqlite，正文在同一资料区objects/SHA256，缓存为独立缓存区；数据库只存相对资源href、摘要与受控引用。App私有路径不进领域、锚点、日志或未来同步。reader_storage只提供通用基础，不能依赖任一App。

| 表 / 模型 | 主身份与约束 | 当前使用 |
|---|---|---|
| books / BookSummary | 随机book_id；标题不唯一，中文语言与rating/evidence；row_revision和deleted墓碑 | 本机书架及自产样本 |
| documents / DocumentRevision（Edition） | id、book_id、digest、kind、parser_version；(digest,kind,parser_version)唯一；原始大小/类型/时间 | 托管TXT样本修订；同文件换解析器可保留旧修订 |
| chapters / ChapterRecord | (document_id,id)主键、ordinal唯一、spine_href | 自产样本章；TXT/EPUB实际解析后续接入 |
| resources / ResourceRecord | (document_id,href)、摘要、类型、大小、cache_permission三态 | 样本文本为已知自产allowed；其他默认unknown |
| positions / StoredPosition | (book_id,channel)、document_id、anchor JSON、local_seq、更新时间；(book_id,document_id)复合外键 | 阅读/听书独立持久位置；UI仅样本手动段落检查点 |
| annotations / AnnotationRecord | bookmark/highlight/note；关联书籍/修订；anchor、note、row_revision、deleted | schema/模型已定义；MAC-11产品用例待实现 |
| content_policy / ContentRating | book_id外键；原始/内部评级、最低年龄/来源地区/证据/策略/来源资格 | MAC-16门禁，unknown/prohibited不自动归普通；地区skipped_by_user |
| collections / CollectionRecord | collection/tag/adult；独立id、标签、revision/墓碑 | schema/模型已定义；MAC-16成人分组已实现；一般管理MAC-08待实现 |
| collection_books | 书籍与分组复合主键/外键 | MAC-16中性分级卡片与独立成人分组关系 |
| source_bindings / SourceBinding | source_id＋source_item_id唯一；对应本地book_id、核验/缓存unknown、仅credential_ref、revision/墓碑 | 未来显式来源绑定，尚无真实接入 |
| jobs / StoredJob | 持久job_id、import/download、状态/进度/安全错误码/时间 | 任务模型基础；调度/恢复产品用例待MAC-04/21 |
| settings | key白名单theme/text_scale；JSON值、row_revision | 深浅色实际持久；其余设置后续 |

row_revision仅本机元数据代际；updated_at是UTC epoch毫秒，不能作为未来跨设备唯一冲突顺序。后续MAC-25补服务修订/设备序号与协议，不创建空转outbox。删除有墓碑，当前UI尚未开放清库/删书。

## 原子边界与故障状态

SQLite事务涵盖书籍、修订、章节与资源引用；外部文件与SQL不属于同一原子事务。先完成受控文件，再提交引用，中断留下未引用对象；audit列出missing/orphaned，不自动回收。missing/corrupt对象明确报错，不用空正文替代。暂存写入失败只清理本次暂存；不会清除已有对象。

查询也经过同一后台连接。所有值绑定参数；SQL仅来自本项目源码，不将来源JSON/脚本拼成SQL。位置写采用expectedSequence比较更新，0只允许首次创建；事务影响行数不符返回conflict。metadata约束/外键错误整批回滚，后续写入仍可继续。

租约针对本机协作进程，不是安全边界；SQLite锁/约束仍为最终保障。未验证网络共享盘、物理断电或真实满盘，不将逻辑回滚测试扩大为这些环境已通过。

## DocumentAnchor

字段固定为schema_version=1、document_kind(txt/epub)、content_revision、chapter_id、spine_href、block_id、offset_unit=utf16_code_unit、start/end（左闭右开）、exact、prefix/suffix与context_sha256。exact最多512 UTF-16单元，上下文各16 Unicode标量，不保存整段正文作为位置。位置和标注均绑定文档修订，不用标题或屏幕页号。

- UTF-16 start/end允许空范围表示游标；拒绝半代理对。📖占2单元，e＋组合音标保持原序列。
- EPUB spine使用manifest内路径；TXT的块ID及章节来自明确解析器版本。MAC-06受控WebView尚未接入默认入口，正式解析在MAC-05/07完成。
- 精确偏移与上下文一致→exact；同修订/同块中唯一上下文→context候选；找不到/歧义/修订变化→chapterStart或unresolved。候选/回退不覆盖数据库旧记录，UI应说明旧位置保留。
- SQLite instr返回1起的Unicode标量位置，转0起后通过scalarToUtf16；NSRange/JS直接按UTF-16，桥接数值先验证有限整数，不截断小数。

## 迁移兼容

内部交付含v1→v2→v3→v4序列；v4增加分级策略，迁移只对已知自产普通样本填notRequired，其余来源资格unknown。升级前先生成并核验独立SQLite快照；失败拒绝升级，DDL失败事务回滚。遇到未来版本只读打开、不降级；无法读取或首次初始化失败则显示启动错误，保留原文件。恢复流程见[恢复说明](recovery.md)。

生产入口LocalLibrary已接入；SessionLibrary为会话内组件测试替身，启动失败不切换替身。schema/类型齐全不代表真实导入、通用阅读器、书签/下载产品功能已完成。

设备声明/search/lock不在任何书库表中；novel-device为兄弟目录，不可随App书库备份或同步。定义与当前限制见[ADR-0007](../decisions/0007-mac16-local-access-and-privacy.md)。历史schema3快照保持在[旧DDL](novel-schema-v3.sql)。
