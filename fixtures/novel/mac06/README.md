# MAC-06自产 EPUB 技术样本

生成/核验日期：2026-10-19。mountain-letter.epub为本项目自产普通中文测试书《山路与来信》，含简繁、标点、emoji、组合字符、两spine、EPUB3目录/片段链接、PNG几何样本、CSS/ruby与TTF内嵌字体。无私人作品或成人正文。

文本/几何PNG由小说/client/tool/mac06/epub_probe.py生成。字体来自锁定phosphor_icons3.0.1的Phosphor-Light.ttf，**不是自产字体**，MIT原文随EPUB保存在OEBPS/LICENSE-phosphor.txt，仓库留存见docs/licenses/mac-02/phosphor_icons-LICENSE.txt。字体SHA-256、原EPUB修订、规范化段落和偏移单位在manifest.json。项目源码许可证仍未选择。

书中包含自产负面测试脚本，只会设置测试标志，不访问网络或私人数据；受控路线在加载前移除脚本，CSP禁止书籍脚本。不得将原始书包作为通用可信HTML。它只用于本地研究，不代表第三方内容授权。

从仓库根执行 `python3 小说/client/tool/mac06/epub_probe.py` 可确定性重建；需要已按应用锁文件取得phosphor_icons3.0.1缓存。脚本同时生成App探针资产，二进制EPUB逐字节相同。异常ZIP/路径/DTD/未知内容等小样在测试内存中临时构造，不保存恶意包或大文件。

此加载器是受限研究子集，正式导入、通用格式与错误恢复在MAC-04/07实施。含encryption.xml的书包本阶段统一拒绝；后续需区分标准字体混淆与DRM，不能把所有加密元数据都称作DRM。
