# fixtures

当前已添加[MAC-06自产中文EPUB](novel/mac06/README.md)：两章简繁正文、几何PNG、原文偏移边界和无外联的脚本负例，附确定性生成器与manifest。嵌入字体为第三方MIT资产，许可随样本保存，不能统称全包自产。

后续使用自产中日韩文本与图片/EPUB/CBZ，或保存作品许可证据后的样本。不自动下载候选聚合规则、私人书库或成人正文。小说当前仅中文；日韩文本/漫画图片留给漫画任务。模拟成人端点只验证默认零搜索请求，不能代替真实来源的首版核验。

MAC-16新增的中性分级卡片内嵌于[LocalLibrary](../小说/client/lib/infrastructure/storage/local_library.dart)（classification-card-v1），以及[策略测试](../小说/client/test/access_test.dart)中的普通/分级/未知标签，均为本项目2026-10-20自产，无外部原文、图片、成人正文或公网来源。仅测试分组与门禁，不将“18+测试标签”当作真实成人来源批准。卡片只在用户主动加入时创建，App首次不自动添加。
