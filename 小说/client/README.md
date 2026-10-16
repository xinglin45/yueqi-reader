# novel_app · 阅栖

小说/client是一套Flutter工程，保留Android、iOS、Windows、macOS四个宿主，共用lib。MAC-01工程与MAC-02应用壳已完成，仅验证macOS Apple Silicon。显示名阅栖，开发标识local.yueqi.novel，本批版本0.0.2+2。

已实现D1暖纸导航、桌面/窄窗布局、深浅色、明确空态、可取消任务与构造注入端口。首次为空库，可主动“体验演示样本”打开自产《山间来信》；仅内存预览，没有真实导入、解析、阅读进度、SQLite或在线书源。阶段说明内可检查任务加载/取消/部分完成/无结果/错误。

## 本机运行

固定Flutter3.47.7 / Dart3.13.5，使用项目包装命令，不修改全局PATH。首次从仓库根安装：

```sh
python3 tool/sdk.py install
./tool/check.sh
cd 小说/client
../../tool/flutterw run -d macos --debug
```

在本目录构建Release：`../../tool/flutterw build macos --release --no-pub`，产物`build/macos/Build/Products/Release/阅栖.app`。当前ad-hoc签名，只作内部应用壳检查，未公证/正式分发；未制作DMG或完成完整安装/升级验收。SDK/构建输出/机器配置不提交。

## 代码与检查

- app：构造装配、SDK Router（路由只传bookId）、D1主题/响应壳；features：各页面入口与TaskView。
- domain：Repository、预览模型与任务契约，application：代际任务控制、有限脱敏诊断；infrastructure：空库＋自产样本的会话内Repository。
- reader_core保持产品命名空间；platform_services为纯Dart系统端口，当前生产系统动作全部unsupported。测试替身位于test/fakes.dart，不能当生产安全存储。
- `tool/check.sh`检查格式、严格Dart静态分析、15项测试和两个共享包。当前中文路径Flutter CLI LSP问题仍用同SDK严格dart analyze替代，详见[ADR-0001](../../docs/decisions/0001-mac01-flutter-toolchain.md)。

[MAC-02验收](../../docs/verifications/mac-02-2026-10-16.md) · [壳/取消/图标决策](../../docs/decisions/0002-mac02-shell-and-jobs.md) · [依赖许可](../../docs/licenses/README.md) · [D1设计确认](../../docs/design/novel-macos/confirmation-D1.md)

下一主任务第03步MAC-06：EPUB风险小样并做中文检索/TTS前置试验；第04步再做MAC-03数据。其他三端宿主未构建，真实文件授权、听书、低存在感系统表面、分级/隐私、下载/同步均在后续任务。普通/18+来源批准仍0/0，完整首版条件保持。
