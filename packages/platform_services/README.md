# platform_services

MAC-02已建立实际纯Dart包，小说App通过构造装配依赖此包。只提供[文件、受控凭据引用、语音及阅读窗口端口](lib/platform_services.dart)与统一PlatformResult。没有Flutter、AppKit、硬编码系统路径、原生插件或任一产品依赖。MAC-03增加仅面向装配/基础设施的StorageLocationProvider，具体path_provider适配放在小说infrastructure，领域不接触路径。

UnavailablePlatform对所有动作返回unsupported，语音能力为无暂停/无偏移，不伪造成功或Keychain。FileGrant/CredentialRef只携带本机不透明引用，不能作为可同步凭据或文件路径；SpeechEvent按sessionId归属，偏移单位必须显式声明。SecureStore本批只定义查找/删除受控引用，写入/认证消费协议在实际来源会话接入时再补，不把字符串密钥返回UI。

真实文件访问/授权恢复在MAC-04/13；系统TTS在MAC-12；菜单栏/悬浮窗口/生命周期在MAC-13；安全存储在实际凭据任务接入。四端目标全部保留，目前没有任何端的真实系统适配器。

测试替身放在消费App的test/fakes.dart，禁止将其作为生产安全存储。签名与生命周期草案见[接口](../../docs/interfaces.md)，验收见[MAC-02](../../docs/verifications/mac-02-2026-10-16.md)。

MAC-06新增`experiments/macos/SpeechProbe.swift`独立研究源，由小说`tool/mac06/run_speech_probe.py`编译运行；不作为Dart包导出，也没有接入生产SpeechService。当前机器暂停/继续、UTF-16回调及十分钟试验通过，整机离线/休眠等仍待MAC-12，见[研究决策](../../docs/decisions/0005-mac06-system-tts.md)。
