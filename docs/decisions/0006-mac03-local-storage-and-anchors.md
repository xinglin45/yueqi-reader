# ADR-0006：后台SQLite、本地文件与UTF-16位置协议

日期：2026-10-20。状态：MAC-03已实现；本批仅macOS arm64验证，其他三端保留同一源码与平台目录。

## 选择

使用精确sqlite3 **3.7.1**直接绑定，由reader_storage内一个常驻isolate拥有连接；小说SQL及Repository放在小说/client。当前11张表的显式SQL与迁移足以覆盖本批，不引入Drift代码生成；未来若引入ORM，须沿用数据和位置协议并验证迁移，不能复制数据库。

[sqlite3维护者说明](https://pub.dev/packages/sqlite3/versions/3.7.1)指出其接口同步且通过hooks打包原生库，本批因此把连接/事务/迁移放到后台。实际绑定SQLite **3.54.0**，unicode61、trigram和短查询原文回退已复验，原值见[跨进程记录](../verifications/mac-03/restart-reader.json)。不再用Python或系统库结果代替App绑定结果。

系统资料/缓存目录由精确[path_provider2.1.6](https://pub.dev/packages/path_provider/versions/2.1.6)适配StorageLocationProvider取得，装配层追加novel/comic命名空间。领域与用例不接触插件或系统路径。默认入口已使用LocalLibrary；SessionLibrary仅保留给组件测试，不作启动失败时的假成功回退。

## 数据、写入与恢复

- 正文保存在独立objects目录，文件名为SHA-256，SQLite只存引用/类型/大小/修订。托管写入先暂存、flush与摘要校验，再同目录rename，最后提交元数据。数据库失败保留可审计孤儿，不自动删除可能被引用的文件。单次对象默认8MiB有界；MAC-04须实现大文件流式导入，不能把当前小样API当大书验收。
- 每连接开启foreign_keys、busy_timeout2500、synchronous FULL；正常模式用WAL。后台请求串行、写批次BEGIN IMMEDIATE，预期影响行数不符时整批回滚。SQLite锁和协作进程文件租约共同防止并发写；多窗口/多实例用户交互仍待MAC-13，不声称分布式锁。
- 迁移前VACUUM INTO临时备份，核验quick_check与版本后改正式备份名，再执行独占事务；备份失败不升级，DDL失败回滚。新版本库拒绝降级；迁移失败以只读方式打开可读旧库。损坏/无法初始化则进入明确的启动失败与重试页面，原文件不删除。
- [VACUUM INTO](https://www.sqlite.org/lang_vacuum.html)用于一致快照，[WAL](https://www.sqlite.org/wal.html)文件须与主库成套保留。应用不自动用备份覆盖原库；恢复步骤见[说明](../storage/recovery.md)。

schema已到v3：v1核心书籍/文档/章节/资源/位置，v2补注释/分组/来源绑定/任务/设置，v3保留同一原文件不同parser_version的历史修订。v3迁移暂存并重建依赖表，外键始终开启，测试覆盖旧位置保留。此为本批首次可持久版本的内部迁移序列，不声称过去发布过v1/v2。见[schema与实体](../storage/novel-schema.md)。

## 身份与位置

book_id为安全随机128位标识，独立于标题、路径、来源及排版页码。相同内容/格式/解析版本复用文档；同名不同内容不合并。documents对应本地版本/Edition，保留原文件摘要与parser_version；线上source_id/source_item_id只作独立绑定，不暗示跨源等同。

DocumentAnchor外层v1明确kind、修订、章节、spine/块、UTF-16范围、exact与前后各16标量上下文及SHA-256指纹。JS/NSRange/Dart的UTF-16一致；SQL instr从1起的标量偏移必须先减1再转换。禁止半代理对、负数、小数、非有限值/未知版本；不规范化简繁或组合字符。

恢复精确匹配才自动使用；同修订/块中唯一上下文匹配只返回候选，需接受后再保存。歧义、修订变更或块缺失回退章节开头/未定位，保留原锚点及摘录。阅读和听书按channel分行，带local_seq预期版本，迟到保存不能覆盖新位置，也不能串到另一书。

## 实际产品边界

主动加入自产《山间来信》后，书架、TXT样本文本、手动“记住这一段”与深浅色偏好已可跨启动恢复。仅此受控样本接入存储，当前不是通用TXT/EPUB解析器，也不自动追踪阅读滚动。其他实体已建schema/类型，笔记、标签、来源和持久任务的产品用例待各自任务，不把建表写作整项功能完成。

未知分级不进入普通书架；缓存/来源核验默认unknown。设置白名单仅theme/text_scale，成年声明在MAC-16独立实现，凭据仅预留不透明引用。没有账号、后端、同步outbox、网络来源或付费服务依赖。本项目源码许可证仍未选择；[许可清单](../licenses/mac-03-dependencies.json)与[验收](../verifications/mac-03-2026-10-20.md)记录本批实际范围。
