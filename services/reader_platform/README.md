# reader_platform

唯一启动入口为 app/，公共模块保留在 modules/；小说/漫画领域模块分别在根目录 小说/server、漫画/server，由同一聚合构建纳入，不在这里再保存副本。见[仓库布局](../../docs/repository-layout.md)。

Spring Boot 模块化单体预留。一个部署产物，共享账号/设备/同步/分级；内容不默认转发。MySQL 在云持久化时可选，Redis 按需。无构建文件、已运行端点或配置。初始化 FND-01，账号 SYN-01，同步 SYN-02。

此处仅为职责和目录预留，不是已实现的可运行模块。总体架构、验收与依赖见项目根目录 docs/architecture.md 和 docs/roadmap.md。
