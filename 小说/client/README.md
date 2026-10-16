# novel_app · 阅栖

源码位置：小说/client。一套Flutter工程保留Android、iOS、Windows、macOS四个宿主，共用lib；MAC-01已完成基础工程初始化，当前只验证macOS Apple Silicon基础壳。显示名阅栖，开发标识local.yueqi.novel，版本0.0.1+1。真实书架、TXT/EPUB和阅读功能尚未实现。

保留原产品职责与入口：[小说目录说明](../README.md)、[仓库布局](../../docs/repository-layout.md)、[四端边界](../../docs/novel-cross-platform.md)。核心业务仍按FND/NOV与macOS专题任务推进，不按平台或环境复制源码。

## 本机运行

固定Flutter 3.47.7 / Dart 3.13.5，使用项目包装命令，不修改全局PATH。首次从仓库根安装：

```sh
python3 tool/sdk.py install
./tool/check.sh
cd 小说/client
../../tool/flutterw run -d macos --debug
```

在本目录构建Release：`../../tool/flutterw build macos --release --no-pub`，产物`build/macos/Build/Products/Release/阅栖.app`。当前ad-hoc签名，只作工程检查；未公证/正式发布，不是完整自用阅读包。SDK/构建输出/机器配置不提交。

## 检查与边界

[MAC-01验收](../../docs/verifications/mac-01-2026-10-16.md) · [SDK/中文路径分析决策](../../docs/decisions/0001-mac01-flutter-toolchain.md) · [依赖许可](../../docs/licenses/README.md)

使用同一SDK的严格`dart analyze`替代当前中文路径下失败的Flutter CLI LSP入口。应用锁文件提交；reader_core只提供独立产品命名空间，其他共享包、漫画与server仍为后续。其余三端宿主已生成但未构建/运行；Android许可、CocoaPods警告和原生输入法验收边界见验收记录。

下一步MAC-02按已确认的[D1设计](../../docs/design/novel-macos/design-spec-D1.md)实现应用壳与路由；后续功能、安装包和首版来源条件见[macOS完整方案](../../docs/novel-macos-plan.md)。
