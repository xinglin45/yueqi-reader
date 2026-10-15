# novel_sources

BookSource 与小说适配器；REST/OPDS/基础规则及 Legado 子集研究。接口 SRC-01，接入 SRC-03，研究 RES-01。

此处仅为职责和目录预留，不是已实现的可运行模块。总体架构、验收与依赖见项目根目录 docs/architecture.md 和 docs/roadmap.md。

小说只接中文简繁来源，优先免费，内置核验过的来源＋支持导入。普通/18+真实来源均属完整首版；includeAdultSources默认false且在网络请求前限制来源集合，关闭搜索不影响独立分组的已有收藏阅读。规则与调度/回调验收见 [novel-source-policy.md](../../docs/novel-source-policy.md)。
