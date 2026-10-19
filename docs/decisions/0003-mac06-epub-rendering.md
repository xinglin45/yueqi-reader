# ADR-0003：EPUB选择受控WebView与结构锚点

日期：2026-10-19。状态：**研究选型已完成，生产接入在MAC-07/09**。适用当前macOS小说，不改变Flutter客户端或两款App独立架构。

## 决定与依据

选择平台WebView承载EPUB XHTML/CSS，Flutter负责D1壳、会话/位置/书架；资源由本机书籍白名单代理提供。macOS小样实际通过AppKitView嵌入WKWebView，不是浏览器截图或只读解析包。当前直接用系统SDK，无新增WebView插件；不因候选插件声称支持四端便冻结绑定。

比较双方读取同一份[自产EPUB](../../fixtures/novel/mac06/README.md)，SHA-256为`3d6d0a4ee10305897ef708f43e76375433998025b1417f0b655cb431090df701`。原包、离线规范化结果与Flutter库输入都由同一生成器产出，原包与Flutter资产逐字节相同。

| 场景 | WKWebView受控小样 | epub_view3.3.0实际试验 |
|---|---|---|
| 文件/目录/图片 | 2个spine、2条EPUB3目录；内部ch2.xhtml#target实点跳转；PNG96×56加载 | 解析2章/1图，图片实际显示；样本出现重复/错位章节标题 |
| CSS/字体/ruby | 铜色strong为rgb(159,101,75)、blockquote边3px、嵌入TTF加载、ruby存在 | 默认逐段Html渲染未应用书内外部CSS；字体/高亮细节需自行适配，不判断所有Flutter排版都不能支持CSS |
| 中文选字/高亮 | 真实鼠标选字从“目标位置”改为“在这里”；host隔离world捕获选区，CSS Highlights可用 | SelectionArea包裹库用于试验；没有完成精确选区→原文偏移映射，不计通过 |
| 锚点/重排 | 规范化block文本与DOM文本逐段一致；360宽/740宽双栏/恢复字号后所选文本一致、矩形有效 | 生成CFI原值`epubcfi(/6/0[title1]!/4/2[title1])`并调用恢复；不将非空字符串当字符精确恢复或跨引擎CFI一致证明 |
| 搜索/TTS同文 | 原文UTF-16：ch2/target“目标位置”[6,10)；鼠标“在这里”[10,13)，SQL/原生语音偏移转换另见本批决策 | 尚需定制稳定文本映射，库默认视口/段落CFI不足以证明字符映射 |
| 资源隔离 | EPUB脚本预移除；page world独立确认测试标志false；https/file/跨书/未列资源均被阻止 | 未给通用未受信书包建立生产沙盒；只运行自产样本，不因此宣称库安全通过 |

原始输出[webview.json](../verifications/mac-06/webview.json)、[Flutter对照截图](../verifications/mac-06/flutter-epub-view.jpg)、[WK样式截图](../verifications/mac-06/webview-chapter1.jpg)、[跨章选字](../verifications/mac-06/webview-mouse-selection.jpg)。360/740是正文重排宽度，不冒充原生整窗已调到该尺寸；分页翻书/全书重启位置仍待MAC-09。

## 实测发现与修正

1. epub_view3.3.0＋flutter_html3.0.0初次解析出html0.15.7，构建报`qs.matches`不存在，[失败日志](../verifications/mac-06/epub-view-initial-build-failure.log)保留。核对包源码与[html维护记录](https://pub.dev/packages/html/changelog)，研究dev依赖精确锁定html0.15.6后才构建运行。未修改SDK/第三方缓存源码。旧HTML版本只为已知样本比较；后续不得直接用于不可信生产导入。
2. 沿用MAC-02的Debug沙盒时，WebKit子进程退出。增加**DebugProfile**的network.client后，本地自定义scheme加载成功；Release权限未扩展。WKWebView需要自身网络子进程工作，内容请求仍经CSP、内容规则、书籍资源代理与导航白名单。MAC-07正式接入须验证Release签名/沙盒和最小权限，不能把Debug通过冒充Release引擎通过。[Apple沙盒说明](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
3. 点击Flutter按钮会使原生选区失焦。已在隔离world监听selectionchange，保留最后有效选区，在实际鼠标试验中回传“在这里”及UTF-16范围；不从屏幕坐标反推持久位置。

## 资源与执行边界

- 受限离线加载器先检查mimetype/容器/manifest/spine，拒绝重复ZIP路径、穿越、符号链接、DTD/实体、缺资源、未知格式等。预算：压缩4MB、展开8MB、单条4MB、256条、压缩比100；这是小样预算，生产大书必须另做分段读取和预算，不可直接套用。
- 当前接受EPUB3 reflowable子集、XHTML/CSS/PNG/TTF/许可文本；脚本删除，其他不支持内容明确拒绝。含encryption.xml本阶段拒绝，不把标准字体混淆混同DRM。EPUB2/NCX、JPEG/SVG/其他字体、表格/脚注/媒体/固定布局/大书属于MAC-07须明确支持或报错的项目，不悄悄删除首版需求。
- 数据在内存资源表中，WKURLSchemeHandler只服务当前书籍host和manifest路径；不把系统路径/任意URL传给网页。原生适配留macOS目录，领域和application未引入AppKit或系统路径。
- 非持久WKWebsiteDataStore；CSP默认none，书籍脚本禁用，外联内容规则/导航另拦截。固定host脚本在`.defaultClient`隔离world执行；页面标志另从page world读取，避免用隔离world的空标志冒充脚本未执行证据。没有开放任意JS方法或加载未知来源脚本。
- 选区桥接本批只接受同一块内的文本节点边界；跨块、元素边界和跨ruby注音的可见选区须MAC-07继续处理。对象拥有者销毁后解除通道/停止加载；正式接口还需超时、重入与Web进程崩溃恢复。

## 锚点草案与四端边界

研究采用`version + document_revision + spine_href + block_id + UTF-16 start/end + exact`；不保存屏幕页码，不承诺当前草案为完整CFI实现。NSRange/JavaScript/Dart统一UTF-16；SQL instr的Unicode标量偏移需转换。浮点桥接数字必须先校验为有限整数且在文本边界内，禁止截断小数或半个代理对。修订/块/摘录不匹配时保留旧锚点并明确失败，MAC-03/09再定义上下文指纹和可解释回退。原包hash仅为本研究修订，不是书架book_id。

| 平台 | 可替代承载路径 | 本批实测 |
|---|---|---|
| macOS | WKWebView + AppKitView + WKURLSchemeHandler | 当前arm64/macOS27.0.1 Debug嵌入通过；Release集成、最低系统/Intel未测 |
| iOS | WKWebView同类资源代理，Flutter平台视图 | 仅官方API研究；未构建/真机验证 |
| Android | WebView + WebViewAssetLoader/受控请求拦截 | 仅[Android官方资源代理](https://developer.android.com/reference/androidx/webkit/WebViewAssetLoader)研究；未构建/验证 |
| Windows | WebView2虚拟host或资源请求代理 | 仅[Microsoft本地内容方案](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/working-with-local-content)研究；未构建/验证 |

[Flutter AppKitView](https://api.flutter.dev/flutter/widgets/AppKitView-class.html)、[Apple scheme代理](https://developer.apple.com/documentation/webkit/wkurlschemehandler)、[EPUB3.3阅读系统规范](https://www.w3.org/TR/epub-rs-33/)与[epub_view发布页](https://pub.dev/packages/epub_view/versions/3.3.0)为研究依据。实现代码/依赖精确版本在锁文件，第三方许可见[本批清单](../licenses/mac-06-dependencies.json)；WebKit/Flutter组合不等于完整EPUB规范符合性声明。
