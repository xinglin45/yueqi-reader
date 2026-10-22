# ADR-0010：受控 EPUB 会话、资源代理与原文片段锚点

日期：2026-10-22。状态：采用。第08步MAC-07，延续[MAC-06选型](0003-mac06-epub-rendering.md)，保留D1、TXT及MAC-16门禁。

## 文档与资源边界

小说领域提供EpubDocumentReader，平台界面仅接触会话/资源ID、目录、结构锚点；不接触系统文件路径或任意JS。LocalEpubReader通过MAC-04的授权快照读取原件，后台isolate完成ZIP/CRC、XML、净化与摘要。托管文件在解析前后计算原始SHA-256，并与导入修订比对；引用快照先核对导入摘要，解析后即清理。

共享EpubArchive从MAC-04检查器抽出，导入与阅读沿用同一ZIP预算和安全路径检查。原件最多64 MiB、4096条目、总展开128 MiB、单条16 MiB；拒绝ZIP64/多磁盘/加密、重名/重叠条目、符号链接、越界路径、异常CRC/大小及高压缩比。展开超过1 MiB且大于压缩数据200倍拒绝。绝不把ZIP路径作为磁盘输出路径。

本步支持EPUB2/3 reflowable UTF-8 XHTML、EPUB3 nav与EPUB2 NCX、层级目录、多spine/片段链接、表格/ruby、PNG/JPEG及普通TTF/OTF/WOFF/WOFF2字体。XHTML每条2 MiB、CSS512 KiB、其他资源8 MiB，spine最多512、目录4096项/32层；单章5万文本片段。图片最长边8192、每图和全书累计不超过32M像素。会话派生文件总计不超过192 MiB，最多2个活动会话、1个在建任务。

支持受限CSS：保留普通书内样式、文字声明、内嵌字体和本书url资源，拒绝CSS导入、转义、活动表达式与竖排声明。SVG、MathML、音视频/媒体覆盖、固定版式、DTD/实体、加密/混淆字体等明确不支持；不尝试DRM解密。缺资源/目录片段、重复DOM ID或不支持类型明确失败，保留原件与旧位置。不声称完整EPUB符合性或所有图片/字体变体均通过。

脚本/base移除，事件/srcdoc/srcset等活动属性移除；不允许的外联src/href删除并给出提示。主机CSP禁止脚本、连接、frame/object/form/base，图/样式/字体仅限当前书籍会话host；独立WebKit内容规则与导航代理再次限制。所有可用地址改写为reader-book://随机会话/rN，不把原始容器路径交给原生资源处理器。远程或跨书请求不能借资源代理变成文件或网络读取。

macOS使用非持久WKWebsiteDataStore、WKURLSchemeHandler与AppKitView。原生资源队列最多128项、同时8项、单响应最多16 MiB、15秒超时；严格检查scheme/host/路径/查询/凭据，取消与销毁后不回复旧task。Dart每次资源/章节请求前后复查会话、分级、visibility代际、文件长度与摘要。原生页默认禁止正文JS；固定主机操作仅在defaultClient隔离world执行，无page-world消息入口或任意脚本方法。

## 原文与持久位置

净化后的正文按DOM文本节点建立不重叠的bN片段，长节点每2048 UTF-16单位拆分且不拆代理对。为这些节点注入主机属性，覆盖/移除书包伪造的同名属性。rt/rp与aria-hidden装饰不进入正文映射；保留简繁、emoji和组合字符原顺序；XML CRLF/CR统一为LF，CDATA与普通文本使用同一映射。桥接ready逐片段比较实际DOM与Dart规范文本，不匹配则拒绝继续。它不是完整CFI实现，不能跨解析器修订承诺相同片段ID。

选区可跨行内元素、段落与ruby，返回有序片段列表，最多32项、每项512单位、合计2048；Dart校验会话/spine、整数、UTF-16边界、顺序与每份exact，不信任网页回传摘录。原生与Dart共用同一规范文本，为后续检索/笔记/TTS提供映射；这些产品功能尚未在本步实现。

DocumentAnchor wire v1不变；revision是不可变解析documents.id，chapter=cN，spine_href为容器规范路径，block=bN。新解析文档与chapters同一事务写入，parser_version=epub-v1；相同原件/解析器再次打开复用该修订。直接复用schema6既有documents/chapters/positions，不增加空表或复制正文到SQLite。手动保存选区起点，未选字时保存当前可见片段起点；CAS沿用既有协议。精确恢复失败提示并保留旧记录，不自动覆盖；自动滚动进度/分页留MAC-09。

字号/主题变动前捕获内容锚点，字体与新布局完成后恢复同一范围；多片段选区恢复整个范围。原生视口独立布局并自行滚动正文，避免把AppKitView放进外层Flutter滚动区造成点击/辅助功能定位不稳定。主机操作8秒超时，Flutter调用10秒/初载25秒；Web进程退出会隐藏原生视图并提供重新加载本章，旧位置保留。

## 临时副本与隐私

epub-sessions/随机会话只存当前会话净化资源与有摘要的章节文本；关闭、取消、失败、锁定及应用正常释放时删除，持有单写入租约后的启动清理崩溃遗留。引用模式不创建永久托管原件。崩溃到下次启动之间可能残留临时文件，未来MAC-14/22备份必须排除该目录；本步不宣称这些文件有额外静态加密。

已打开会话读取一致的临时快照，原件会话中途移动不会自动切换文本；再次打开必须重新验证原件与授权。文件状态入口可检查/重新关联，检测内容改变后要求重导入；不无提示把旧位置套到新文件。

门禁覆盖目录、正文/资源与位置，不只依赖书架隐藏。隐私锁/资格作废同步退休会话、发起原生隐藏/销毁并清空图片缓存；阅读标题及已打开目录/图片弹窗也被遮蔽。18+搜索OFF不关闭已有作品阅读；App自身成年声明仍只有本机单份声明，不在生产库代用户确认。

## 平台、权限与验证

仅macOS原生渲染在本步实现，其他三端保留Flutter宿主和接口，显示尚未接入，不因本地解析器可运行就记为平台引擎验收。WKWebView需要网络子进程，Release新增network.client，与既有Debug一致；书内网络仍由上述多层规则拒绝，没有network.server、任意文件读取或新的来源请求能力。无新第三方运行包/原生插件，现有研究用epub_view/html不参与生产阅读。

首轮规则只匹配不带片段的rN地址，导致带空#的初载被WebKit以104拒绝；去掉空片段、允许本书rN可选片段后，实际加载与跳转通过。不能通过移除隔离规则来规避问题。

依据：[Apple scheme代理](https://developer.apple.com/documentation/webkit/wkurlschemehandler)、[禁止正文JS](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript)、[WebKit内容规则](https://webkit.org/blog/3476/content-blockers-first-look/)、[EPUB3.3规范](https://www.w3.org/TR/epub-33/)。版本支持与ABI同时对照本机固定Xcode SDK/Flutter源码。项目实测、故障场景、原生截图和保留范围见[本步验收](../verifications/mac-07-2026-10-22.md)。
