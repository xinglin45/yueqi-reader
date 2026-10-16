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
