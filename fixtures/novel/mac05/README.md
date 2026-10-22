# MAC-05自产TXT样本

日期：2026-10-22。章节-utf8.txt是本项目自产中性中文文本，包含简繁、emoji、CRLF、序章、无空格章标题、重复章名和後記。无第三方正文/素材、成人正文或公共来源；摘要见manifest.json。项目源码许可证仍未选定。

根目录.gitattributes禁止对本目录TXT做自动换行转换，保持CRLF原始字节和摘要一致。

10 MiB/50 MiB和超长段落在tool/mac05/benchmark.dart及临时测试目录动态生成，不提交大文件。既有UTF/BOM/GB18030/Big5边界样本复用../mac04/，其来源记录与哈希不变。
