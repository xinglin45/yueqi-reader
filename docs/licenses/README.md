# 依赖许可留存

2026-10-16按实际应用锁文件与package_config/pub deps记录，共28包（含开发依赖），运行时闭包9包（含novel_app、reader_core）。

- [机器可读清单](mac-01-dependencies.json)：包名、实际版本、来源、运行/开发范围、许可文本SHA-256；不保存本机绝对缓存路径。
- [Flutter SDK BSD许可](flutter-BSD-3-Clause.txt)：固定SDK对应原文。
- `mac-01/`：实际运行时第三方包的LICENSE原文，包括sky_engine聚合第三方声明；不把聚合文件内所有依赖一律标为BSD。
- 构建产物Flutter assets保留NOTICES.Z；实际存在、字节数与哈希见[构建记录](../verifications/mac-01-build-metadata.json)。

MAC-01原始清单由该提交的脚本生成；当前重建须显式提供`--checkpoint`，不得用新依赖覆盖历史快照。开发包仅记录实际许可哈希及上游版本地址；不随App打包开发依赖。novel_app和reader_core为本项目源码，项目许可证仍未选择；第三方许可留存不为本项目自动指定许可证，也不是免费商用/再分发的一揽子声明。


## MAC-02（2026-10-16）

[本批清单](mac-02-dependencies.json)记录实际应用锁文件解析的30包、11个运行时包（含App/core/platform_services），8个第三方运行时包的LICENSE原文由清单定位；未变化的7份复用mac-01原文及哈希，mac-02/仅留新增Phosphor原文。新增phosphor_icons 3.0.1：MIT，Phosphor维护分支的SDK兼容情况见[ADR-0002](../decisions/0002-mac02-shell-and-jobs.md)。无新增原生插件或CDN。源码项目许可证仍未选择。

运行 `python3 tool/record_dependency_licenses.py --checkpoint mac-02` 更新本批清单；MAC-01文件保持历史快照。Release聚合声明实际大小/哈希见[MAC-02构建记录](../verifications/mac-02-build-metadata.json)。

## MAC-06（2026-10-19）

[本批清单](mac-06-dependencies.json)记录49包：运行闭包11、研究专用29、其他开发9。运行依赖未新增；研究入口使用精确epub_view3.3.0与html0.15.6及传递依赖，新增29份研究许可原文在mac-06/，未变化的运行许可复用旧快照。html旧版只为已知自产样本复现兼容问题，不能自动用于不可信生产导入，见[ADR-0003](../decisions/0003-mac06-epub-rendering.md)。

样本使用Phosphor MIT字体，原许可同时嵌入EPUB，不把字体视作自产。可通过`python3 tool/record_dependency_licenses.py --checkpoint mac-06`重建当前清单；历史MAC-01/02不覆盖。Release的聚合NOTICES实际字节数/哈希见[构建记录](../verifications/mac-06/release-build.json)，研究dev依赖出现在聚合声明不等于生产入口集成了引擎。项目源码许可证仍未选择。

## MAC-03（2026-10-20）

[本批清单](mac-03-dependencies.json)记录77包：运行依赖闭包47、MAC-06研究专用21、其他开发9。该范围按pub依赖图划分，包含原生assets构建工具和各端实现包，不声称47包都产生运行时代码。新增27份许可原文由清单定位，其余复用既有哈希文件；历史快照不覆盖。

实际新增sqlite3 3.7.1（Dart绑定MIT）、path_provider2.1.6及其各端实现、crypto3.0.7/path1.9.1（从研究闭包转为直接运行依赖）与本项目reader_storage。SQLite原始交付代码的[官方公共领域声明](https://sqlite.org/copyright.html)与Dart绑定许可证分开记录，不把它推及其他依赖或项目源码许可证。本次选择普通SQLite预编译库，未引入SQLCipher/多加密扩展或收费服务。构建hook按上游内置摘要校验下载资产；Release内实际sqlite3/objective_c代码哈希见[构建记录](../verifications/mac-03/release-build.json)。

重建命令：`python3 tool/record_dependency_licenses.py --checkpoint mac-03`。所有pub包精确解析结果由App锁文件留存，实际LICENSE原文/哈希已核对。系统SDK仍按系统许可使用；留存第三方声明不替本项目选择源码许可证，也不代表来源作品或未来分发渠道均已批准。

## MAC-16（2026-10-20）

[本批清单](mac-16-dependencies.json)仍为77包，运行闭包47、研究21、其他开发9；无新增依赖/插件/权限/许可原文，复用既有文件与哈希。App升级0.0.5+5，源码许可证仍未选定。可运行`python3 tool/record_dependency_licenses.py --checkpoint mac-16`重新核对，历史清单不覆盖。

## MAC-04（2026-10-21）

[本批清单](mac-04-dependencies.json)仍为77包，运行闭包49、研究19、其他开发9；xml6.6.1及其已有petitparser依赖从研究转入运行范围，无版本升级、新第三方包或新增许可原文。生产EPUB只采用有界ZIP校验器与XML元信息检查，未接入研究用epub_view引擎。macOS文件和中文旧编码适配使用系统AppKit/CoreFoundation，无新增原生插件。重建：`python3 tool/record_dependency_licenses.py --checkpoint mac-04`；既有许可哈希复用，源码许可证仍未选择。
