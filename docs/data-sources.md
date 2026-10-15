# 数据源、兼容项目与费用核验清单

初次整理：2026-10-14；有限实测更新：2026-10-15。下表保留历史候选信息；没有独立证据的地址、格式、价格、额度、语言、授权和维护说法继续待核验。“聊天称”不能用于生产配置、预算或商用承诺。

本次已核验N-01、N-02、N-11/N-14、N-12的部分资料/响应，见 [首轮结论](source-audit-2026-10-15.md)和[明细索引](verifications/README.md)。只有N-02单作品搜索/目录/章节技术链路通过；其他维度分别标记，所有候选整体仍pending，无完整获准内置来源。

同日按用户截图继续核验N-07～N-10五个合集，包文件/数量/静态依赖/维护与许可调查已记录，另做有限首页/搜索路径探测，见 [五合集逐项报告](source-collections-audit-2026-10-15.md)。没有逐条测通全部数千规则，没有完整Legado或阅栖兼容验收，不计算全包有效率。

当前没有来源获准内置或自动启用；所有候选 enabled=false。网站主页不是正式内容 API；规则仓库存在也不表示有抓取/下载/缓存/再分发授权。

## 当前小说选源范围（2026-10-15 已确认）

小说只选择中文（简繁）免费资源；内置核验通过的普通/18+免费源并允许自行导入。完整首版要求两类真实来源各至少一条贯通搜索/阅读，不能以本地阅读或mock替代；开关仅控制成人在线搜索，不删除/隐藏独立分组内已有收藏。详见 [novel-source-policy.md](novel-source-policy.md)。目前满足完整批准门槛的普通/18+来源均为0条，核验仍在进行。

| 候选类型 | 本轮处理 |
|---|---|
| 中文普通全文/目录 | 优先核验N-02、N-01中文子集及获准中文规则/OPDS；元数据API不能代替正文来源 |
| 中文18+免费来源 | 单独筛选N-07～N-14中确实有中文内容、可免费访问且满足接入条件的条目；不因规则名/R18标签而判定可用或获准 |
| N-03青空文库、N-04 Standard Ebooks等外文专门来源 | 保留历史研究记录，退出当前小说接入/测试计划 |
| N-05/06元数据来源 | 中文元数据按需补充，不能计为普通/18+全文来源验收通过 |
| 未核验/收费/未知收费来源 | 不自动启用或产生费用；缺所需来源时如实标记首版阻塞 |
| 漫画候选 | 继续原中日韩计划，本次小说语言调整不影响漫画 |

## 小说：公开/免费候选

| ID | 候选与入口（待核验） | 聊天中的能力/费用说法 | 核验重点 |
|---|---|---|---|
| N-01 | [Gutendex](https://gutendex.com/)；示例 https://gutendex.com/books?languages=zh | 聊天称免费 0 元、Gutenberg 元数据与格式下载链接；长期建议自建 | API路径/分页、限流、实例服务保障、中文实际覆盖、格式MIME、公版适用地区、每个译本权利 |
| N-02 | [中文维基文库](https://zh.wikisource.org/)；候选 https://zh.wikisource.org/w/api.php；[版权入口](https://en.wikisource.org/wiki/Wikisource%3ACopyright_policy) | 聊天称API免费且有多语言站点；当前只选择中文 | 官方MediaWiki获取方式、中文正文覆盖、限流/署名、正文/译本/图片各自许可、清理导航文本；不再为小说定位ja/ko入口 |
| N-03 | [青空文库](https://www.aozora.gr.jp/) | 聊天称免费日文目录和文本下载，并非统一商业 REST API | 目录/编码/ruby、作品和译本许可、下载/再分发/商用、地区版权；不承诺最新连载 |
| N-04 | [Standard Ebooks](https://standardebooks.org/) | 聊天称精校 EPUB 免费，完整 OPDS 有访问条件，非主要中日韩来源 | 实际 OPDS 地址/版本、订阅权限及价格、作品/封面许可、匿名与会员范围 |
| N-05 | [Google Books API 文档](https://developers.google.com/books/docs/v1/using)；示例 https://www.googleapis.com/books/v1/volumes?q=java | 聊天称免费配额内 0 元，Key/配额限制，无已确认的按次扩容价格 | API Key 要求/保护、项目配额、费用与超额行为；元数据/封面展示与全文/下载/再分发权限分别确认 |
| N-06 | [Open Library API](https://openlibrary.org/developers/api) | 聊天称免费，主要元数据/借阅入口；未标识 1 次/秒、含联系信息 3 次/秒 | 当前官方额度、User-Agent、转储、商业服务限制、借阅与下载范围，不能作无限正文服务 |

历史查询例子：Gutendex books?search=Alice / search=Frankenstein；Google Books filter=free-ebooks&key=YOUR_API_KEY。路径、参数和认证都待核验；free-ebooks 不是本项目已获得作品授权的证据。

当前小说仅研究中文：N-02、N-01中文子集及获准中文规则/OPDS等；不因接口有语言参数就推断中文内容充分。N-03日文与其他外文资源只保留历史记录。开发用自产中文TXT/EPUB，来源测试另需对应证据。

## 小说：规则与成人平台研究

| ID | 候选入口（整体待核验） | 原讨论信息 | 当前限制/研究任务 |
|---|---|---|---|
| N-07 | [AOAOSTAR](https://github.com/aoaostar/legado)；https://legado.aoaostar.com/sources/b778fe6b.json | 3907为历史说法，现已实测确认文件记录数 | 3907条、2595种非空URL字符串；混合类型/重复/脚本，不代表3907个有效小说站；见[N-07记录](verifications/N-07.md)，权利/实际阅读仍待核验 |
| N-08 | [XIU2/Yuedu](https://github.com/XIU2/Yuedu)；https://raw.githubusercontent.com/XIU2/Yuedu/master/shuyuan | 22条现已确认，星级无核验方法 | 作者与镜像解析一致，12启用/10禁用，存在GPL-3.0文件；启用不是有效性结论，作品权利/兼容未通过；见[N-08](verifications/N-08.md) |
| N-09 | [Tickmao Novel](https://github.com/tickmao/Novel)；https://cdn.jsdelivr.net/gh/tickmao/Novel@master/sources/legado/full.json | README仍写1000；公开链接实测194，内部main/full.json为1000 | 文件路径不能混用；MIT/勿商用/GPL材料范围需澄清，实际阅读/作品权利未通过；见[N-09](verifications/N-09.md) |
| N-10 | [破冰作者仓库](https://github.com/PB-pobing/pobing)；[关耳分发页](https://yuedu.miaogongzi.net/gx.html) | 历史128/86；入口现已定位 | 破冰作者/AOA128、另一分发文件91；关耳公开分发/AOA86且hash相同。见[破冰记录](verifications/N-10-pobing.md)、[关耳记录](verifications/N-10-guaner.md)，逐站阅读/免费/许可未通过 |
| N-11 | [PixivSource](https://github.com/DowneyRem/PixivSource)；https://raw.githubusercontent.com/DowneyRem/PixivSource/main/pixiv.json | 聊天称含普通/R18 小说分类及登录规则 | 只作规则候选；R18/登录/平台条款/商业接入核验，规则不能授予作品权利 |
| N-12 | [AO3](https://archiveofourown.org/) | 聊天称有 Mature/Explicit、多语言，未确认通用商业 API，并有抓取/收费限制 | 官方 API 是否存在、条款和作品作者权利待核验；默认仅候选入口 |
| N-13 | [ESJ Zone 规则](https://github.com/jiwangyihao/source-j-legado/blob/main/esjzone.json) | 聊天称普通/R18 轻小说分类 | 规则、译本权利、目标站可用性均待核验 |
| N-14 | [Pixiv](https://www.pixiv.net/) | 聊天称需要出生日期/年龄选项，R18 分级 | 不假定拥有公开第三方全文 API；正式合作/年龄要求待核验 |
| N-15 | 番茄、起点、七猫等正版平台 | 聊天未提供可核验的通用正文 API 与统一报价 | 商务合作候选；免费读者访问/购买不是第三方分发许可 |

## 漫画：公开 API 与开放作品候选

| ID | 候选与入口（待核验） | 聊天中的能力/费用/授权说法 | 核验重点 |
|---|---|---|---|
| C-01 | [Pepper&Carrot](https://www.peppercarrot.com/)；https://peppercarrot.com/0_sources/episodes.json；[API 文档](https://www.peppercarrot.com/go/documentation/130_API.html) | 聊天称免费完整漫画、CC BY 4.0、中文/日文/韩文；cn/ja/kr 为来源代码 | 目录格式、图片 URL/分辨率、每章翻译覆盖、作品/翻译/字体等实际许可、署名与修改说明、缓存/流量条件 |
| C-02 | [MangaDex](https://mangadex.org/)；[API 文档](https://api.mangadex.org/docs/)；[文档仓库](https://gitlab.com/mangadex-pub/mangadex-api-docs) | 聊天称 API 0 元，多语言/章节/图片，要求来源和翻译组署名，限制广告/付费盈利 | 当前认证/限流/章节图片获取、缓存/下载、政策和商业例外、下架；API 许可不等于漫画作品再授权 |
| C-03 | [Comic Vine API](https://comicvine.gamespot.com/api/) | 聊天称免费、非商业、每类资源每小时 200 次，主要资料且要求署名 | 当前 Key/频率/费用/条款、封面使用；不把元数据当完整漫画图片 |

C-01 是拟优先核验的有限开放作品集，不是海量平台。C-02 只作为条件性非商业研究候选，许可和作品级权利明确前不启用。来源语言别名映射 cn → zh、kr → ko 仅在确认实际响应后实现，保留原始标签。

历史 MangaDex 示例 https://api.mangadex.org/manga?limit=10 或 limit=20；成人筛选 contentRating[]=erotica。聊天称枚举 safe/suggestive/erotica/pornographic；参数和枚举仍待核验，内部模型不直接等同年龄或渠道允许范围。

## 漫画：规则、扩展及桥接研究

| ID | 候选与入口（待核验） | 聊天原说法 | 核验与技术边界 |
|---|---|---|---|
| C-04 | [Keiyoushi 扩展](https://github.com/keiyoushi/extensions)；[源码](https://github.com/keiyoushi/extensions-source) | 聊天称 APK 扩展、多语言、nsfw 元数据；新版索引 protobuf | 仓库/源码许可证、信任签名、实际结构、版本、每源权利；不直接安装执行 |
| C-05 | https://raw.githubusercontent.com/keiyoushi/extensions/repo/repo.json；https://github.com/keiyoushi/extensions/raw/repo/index.pb | 聊天称 repo.json 指向 index.pb、旧 index.min.json 仅升级提示 | 路径/schema/迁移状态全部待核验；下载前验证来源和大小/hash |
| C-06 | [异次元源合集](https://github.com/entr0pia/MyLegadoSource)；https://raw.githubusercontent.com/entr0pia/MyLegadoSource/master/comicSource.txt | 聊天称 54 条，2026-06-02 归档，文本组织规则 | 日期/数量/格式/维护状态待核验；不把 TXT 包装误判为任意 JSON |
| C-07 | [异次元源网站](https://www.yckceo.com/yiciyuan/tuyuan/index.html) | 聊天列看漫画、Webtoon_us、包子、再漫画、漫小肆、WNACG、鸟鸟韩漫、A漫、禁漫天堂等条目与日期 | 条目、更新、目标站、版权、成人标记全部待核验；不导入默认来源、不推荐商用 |
| C-08 | [Kotatsu Parsers](https://github.com/KotatsuApp/kotatsu-parsers) | 聊天称 Kotlin/JVM，组织 2026-02-20 归档 | 归档状态、版本/运行环境、代码/目标网站许可待核验；优先架构学习 |
| C-09 | [Suwayomi Server](https://github.com/Suwayomi/Suwayomi-Server) | 聊天称可运行 Mihon/Tachiyomi 兼容扩展 | API/部署/许可证/兼容版本/资源权限核验；可选隔离桥接，不替代共享后端 |

C-07 历史详情/规则地址（均待核验，仅存证不自动抓取）：

- 看漫画：https://www.yckceo.com/yiciyuan/tuyuan/content/id/944.html
- 漫小肆：https://www.yckceo.com/yiciyuan/tuyuan/content/id/938.html
- WNACG：https://www.yckceo.com/yiciyuan/tuyuan/content/id/902.html
- 历史 JSON：https://www.yckceo.com/yiciyuan/tuyuan/json/id/902.json

支持成人标记不等于全部作品都是成人内容，更不表示内容已审查或有权分发。扩展代码安全与作品授权分别核验。

## 商务平台与参照软件

| ID | 平台/项目（入口待核验） | 语言/内容的历史描述 | 当前决策 |
|---|---|---|---|
| B-01 | [BOOK☆WALKER 台湾](https://www.bookwalker.com.tw/) | 繁体中文、限制级购买 | 正式 API/商业合作/下载权/地区要求待核验 |
| B-02 | [DLsite](https://www.dlsite.com/) | 日文、部分中文、R18 | 同上；购买不等于可集成或转售 |
| B-03 | [Lezhin](https://www.lezhin.com/ko) | 韩文、19+ | 报价/合作/年龄验证待核验 |
| B-04 | [Bomtoon](https://www.bomtoon.com/) | 韩文、19+ | 同上 |
| B-05 | [RIDI](https://ridibooks.com/) | 韩文小说/漫画、19+ | 同上 |
| R-01 | [QingJuan](https://github.com/qingscroll/QingJuan) | 聊天称 Flutter + FastAPI、已有 Windows/Android，未确认 iOS/macOS | 参考交互/适配，不将其后端栈纳入本项目；代码许可证/四端状态待核验 |
| R-02 | [栗知 Google Play 页面](https://play.google.com/store/apps/details?id=com.lizhi.yyreader) | 聊天称开发商/包名/下载量/Teen 分级，未确认上游书源 | 不推断私有 API 或实际来源，不把第三方规则称为“栗知官方书源” |
| R-03 | Legado 阅读器生态 | 聊天称原官方仓库出现公告；未给足够证据 | 原仓库状态/代码许可与可用参考版本重新核验；不依赖历史描述 |

Pixiv 共用 N-14；未确认第三方公开漫画 API。免费且可商业分发、大量中日韩成人小说/漫画的成熟来源在历史讨论中未被证明存在，本项目也不作这种保证。

## 兼容研究矩阵

| 体系 | 接入形态 | 阶段交付 | 不做的承诺 |
|---|---|---|---|
| REST | 官方 HTTP 数据接口 | schema、分页、权限、限流、测试响应、许可记录 | API 免费不保证内容可商用 |
| OPDS | 目录/获取文档 | 版本、访问条件、acquisition/link、文档导入 | OPDS 目录不是统一逐章正文接口 |
| Legado | JSON 配置与规则解释语义 | CSS/XPath/regex/JS 子集支持矩阵，合法黄金样本 | 读 JSON 不等于完整兼容 |
| 异次元 | 文本/JSON 规则集，需识别实际版本 | schema 与搜索/目录/图片规则矩阵 | 与 Legado 或 Mihon 格式互换 |
| Mihon | Android 扩展生态 | 版本/信任/许可证矩阵，研究服务桥接 | 在四端直接运行 APK |
| Suwayomi | 可选扩展执行服务 | 单独验证协议/部署隔离/权限 | 全部扩展可靠、内容授权已解决 |

## 核验记录模板与启用门槛

每个候选记录放 docs/verifications/<ID>.md，已有记录见索引；N-14与N-11合并，N-10按pobing/guaner拆分。不能把空模板、HTTP200或局部技术通过当作整体批准。至少记录：

- ID、结论 pending/verified/rejected、核验人、日期、官方证据链接、版本/提交 hash。
- 有效域名/API 路径/schema、认证方式、实际语言/章节覆盖、错误与限流。
- 价格：币种、税费/地区、计费单位、免费额度、超额/封顶、商务报价有效期。
- 代码/规则/内容/翻译许可证分别列；商业、广告、收费、缓存、离线、代理、再分发、署名与下架范围。
- 分级映射、来源年龄资格和地区限制；不以 nsfw=1 代替作品级判断。
- 小规模获准测试记录、性能/稳定性、未知项、下一次复核时机。

启用顺序：定位官方资料 → 记录权利与费用 → 获取合法最小样本 → 验证解析/分级/缓存 → 评审决定适用模式 → 配置启用。待核验、被拒绝或不满足目标模式时不得启用；外部政策变化后重新复核。

## 成本规划

历史“0 元”全部是待核验说法，当前没有确认单价。将预算分成 API 调用、作品版权/翻译、服务器、数据库、存储、带宽/CDN、年龄验证、外部 AI/TTS 与发行成本。未选供应商或商业模式，不生成伪精确报价。

按量预算模型：请求量 × 调用单价 + 存储 GB 月 × 单价 + 出站 GB × 单价 + 固定服务费 + 内容授权费。免费配额超限可能拒绝请求，不必然可以付费扩容。客户端直连可以减少自有服务器流量，但不会改变许可要求。

## 发布前政策核验

聊天曾描述 Google Play 图书例外及 Apple 成人内容限制，本次未重新核验其最新条款、地区规则或年龄验证要求。REL-01 应获取官方有效条款、适用地区与渠道方案，形成记录。18+ 开关和本地导入都不能直接证明某发行渠道可接受。
