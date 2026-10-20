# reader_storage

MAC-03已实现通用SQLite后台连接、事务/迁移恢复与托管文件；纯Dart基础，不依赖Flutter或任一App。消费产品传入ReaderProduct、系统提供的资料目录与本产品SchemaStep；小说SQL留在小说/client，漫画尚未实现自己的schema/用例。

- StorageDatabase.open：一个后台isolate拥有连接，串行查询/事务；外键、FULL同步、WAL与本机协作租约。SQL只供本项目基础设施使用，禁止从导入规则或正文接收SQL。
- SchemaStep：连续版本，升级前核验VACUUM快照，DDL事务失败回滚；旧库恢复模式readOnly，新版本库不降级。无法读取/初始化返回StorageFailure，绝不自动删库。
- SqlCommand.expectedChanges：比较更新的原子前置条件，失配整批回滚，防止迟到进度覆盖。
- ContentFiles：摘要对象名、默认8MiB有界、暂存校验后rename；非法摘要/符号链接/损坏文件拒绝。audit报告缺失/孤儿，不自动回收；大文件流式导入在MAC-04扩展。

锁定sqlite3 3.7.1、crypto3.0.7、path1.9.1。实际macOS绑定SQLite3.54.0，其他三端只保留上游支持与工程入口，未构建。包锁由小说App统一留存，库目录不提交独立锁文件。测试在消费App的storage_test.dart/persistent_shell_test.dart覆盖真实文件库；不依赖公网测试数据。

[ADR-0006](../../docs/decisions/0006-mac03-local-storage-and-anchors.md) · [小说存储协议](../../docs/storage/novel-schema.md) · [恢复说明](../../docs/storage/recovery.md)
