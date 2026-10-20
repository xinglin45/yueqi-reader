# novel_app · 阅栖

小说/client是一套Flutter工程，保留Android、iOS、Windows、macOS四个宿主，共用lib。MAC-01/02、MAC-06研究与MAC-03本地存储已完成，仅验证macOS Apple Silicon。显示名阅栖，开发标识local.yueqi.novel，版本0.0.4+4。

沿用D1暖纸导航/响应布局。主动“体验演示样本”后，自产《山间来信》已保存在本机；“记住这一段”保存手动段落检查点，重新打开样本恢复到该段，深浅色偏好也会保留。首次不自动添加书籍，无需登录。通用TXT/EPUB导入、完整排版/自动阅读进度、系统听书、来源、下载及同步尚未实现。

从根目录检查：

```sh
python3 tool/sdk.py install
./tool/check.sh
```

运行生产本地入口（在本目录）：

```sh
../../tool/flutterw run -d macos
```

构建Release：`../../tool/flutterw build macos --release --no-pub`，随后在根目录运行`python3 tool/sign_macos_internal.py`完成并深度校验内部ad-hoc封套（保持原权限，仅处理本项目既有ad-hoc产物）；产物`build/macos/Build/Products/Release/阅栖.app`。ad-hoc内部检查版，未公证/DMG/安装升级验收；最终签名与原生assets证据见本批构建记录。SDK/机器配置/数据库/产物不提交。

数据由系统Application Support/Cache接口取得，追加novel命名空间，SQLite和objects与漫画隔离。启动失败保留旧资料并给出重试；升级失败/未来schema以只读模式保留可读数据，绝不切换内存替身伪装成功。恢复流程见[恢复说明](../../docs/storage/recovery.md)。

- lib/domain：无Flutter/系统路径的书籍、文档修订、资源、位置与实体类型；UTF-16锚点及可解释回退。
- lib/infrastructure/storage：小说11表schema v3、LocalLibrary与位置/设置持久化；platform_storage_locations隔离path_provider。
- packages/reader_storage：通用后台SQLite/迁移/托管文件；platform_services保留纯Dart平台端口，文件选择/凭据/语音/系统窗口动作仍unsupported。
- SessionLibrary与AppDependencies.local只供会话内组件测试；默认入口使用真实AppDependencies.open。
- tool/check.sh检查格式、严格Dart分析、Flutter/Dart与13项Python测试和三个共享包。当前中文路径Flutter CLI LSP错误沿用[ADR-0001](../../docs/decisions/0001-mac01-flutter-toolchain.md)替代方式。

[MAC-03验收](../../docs/verifications/mac-03-2026-10-20.md) · [存储决策](../../docs/decisions/0006-mac03-local-storage-and-anchors.md) · [schema/位置协议](../../docs/storage/novel-schema.md) · [依赖许可](../../docs/licenses/README.md)

MAC-06独立Debug对照入口仍在[tool/mac06](tool/mac06/README.md)，不等于生产EPUB接入。MAC-03跨进程复验见[tool/mac03](tool/mac03/README.md)。下一主任务第05步MAC-16：一次成年声明、分级与独立成人收藏/隐私基础。其他三端、漫画与后端保留后续范围，普通/18+内置批准仍0/0。
