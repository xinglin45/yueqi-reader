# platform_services

跨平台系统能力的接口与适配目录预留：文件选择/权限、安全存储、系统语音、窗口/菜单、任务生命周期与通知。支持目标为 macOS、Windows、Android、iOS，首批先验证 macOS。

当前只有职责说明，没有已实现的 Dart 包或原生插件。公共业务代码依赖端口，不直接依赖 macOS 系统路径/原生实现；成熟插件也必须核验实际四端能力和许可证。

详细设计见 [四端技术边界](../../docs/novel-cross-platform.md)。初始化任务 MAC-01/02，TTS 任务 MAC-12，文件/桌面集成 MAC-13。能力未实现时明确返回 unsupported，不伪造成功。
