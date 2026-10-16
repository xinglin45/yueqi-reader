# ADR-0001：MAC-01工具链与中文路径静态检查

日期：2026-10-16。状态：采用；限本批基础工程，D1正式UI仍在MAC-02实现。

## 决策

固定Flutter **3.47.7 stable**、Dart **3.13.5**。官方仓库stable分支与3.47.7标签在核验时均指向`abaf9c523780a608bd46686fd5e53740a07077f8`，engine为`deb287481e3ce9468f3434937ced4240a70539ca`。具体约定保存于[SDK锁定文件](../../tool/flutter-sdk.json)，包装命令验证framework/engine/Dart版本；SDK不进入源码仓库，不修改用户全局PATH。依赖解析以应用pubspec.lock为准，不执行隐式升级。

官方SDK归档清单与压缩包下载入口本轮返回404；随后从[Flutter官方Git仓库](https://github.com/flutter/flutter/tree/abaf9c523780a608bd46686fd5e53740a07077f8)下载固定标签，核对实际提交、engine修订与运行时版本。SDK自身从官方storage.googleapis.com下载匹配的Dart/引擎资源。没有把下载失败改写为归档校验成功，也没有声称核验了未取得压缩包的SHA-256。Git固定提交是本次源码安装的复现依据。

本批仅依赖Flutter、实际使用的纯Dart共享包reader_core，以及Flutter SDK测试工具和flutter_lints。Riverpod/go_router/Drift等在真正使用它们的任务再联合解析，不为MAC-01提前添加空装配。

macOS先验证Apple Silicon：项目级`ARCHS=arm64`、`EXCLUDED_ARCHS=x86_64`，不设置全局Flutter架构偏好。最低目标采用模板的macOS 12.0；最低系统真机与Intel均未验证。iOS、Windows、Android保留生成的独立宿主；不能由macOS构建推断它们已经通过。

应用开发标识暂定`local.yueqi.novel`，使用本地占位命名，不声称持有相应公共域名。发布前在MAC-24冻结标识、签名与渠道。源码包名novel_app，用户显示名阅栖，工程检查版本0.0.1+1，图标暂用Flutter模板资源。

## 中文路径分析错误与替代检查

首次在真实中文工作区执行`flutter analyze`，其LSP客户端发送初始化消息时，`Content-Length`使用`message.length`；目录名含非ASCII时，字符数与UTF-8字节数不一致，分析服务收到截断JSON并以255退出。证据来自固定SDK的[analysis.dart](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/packages/flutter_tools/lib/src/dart/analysis.dart#L156)，以及本机实际错误`FormatException: Unterminated string`。此失败不计作静态检查通过。

采用同一SDK的`dart analyze --fatal-infos --fatal-warnings`，继续加载应用的`analysis_options.yaml`与flutter_lints。实际中文目录分析已通过；[本地检查脚本](../../tool/check.sh)和CI使用该入口。Dart官方说明见[dart analyze](https://dart.dev/tools/dart-analyze)。不修改SDK源码、不另复制英文路径工作区，不降低lint严重级别；后续升级SDK时重新核验Flutter CLI是否已修复。

## 原生依赖与边界

当前没有原生第三方插件；Flutter 3.47使用默认Swift Package Manager路径，未安装CocoaPods。doctor仍报告CocoaPods缺失，是否影响当前交付以实际macOS构建结果单独记录；引入需要Pods的插件时再核验/安装，不声称所有插件都支持SwiftPM。

Android许可尚有未接受项，本批不代替用户接受条款，Android构建留待对应平台任务。本次不依赖Java、Spring Boot、MySQL、Redis或任何在线书源。来源批准0/0及特殊区域/成年声明策略保持。
