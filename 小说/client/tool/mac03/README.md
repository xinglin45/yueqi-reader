# MAC-03持久化复验

生产入口lib/main.dart经NovelStartup与SystemStorageLocations打开真实本地库；本目录只复验同一存储实现，不是第二套App或私有资料导入工具。使用自产短篇，不接入网络、账号或后端。

在小说/client目录中，为独立检查点目录运行：

```sh
mkdir -p build/mac03
../../tool/dartw run tool/mac03/storage_probe.dart write-crash build/mac03/process-state > build/mac03/crash-writer.json
/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' ../../tool/dartw run tool/mac03/storage_probe.dart verify build/mac03/process-state > build/mac03/restart-reader.json
```

write-crash在提交样本/位置/主题后直接exit，特意跳过连接close/checkpoint；verify为另一个进程，只检查旧数据与临时FTS表。两者的书籍ID、位置序号与原文相同且进程ID不同。进程禁网是当前Mac额外证据，不声称整机或系统服务均断网。write模式则正常关闭。

输出含schema/SQLite源版本与自产数据，不包含本机路径/私人正文/凭据。构建、原始DB/WAL/日志在忽略的build目录；提交证据位于docs/verifications/mac-03。复现可更新同一研究目录的位置代际；历史原值以Git提交为准。通用大文件导入、完整引擎与产品搜索仍待后续任务。
