# ADR-0005：macOS听书优先使用系统原生语音适配

日期：2026-10-19。状态：前置路线验证完成；MAC-12生产听书尚未实现。

## 选择与实测

macOS拟通过platform_services中的SpeechService适配AVSpeechSynthesizer，原生语音/生命周期保持在平台侧，小说用例只处理会话和文本锚点。当前生产端口仍返回unsupported；本批Swift研究程序不是已接入的听书功能。

[flutter_tts4.2.5维护说明](https://pub.dev/packages/flutter_tts/versions/4.2.5)的macOS功能表没有列入pause或speech marks，不把跨平台总功能表当macOS保证。此次直接测试Apple API，未将flutter_tts加入生产依赖。[Apple暂停API](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/pausespeaking(at:))及[范围回调](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate/speechsynthesizer(_:willspeakrangeofspeechstring:utterance:))为接口依据。

| 项目 | 真实观测 |
|---|---|
| 语音 | 受限探针枚举20条zh-CN/zh-TW系统语音；数量仅代表此机器/此运行条件，不能作为固定支持数 |
| 音频生成 | Tingting/Meijia各完成约6.1秒非零PCM缓冲生成，22050Hz；不保存/上传私人正文或录音 |
| 暂停/继续 | 两个请求均返回true，有didPause/didContinue回调；稳定暂停1秒期间范围回调增量0 |
| 原文范围 | NSRange按UTF-16，📖回调length=2；与JS/Dart单位一致，不能按汉字计数或Python字符索引直接使用 |
| 切书 | 先更换session再stop旧utterance，再开始B；B完成，旧回调被代际过滤。本次共丢弃2条过期回调，计数包含所有试验阶段转换，不只A→B |
| 十分钟 | 音量设为0的实时调度600.33秒、147次句段循环，无超时或持续排队；不改系统音量/偏好 |
| 内存 | 探针进程采样峰值54336KiB（约53.1MiB），末次52224KiB（51MiB）；不含语音服务/XPC或完整Flutter App，不能套作全App预算 |
| 语音缺失 | 不存在的voice identifier返回nil，应给用户可恢复选择，不能伪造朗读成功 |

原始范围/状态与列表见[tts-process-network-denied.json](../verifications/mac-06/tts-process-network-denied.json)，RSS采样见[tts-memory.json](../verifications/mac-06/tts-memory.json)。原生范围实测与[EPUB DOM锚点](../verifications/mac-06/webview.json)、检索UTF-16转换使用相同单位约定；未实现正式句段队列/高亮联动。

## 离线证据的实际范围

通过sandbox-exec对**探针进程**禁止网络后，安装的两条compact语音仍输出非零PCM并播放调度完成。该策略没有证明系统XPC语音服务也被断网，不声称整机断网/飞行模式、所有语音或云语音均已通过。MAC-12还需在明确断网条件下逐条核验离线能力，不下载新语音，也不因枚举到语音便写offline=true。

本批音量0，不提供真实听感、中文多音字/停顿/变调、耳机切换或音频路由质量结论。未做真实休眠/唤醒/锁屏、整夜播放、所有语音/最低系统/Intel测试；十分钟小样不代替正式长时验收。

## MAC-12实施约束

- 当前Swift研究源码在Swift5模式产生Sendable提示，主循环与缓冲计数已集中到主线程，但正式适配必须完成MainActor/回调线程隔离验证，不能把研究类直接搬进生产。
- 每个utterance绑定session_id和原文范围；先使旧会话失效，再取消底层工作。监听进度独立保存，不能覆盖阅读位置。停止、隐藏、切书、语音缺失、后台/唤醒都需要有状态与验证。
- SpeechService草案还需细化paused/resumed/cancelled/error事件、偏移length/原文映射，以及语音离线能力unknown状态。现有bool字段不能承载未核验的离线保证；在真正适配时扩展契约。
- Windows/Android/iOS仍需逐端系统适配和中文真机测试，不能由当前Mac结果替代。系统语音无需本项目接入付费云服务，但不对未来第三方服务费用/授权作承诺。
