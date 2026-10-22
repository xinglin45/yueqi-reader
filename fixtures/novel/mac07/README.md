# MAC-07自产 EPUB 样本

2026-10-22，由小说/client/tool/mac07/generate_fixtures.py生成15个小包。简繁正文、表格、ruby和几何PNG/JPEG均为项目自产，无成人正文、第三方书籍或网络素材；项目源码许可证仍未选择。JPEG生成使用当前既有Pillow12.2.0，不进入App运行依赖，重新生成需该工具环境；日常检查只读取已提交样本。

有效样本覆盖EPUB2/NCX、EPUB3/层级nav、两spine、片段链接与图片；规范文本样本覆盖XML的CRLF/CR、CDATA、长节点和emoji/组合字符。其余为受控拒绝样本，仅交由有界校验器，不在其他阅读器执行。逐文件大小/摘要见manifest.json。已有嵌入字体和MIT许可样本复用../mac06，不把字体当作自产。
