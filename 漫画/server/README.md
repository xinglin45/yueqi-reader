# reader-comic

源码位置：漫画/server。本目录是漫画 Java 领域模块，不是独立 Spring Boot 服务；由 services/reader_platform/app 装配，与共享模块一起部署。构建配置将在 FND-01 建立。

见[漫画目录说明](../README.md)与[仓库布局](../../docs/repository-layout.md)。

漫画收藏、书签与进度聚合；漫画领域拥有数据。 模块通过公开接口协作，不直接跨模块改表，随单一服务部署。

此处仅为职责和目录预留，不是已实现的可运行模块。总体架构、验收与依赖见项目根目录 docs/architecture.md 和 docs/roadmap.md。
