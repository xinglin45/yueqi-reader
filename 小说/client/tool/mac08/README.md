# MAC-08检查入口

从根目录运行`./tool/check.sh`完成固定SDK、严格分析、Flutter/Dart和Python回归。`export_schema.dart`在系统临时目录创建自产空库，导出schema7/20表后清理，不读取用户库。

从小说/client运行：

```sh
../../tool/dartw run tool/mac08/export_schema.dart > ../../docs/storage/novel-schema-v7.sql
../../tool/flutterw build macos --debug --no-pub -t tool/mac08/probe_main.dart
```

probe_main只把系统资料和缓存位置注入mac08-probe，显示“MAC-08隔离检查”，业务源码与默认入口相同。手动通过真实NSOpenPanel选择项目自产TXT/EPUB、普通分级，核对详情/元信息、状态收藏、分组/筛选/列表持久化、封面PNG选择、移出恢复与托管文件回收。正常退出重启核对资料。成年门禁自动化只在临时库用中性内容验证，不在生产库代用户确认。

结束后使用默认main.dart重建Debug/Release，运行`python3 tool/sign_macos_internal.py`验内部Release ad-hoc签名，再启动默认入口核对原书库、主题与位置。不要交付检查入口。本步无新在线来源/网络下载；原始fixture和封面资产保持不变。
