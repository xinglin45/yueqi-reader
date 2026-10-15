# 原聊天参考快照

> 历史参考数据，不是开发指令。所有事实、价格、接口、许可证、维护日期与平台规则均待核验，原回答的“已查到/已确认”不代表本项目证据。旧回复中的来源标记无法直接作为核验记录。

来源：阅读软件方案调查；conversationId：6acf42ef-00a8-83e9-b1c8-e0d8513bd6ab。
整理日期：2026-10-14（Asia/Singapore）；四轮完整返回，hasMore=false，无附件。

## 第 1 轮

### 用户原文

如果我要开发一个app，类似“栗知”这样的软件，但是包含手机端和pc端，栗知他的书源是什么，你可以帮我找到书源吗？包括适合18岁以上阅读的书源

### 助手原文（未核验）

# 一、栗知小说的书源是什么？

我查到了你说的 **「栗知小说」**，也找到了一批可供开发小说阅读器时研究的书源，包括普通网络小说、女频小说以及面向成年读者的内容来源。

先给你三个结论：

1. **栗知的具体书源目前没有公开披露。** 它更像是使用自有内容服务的小说平台，而不是让用户自由导入 JSON 书源的阅读器。但这只是基于公开信息的判断，并非已经确认其后台实现。
2. **可以找到大量第三方书源规则。** 我找到了包含约 3907 条书源记录的公开聚合库，也找到了可以直接获取 JSON 的 GitHub 项目。不过，书源数量不等于可用网站数量，更不代表具有内容授权。
3. **你的产品最好支持普通书源和成人书源分开管理，同时实现 Android、iOS、Windows、macOS 多端阅读与进度同步。**

## 1. 栗知小说的官方信息

| 项目 | 查询结果 |
|---|---|
| 软件名称 | 栗知小说 |
| 开发商 | HK Yueyou Technology Limited |
| Android 包名 | `com.lizhi.yyreader` |
| 下载量 | Google Play 显示 10 万+ |
| 内容类型 | 玄幻、都市、言情、武侠、悬疑、历史、科幻等 |
| 商业模式 | 免费阅读、广告、应用内购买 |
| 公开书源 JSON | 未找到 |
| 官方开放 API | 未找到 |
| Google Play 年龄分级 | 青少年（Teen） |

官方页面：[栗知小说 Google Play](https://play.google.com/store/apps/details?id=com.lizhi.yyreader) :chatgpt-content-reference{index="0"}

需要特别说明，**栗知不一定使用普通阅读器那种「书源 JSON」机制**。

小说软件通常有两种架构。

**模式 A：平台型阅读器**

```text
Android / iOS 客户端
          │
          ▼
      平台 API
          │
          ▼
     小说内容服务
          │
          ├── 自有作品
          ├── 合作方授权内容
          └── 其他合法内容渠道
```

**模式 B：可配置书源阅读器**

```text
Android / iOS / PC
          │
          ▼
       书源管理器
          │
          ├── 书源 A
          ├── 书源 B
          ├── 书源 C
          └── 本地 EPUB / TXT
                 │
                 ▼
          统一解析与阅读
```

栗知的公开资料没有给出足够信息判断它实际使用哪些上游站点，也不能证明它采用了哪种内部架构。

而对于你要开发的软件，我更推荐 **模式 B + 自有后端服务**，这样可以自由扩展书源，并实现多端同步。

## 二、找到的小说书源，可以直接访问

以下是我找到的书源仓库和实际 JSON 地址。

这些地址适合用于**研究书源格式、开发兼容解析器，以及在具备相应访问和使用权限时进行测试**。它们并不是栗知官方书源。

### 1. 普通小说书源

| 书源 | 公开记录数量 | 特点 | 推荐程度 |
|---|---:|---|---|
| AOAOSTAR 全量书源 | 3907 | 大型聚合库，覆盖多种小说网站 | ⭐⭐⭐⭐⭐ |
| XIU2 精品书源 | 22 | 精选书源，适合研究解析规则 | ⭐⭐⭐⭐⭐ |
| Tickmao Novel | 1000 | 提供 Legado JSON 和其他阅读器配置 | ⭐⭐⭐⭐⭐ |
| 破冰书源 | 128 | 老牌书源集合 | ⭐⭐⭐⭐ |
| 关耳女频 | 86 | 偏向女性阅读题材 | ⭐⭐⭐⭐ |

以上是仓库公布的记录数量，并非逐个实测的有效数量。AOAOSTAR 页面在 2026 年 10 月 14 日显示全量书源同步成功，但部分其他集合已同步失败。:chatgpt-content-reference{index="1"}

**① AOAOSTAR 全量书源**

GitHub：

https://github.com/aoaostar/legado

JSON 直链：

https://legado.aoaostar.com/sources/b778fe6b.json

**② XIU2 精品书源**

GitHub：

https://github.com/XIU2/Yuedu

JSON 地址：

https://raw.githubusercontent.com/XIU2/Yuedu/master/shuyuan

**③ Tickmao 小说书源**

GitHub：

https://github.com/tickmao/Novel

JSON 地址：

https://cdn.jsdelivr.net/gh/tickmao/Novel@master/sources/legado/full.json

其中，Tickmao 仓库还有适用于 iOS 阅读器的其他格式配置。:chatgpt-content-reference{index="2"}

建议开发时优先研究 XIU2 和 Tickmao，它们更适合作为书源规则格式的学习样本。

---

## 三、18 岁以上的小说书源

这一部分需要区分两类：

- **成人向小说**：包含成熟爱情、暴力、恐怖、复杂社会题材等内容。
- **R18 小说**：包含明确的成人性描写或其他受年龄限制的内容。

目前找到以下来源。

### 1. Pixiv 小说书源：有现成的 JSON

这是目前找到的成人向书源中，最值得研究的项目之一。

**项目：PixivSource**

GitHub：

https://github.com/DowneyRem/PixivSource

JSON 直链：

https://raw.githubusercontent.com/DowneyRem/PixivSource/main/pixiv.json

项目提供的功能包括：

| 功能 | 支持情况 |
|---|---|
| 普通小说搜索 | 支持 |
| R18 小说分类 | 有对应规则 |
| 成人小说排行榜 | 有对应规则 |
| 小说收藏 | 有对应规则 |
| 小说追更 | 有对应规则 |
| 中文界面相关配置 | 支持 |
| JSON 书源 | 支持 |
| 是否需要登录 | 部分功能需要 |
| 商业 App 接入授权 | 未确认 |

我检查了项目中的 `pixiv.json`，其中确实定义了 `R18` 的分类、推荐、排行榜等规则。:chatgpt-content-reference{index="3"}

Pixiv 官方也明确支持小说 R18 分级。

用户需要年满 18 岁，设置出生日期，并开启对应浏览选项，才能访问受年龄限制的作品。:chatgpt-content-reference{index="4"}

但需要注意：**第三方 JSON 规则的存在，不代表 Pixiv 允许你的 App 自由抓取或重新分发作品。**

### 2. AO3：国际成人向小说与同人作品

网站：

https://archiveofourown.org/

特点：

| 项目 | 说明 |
|---|---|
| 小说类型 | 原创、同人、爱情、奇幻等 |
| 成人内容 | 包含成熟及明确成人分级的作品 |
| 语言 | 多语言，包含中文 |
| 标题搜索 | 支持 |
| 标签检索 | 支持 |
| 书源 JSON | 本次未找到可确认有效的现成配置 |
| 官方公开商业 API | 未确认 |

AO3 可以作为成人向内容平台的研究对象。

不过，它的条款明确禁止通过抓取建立托管 AO3 内容或对这些内容收费的应用。因此，如果你开发商业阅读器，不应直接采集 AO3 正文并放到自己的服务器上分发。:chatgpt-content-reference{index="5"}

### 3. ESJ Zone：轻小说与 R18 分类

找到一个现成的 Legado 书源规则：

https://github.com/jiwangyihao/source-j-legado/blob/main/esjzone.json

该规则包含普通轻小说分类及 R18 分类入口。:chatgpt-content-reference{index="6"}

但其网站访问状态、翻译作品授权及规则当前可用性尚未逐项验证，所以只建议作为技术研究样本。

### 4. 更适合正规接入的电子书来源

另外找到两个适合做公开内容测试的服务。

| 来源 | 内容类型 | 接入方式 |
|---|---|---|
| [Gutendex](https://gutendex.com/) | Project Gutenberg 电子书元数据 | REST JSON API |
| [Standard Ebooks](https://standardebooks.org/) | 精校公版电子书 | OPDS |

例如 Gutendex 可以直接访问：

```http
GET https://gutendex.com/books?languages=zh
```

也可以根据书名搜索：

```http
GET https://gutendex.com/books?search=Frankenstein
```

其官方文档建议长期使用时自行部署 API 服务。Gutenberg 图书的版权状态也需要根据目标发行地区判断。:chatgpt-content-reference{index="7"}

Standard Ebooks 的完整 OPDS 目录通常需要会员或其他符合条件的访问权限，并非完全开放的匿名接口。:chatgpt-content-reference{index="8"}

---

## 四、如果要开发手机 + PC 阅读器，采用什么技术方案？

考虑到你熟悉 Java、Spring Boot，且需要 Android、iOS、Windows、macOS，我建议使用下面的架构。

```text
              小说阅读系统
                   │
       ┌───────────┴───────────┐
       │                       │
   Flutter 客户端          Java 后端
       │                       │
   ┌───┼────────┐        Spring Boot
   │   │        │              │
Android iOS   PC端        ┌────┴────┐
            Win/Mac       │         │
                       用户服务   书源服务
                          │         │
                          │      规则解析器
                          │         │
                          │    ┌────┼────┐
                          │    │    │    │
                          │   JSON OPDS 授权API
                          │
                      MySQL + Redis
```

### 最关键的是书源解析引擎

建议采用插件式架构，所有书源都转换成统一的数据结构：

```java
public interface BookSource {

    // 根据关键字搜索书籍
    List<Book> search(String keyword);

    // 获取书籍详情
    Book getBookInfo(String bookId);

    // 获取章节目录
    List<Chapter> getChapters(String bookId);

    // 获取章节内容
    String getChapterContent(String chapterId);
}
```

然后增加不同适配器：

```text
BookSource
    │
    ├── LegadoJsonSource
    │
    ├── OpdsSource
    │
    ├── LicensedApiSource
    │
    └── LocalBookSource
```

客户端不需要关心小说来自哪里，只需要调用统一接口。

特别需要注意，Legado 书源可能包含 JavaScript 规则，不能直接把不可信 JSON 中的脚本放到 Spring Boot JVM 内无限制执行。建议使用沙箱、资源限额、域名白名单及 SSRF 防护。

### 可以直接参考的开源项目

我还找到一个比较接近你需求的项目：

**青卷 QingJuan**

GitHub：https://github.com/qingscroll/QingJuan

它采用 Flutter + FastAPI，已经实现 Windows、Android 客户端以及远程后端连接。

现有功能包括书源导入、章节下载、阅读进度同步、离线阅读、翻译等。暂未看到它支持 iOS 和 macOS 的正式发行版本。:chatgpt-content-reference{index="9"}

你可以重点研究它的多端交互和书源适配设计，然后根据自己的技术栈改为 Java 后端。

---

## 五、开发前需要特别注意的两个问题

### 1. 版权问题

有一条值得关注的最新情况。

截至 2026 年 10 月 14 日，著名开源阅读器 Legado 的原官方 GitHub 仓库已经删除原项目内容，页面显示了一份涉及侵权行为的公告。:chatgpt-content-reference{index="10"}

因此，**不建议将聚合到的数千条第三方书源直接作为商业 App 的内置内容来源**。

更合适的商业方案是以授权内容、公版图书和用户有权访问的个人文档为主。

### 2. 成人内容与应用商店

这部分直接影响你的发布方案。

Google Play 对电子书目录类应用有一定例外，但要求涉及性内容的书籍仅占较小比例、不能主动推广，并须限制未成年人访问。色情内容及违法内容仍然禁止分发。Apple App Store 也对露骨色情材料有明确限制。:chatgpt-content-reference{index="11"}

因此，即使应用设置为 18+，也不代表能够在应用商店自由发布所有成人内容。还需要根据发行地区的法律及商店政策确定内容范围。

---

## 六、我的最终建议

你的产品可以分成三个核心模块：

| 模块 | 核心功能 | 优先级 |
|---|---|---|
| 小说阅读器 | 书架、搜索、目录、阅读、听书 | P0 |
| 书源中心 | 导入 JSON、书源检测、统一搜索、规则管理 | P0 |
| 多端同步 | 书架同步、阅读进度、书签、离线阅读 | P0 |
| 本地书库 | TXT、EPUB、PDF 导入 | P0 |
| 书源扩展 | OPDS、授权 API、个性化规则 | P1 |
| 成人内容管理 | 内容分级、年龄验证、过滤机制 | P1 |
| 智能阅读 | AI 翻译、摘要、人物关系整理 | P2 |

**我建议第一版以 Flutter + Spring Boot 为核心，先支持 Legado JSON、OPDS 和本地书籍，优先实现 Android、Windows、macOS，再完善 iOS 端。**

最后，我还需要确认一个会直接影响整个产品设计的问题：

**你准备开发的阅读器是自己使用，还是准备公开发布给其他用户使用？**

因为这会决定书源的接入方式、版权方案、成人内容的处理，以及后端是否需要统一获取小说正文。

## 第 2 轮

### 用户原文

漫画源可以帮我找到吗？同样包括适合18岁以上阅读的，中文、韩文、日文都可以

### 助手原文（未核验）

# 📚 漫画源整理：中文、日文、韩文及 18+ 成人漫画

找到了。相比小说书源，**漫画源有一套更成熟的开源生态，尤其是 Mihon（原 Tachiyomi 生态）和异次元漫画源**。

考虑到你准备开发一款同时支持 Android、iOS、Windows、macOS 的小说 + 漫画阅读器，我建议重点关注以下三种资源：

- **漫画扩展仓库**：直接提供漫画网站适配器，部分包含 18+ 漫画源。
- **漫画源配置文件**：类似小说书源 JSON，适合研究并实现自己的解析引擎。
- **漫画内容平台**：包含正版中文、日文、韩文及 R18、19+ 内容，但通常需要登录或购买，不一定开放第三方 API。

## 一、最值得收藏的漫画源仓库

| 漫画源项目 | 来源语言 | 成人源 | 源格式 | 推荐指数 |
|---|---|---|---|---|
| **Keiyoushi Extensions** | 中文、日文、韩文等多语言 | 包含成人分级扩展 | APK / 扩展索引 | ⭐⭐⭐⭐⭐ |
| **异次元漫画源合集** | 以中文为主 | 需逐条检查 | TXT | ⭐⭐⭐⭐ |
| **Kotatsu Parsers** | 多语言 | 源级别支持情况需核实 | Kotlin/JVM | ⭐⭐⭐⭐ |
| **MangaDex** | 多语言翻译漫画 | 包含成人分级元数据 | REST API | ⭐⭐⭐⭐⭐ |
| **Suwayomi Server** | 取决于安装的扩展 | 取决于安装的扩展 | 服务端/扩展 | ⭐⭐⭐⭐⭐ |

这里的成人源是指仓库允许包含 NSFW 或成人分级的漫画来源，不代表所有扩展都提供成人漫画，也不代表实际内容已经逐一验证。

### 1. Keiyoushi：优先研究

GitHub 仓库：

https://github.com/keiyoushi/extensions

扩展源码：

https://github.com/keiyoushi/extensions-source

最新仓库元信息：

https://raw.githubusercontent.com/keiyoushi/extensions/repo/repo.json

新版扩展索引：

https://github.com/keiyoushi/extensions/raw/repo/index.pb

**这个项目非常适合研究，因为它已经提供了不同漫画网站的适配代码。**

常见扩展元数据包含：

```json
{
  "name": "Example Manga Source",
  "lang": "ja",
  "nsfw": 1,
  "sources": [
    {
      "name": "Example",
      "lang": "ja",
      "baseUrl": "https://example.com"
    }
  ]
}
```

上面是说明字段含义的示意 JSON，并不是仓库中的真实扩展。

其中：

| 字段 | 用途 |
|---|---|
| `name` | 扩展名称 |
| `lang` | 语言代码，如 `zh`、`ja`、`ko` |
| `nsfw` | 扩展的成人内容标记 |
| `sources` | 扩展提供的实际漫画来源 |
| `baseUrl` | 对应网站地址 |

开发时可以利用这些元数据做语言筛选、内容分级和书源管理。

**一个重要的版本提醒：** 我检查了旧版 `index.min.json`，目前它实际上只有两个升级提示项目，并不是完整漫画源列表。因此不要直接把网上教程中的旧 JSON 地址当成有效的完整漫画源。

新版仓库使用 `repo.json` 指向 `index.pb`，这也是你设计自己书源系统时值得考虑的兼容问题。:chatgpt-content-reference{index="0"}

### 2. 异次元漫画：直接提供漫画源文件

GitHub：

https://github.com/entr0pia/MyLegadoSource

漫画源直链：

https://raw.githubusercontent.com/entr0pia/MyLegadoSource/master/comicSource.txt

该仓库收集了 **54 个异次元漫画源**。

与 Mihon 不同，它采用文本格式组织漫画源规则，更适合研究配置驱动的解析方式。

但这个仓库已于 **2026 年 6 月 2 日归档**，不再维护，不能保证其中的网站依然可访问。:chatgpt-content-reference{index="1"}

### 3. Kotatsu Parsers：适合 Java 技术栈

GitHub：

https://github.com/KotatsuApp/kotatsu-parsers

这是一个 Kotlin/JVM 漫画解析库。

它的优势是能够运行在 JVM 环境中，与你熟悉的 Java 生态比较接近。

例如：

```kotlin
val parser = mangaLoaderContext.newParserInstance(
    MangaParserSource.MANGADEX
)
```

不过，Kotatsu 组织已于 **2026 年 2 月 20 日归档**，现在不再维护。因此它适合用来学习解析器架构，但不建议直接作为长期生产依赖。:chatgpt-content-reference{index="2"}

## 二、发现一个更实用的中文漫画源网站

这次找到了一个正在更新的漫画源仓库，其中明确列有普通漫画、韩漫以及 18+ 漫画源。

### 异次元漫画源仓库

**访问地址：**

https://www.yckceo.com/yiciyuan/tuyuan/index.html

该网站提供漫画源详情页，以及部分源的 JSON 下载功能。

截至 2026 年 10 月 14 日，页面上能找到这些来源：

| 漫画源 | 语言或内容特点 | 18+ | 最近显示的更新时间 |
|---|---|---|---|
| 看漫画（漫画柜） | 中文漫画 | 非专门成人源 | 10 月 |
| Webtoon_us | 英文版韩漫 | 非专门成人源 | 10 月 |
| 包子漫画 | 中文漫画 | 非专门成人源 | 8 月 |
| 再漫画 | 中文漫画 | 非专门成人源 | 2025 年 11 月 |
| **漫小肆韩漫** | 中文韩漫 | ✅ | 9 月 |
| **绅士漫画 WNACG** | 中文、日漫、韩漫分类 | ✅ | 9 月 |
| **鸟鸟韩漫** | 中文韩漫 | 成人内容需要逐项确认 | 8 月 |
| **A漫** | 成人向漫画 | ✅ | 8 月 |
| **禁漫天堂** | 成人向漫画 | ✅ | 8 月 |

这些信息来自漫画源仓库当前展示的条目，**不是我已经测试通过的源**。部分网站可能需要特定网络环境，也可能存在失效、版权或安全风险。:chatgpt-content-reference{index="3"}

### 可以直接打开的具体书源

**① 看漫画（漫画柜）**

书源详情：

https://www.yckceo.com/yiciyuan/tuyuan/content/id/944.html

**② 漫小肆韩漫 🔞**

书源详情：

https://www.yckceo.com/yiciyuan/tuyuan/content/id/938.html

**③ 绅士漫画 WNACG 🔞**

书源详情：

https://www.yckceo.com/yiciyuan/tuyuan/content/id/902.html

**已经确认能够获取 JSON 的直链：**

https://www.yckceo.com/yiciyuan/tuyuan/json/id/902.json

我实际打开了这个 JSON，确认里面包含漫画搜索、目录、图片地址解析等规则。页面作者还说明，该来源需要特定网络环境，且曾出现搜索规则失效的问题。:chatgpt-content-reference{index="4"}

这意味着它可以作为你的漫画解析引擎的测试样本，但仍需要检查具体规则的兼容性和目标网站的使用许可。

---

## 三、中文、日文、韩文的正规成人漫画平台

如果希望漫画内容更稳定，尤其是长期使用，那么这些提供正式成人分级的出版平台也值得关注。

| 平台 | 主要语言 | 18+ 内容 | 是否有现成的公开通用漫画 API |
|---|---|---|---|
| **BOOK☆WALKER 台湾** | 繁体中文 | ✅ 限制级馆 | 未确认 |
| **Pixiv** | 日文、中文等 | ✅ R18/R18G | 未确认适用的公开漫画 API |
| **DLsite** | 日文、部分中文 | ✅ R18 | 未确认 |
| **Lezhin Comics** | 韩文、英文等 | ✅ 韩国 19+ | 未确认 |
| **Bomtoon** | 韩文 | ✅ 韩国 19+ | 未确认 |
| **RIDI** | 韩文 | ✅ 韩国 19+ | 未确认 |

这里的“未确认”表示没有找到可供第三方阅读器自由调用的正式接口，不表示平台绝对不存在合作 API。

### 中文

**BOOK☆WALKER 台湾**

https://www.bookwalker.com.tw/

这个平台提供正式的限制级馆，成人用户登录后可以浏览和购买限制级漫画。

其限制级分类包含少年、少女、青年、淑女、BL、百合等漫画。对于已经购买的作品，阅读与下载方式仍受平台使用规则约束。:chatgpt-content-reference{index="5"}

### 日文

**Pixiv**

https://www.pixiv.net/

支持包含 R18、R18G 分级的投稿作品，其中也有漫画形式的作品。网站明确区分成人性内容与血腥猎奇内容。:chatgpt-content-reference{index="6"}

**DLsite**

https://www.dlsite.com/

这是日本的数字作品销售平台，提供漫画、同人作品等。其成人内容入口设有年龄确认。:chatgpt-content-reference{index="7"}

### 韩文

**Lezhin Comics**

https://www.lezhin.com/ko

这是我比较推荐你研究的韩漫平台。

其官方网站提供 19+ 作品分类，并实施年龄验证。内容包含恋爱、剧情、BL 等多个类别。:chatgpt-content-reference{index="8"}

**Bomtoon**

https://www.bomtoon.com/

有普通韩漫，也有明确标注 19+ 的作品。:chatgpt-content-reference{index="9"}

**RIDI**

https://ridibooks.com/

提供韩文漫画、Webtoon、小说及电子书。漫画列表支持成人内容筛选，部分作品明确要求读者达到韩国当地的成人年龄标准。:chatgpt-content-reference{index="10"}

需要强调，**这些正规平台适合阅读、购买和寻求内容合作，但不能直接把它们的网页地址当成能获取完整图片的漫画源。**

## 四、最适合直接对接的漫画 API：MangaDex

**MangaDex 是我建议你优先集成的漫画 API。**

官网：https://mangadex.org/

API 文档：

https://api.mangadex.org/docs/

API 文档源码：

https://gitlab.com/mangadex-pub/mangadex-api-docs

它提供漫画搜索、章节查询、翻译语言筛选及内容分级等能力。

### 1. 支持的成人分级

MangaDex 的 API 定义了四个内容等级：

| 分级 | 含义 | 建议处理方式 |
|---|---|---|
| `safe` | 普通内容 | 默认展示 |
| `suggestive` | 含暗示性内容 | 根据内容设置展示 |
| `erotica` | 成人情色内容 | 18+ 分区 |
| `pornographic` | 明确色情内容 | 18+ 分区并进行严格控制 |

这四个值来自 MangaDex API 的官方枚举定义。:chatgpt-content-reference{index="11"}

### 2. API 调用示例

查询漫画：

```http
GET https://api.mangadex.org/manga?limit=10
```

筛选成人分级：

```http
GET https://api.mangadex.org/manga?limit=10&contentRating[]=erotica
```

MangaDex 还提供章节与图片读取相关接口。

不过，**MangaDex API 明确要求署名来源和翻译组，并禁止在使用其服务的应用中投放广告或提供收费服务**。因此，它比较适合非商业原型和个人项目，不适合未经额外授权直接用于商业化阅读器。:chatgpt-content-reference{index="12"}

---

## 五、怎么把这些漫画源用于你的多端 App？

你有 Java 开发经验，建议重点研究 **Suwayomi Server**。

GitHub：

https://github.com/Suwayomi/Suwayomi-Server

它已经实现了在服务端运行 Mihon/Tachiyomi 兼容扩展的能力，并支持通过浏览器访问漫画阅读服务。:chatgpt-content-reference{index="13"}

这非常接近你的需求：

```text
             Flutter
                │
      ┌─────────┴─────────┐
      │                   │
   Android/iOS       Windows/macOS
      │                   │
      └─────────┬─────────┘
                │
          Spring Boot
                │
          漫画源管理服务
                │
       ┌────────┼──────────┐
       │        │          │
   MangaDex  Suwayomi   自定义解析器
      API      服务       │
                │         │
           Mihon 扩展   JSON书源
                │         │
                └────┬────┘
                     │
               统一漫画数据
                     │
                Flutter阅读器
```

需要注意，Mihon 扩展通常是 Android APK，不是普通 JSON 解析规则。

因此：

- Mihon 扩展：可以研究 Suwayomi 的服务端兼容方式。
- 异次元 JSON：适合实现自定义规则解析器。
- MangaDex：适合直接实现 HTTP API 适配器。
- 正版成人漫画平台：需要依据平台提供的授权方式进行接入。

对第三方扩展还需要做安全审查。Mihon 官方明确提醒，第三方扩展具有较高权限，存在恶意代码风险。:chatgpt-content-reference{index="14"}

## 六、最终推荐的漫画源组合

| 优先级 | 漫画源 | 用途 |
|---|---|---|
| P0 | **异次元源仓库** | 中文漫画及现有 18+ 漫画规则 |
| P0 | **MangaDex API** | 多语言搜索、章节与成人分级 |
| P0 | **Keiyoushi** | 研究多语言漫画扩展实现 |
| P1 | **Suwayomi** | 服务端漫画扩展运行 |
| P1 | **BOOK☆WALKER** | 中文正版及 18+ 内容合作方向 |
| P1 | **Lezhin / Bomtoon / RIDI** | 韩文正版及 19+ 内容合作方向 |
| P1 | **Pixiv / DLsite** | 日文及 R18 内容合作方向 |

**我的建议是，你的阅读器从第一版就同时设计小说书源和漫画源，但采用两套独立的解析接口。**

漫画源需要额外处理图片防盗链、阅读方向、长条漫、图片缓存、图片解码和漫画页预加载。

同时将内容分级设计成统一系统，而不是仅用一个 `isAdult` 布尔字段。这样将来同时管理普通小说、R18 小说、普通漫画和 R18 漫画时，不需要重新改造数据库。

**当前最值得先收藏的是这两个入口：**

普通与成人漫画源聚合：

https://www.yckceo.com/yiciyuan/tuyuan/index.html

多语言漫画扩展源码：

https://github.com/keiyoushi/extensions-source

这两处最符合你想自己开发阅读软件、能够不断增加漫画源的目标。

## 第 3 轮

### 用户原文

要分别做小说和漫画的软件，分别最适合使用什么架构，pc+手机端，另外调用api的方式是收费的吗？收费价格是什么，有没有质量好的免费的数据源做app

### 助手原文（未核验）

# 小说 App 与漫画 App：跨平台架构、API 费用、免费数据源完整方案

结合你的技术背景（Java、Spring Boot、MySQL、Redis），以及准备开发 **两款独立的软件，分别支持 Windows、macOS、Android、iOS** 的需求，我建议采用：

**两款独立 App + 两套独立阅读引擎 + 一套可复用的后端基础设施。**

重点是不要从一开始就把所有内容都放在自己的服务器上。对于阅读软件，数据源、阅读体验、版权和流量成本往往比业务接口本身更重要。

## 一、两款 App 最适合什么技术架构？

### 1. 总体技术选型

| 技术模块 | 小说 App | 漫画 App |
|---|---|---|
| 客户端框架 | **Flutter** | **Flutter** |
| Android | 原生编译 | 原生编译 |
| iOS | 原生编译 | 原生编译 |
| Windows | Flutter Desktop | Flutter Desktop |
| macOS | Flutter Desktop | Flutter Desktop |
| 阅读引擎 | EPUB/HTML 排版引擎 | 图片渲染引擎 |
| 本地数据库 | SQLite | SQLite |
| 本地存储 | TXT、EPUB、章节缓存 | 图片、CBZ、CBR |
| 服务端 | Spring Boot | Spring Boot |
| 数据库 | MySQL / PostgreSQL | MySQL / PostgreSQL |
| 缓存 | Redis（按需） | Redis（按需） |
| 内容接入 | JSON 规则、OPDS、授权 API | 漫画扩展、JSON、授权 API |
| 内容同步 | 阅读进度、书签、书架 | 阅读进度、收藏、下载状态 |
| 离线阅读 | 支持 | 支持 |
| 成人内容 | 独立内容分级 | 独立内容分级 |

**为什么都选 Flutter？**

因为你的目标不仅是手机，还包括 Windows 和 macOS。Flutter 可以使用一套 Dart 业务代码，构建四个平台的客户端。

你不需要分别维护：

- Java/Kotlin Android 客户端
- Swift iOS 客户端
- C# Windows 客户端
- Swift macOS 客户端

但 Flutter 并不意味着所有代码都能完全共用。文件访问、系统通知、后台任务、桌面窗口管理及部分阅读引擎仍需要平台适配。

如果准备长期维护两款软件，Flutter 是一个比较均衡的方案。

---

## 二、小说 App：推荐 Local-first + 书源插件架构

**Local-first** 指的是本地优先。

小说阅读、书架管理、阅读历史、书签和已下载章节，不应该完全依赖服务器。

### 推荐架构

```text
              小说阅读 App
                    │
      ┌─────────────┴──────────────┐
      │                            │
   手机客户端                    PC客户端
   Android/iOS                Windows/macOS
      │                            │
      └─────────────┬──────────────┘
                    │
               Flutter
                    │
      ┌─────────────┼──────────────┐
      │             │              │
   小说阅读引擎   书源解析引擎    本地数据管理
      │             │              │
   EPUB/TXT       书源规则         SQLite
   字体排版       OPDS             章节缓存
   翻页动画       REST API         书架
   夜间模式       本地文件         阅读进度
      │             │              │
      └─────────────┼──────────────┘
                    │
          可选 Spring Boot 后端
                    │
        ┌───────────┼───────────┐
        │           │           │
      用户管理    多端同步    书源配置同步
        │           │           │
        └───────────┼───────────┘
                    │
               MySQL/Redis
```

### 为什么不建议所有小说内容都走 Java 后端？

假设用户在手机上阅读一本小说：

**方案 A：服务端代理所有阅读内容**

```text
手机 → Java服务器 → 小说数据源
手机 ← Java服务器 ← 小说正文
```

问题：

1. 所有正文流量都经过你的服务器。
2. 服务器故障会影响用户在线阅读。
3. 用户规模增大后，需要解决缓存和并发问题。
4. 如果来源没有授权，服务端重新分发正文可能带来版权风险。

**方案 B：客户端读取内容，服务器只同步个人数据**

```text
手机 → 有权访问的内容来源 → 小说正文
  │
  └── Java服务器 → 同步书架/阅读进度
```

对于个人阅读器，**优先推荐方案 B**。

它有几个明显优势：

- 服务器成本很低。
- 离线阅读体验好。
- 网络不好时仍然可以打开本地书籍。
- 用户可以自行管理合法获取的内容。
- 阅读进度可以在 PC、手机之间同步。

不过，如果商业化并使用正版授权内容 API，就需要依据版权方的接口协议决定是否由后端访问。

### 小说 App 最重要的模块

我会优先开发以下五个模块：

| 模块 | 重点 |
|---|---|
| 阅读引擎 | TXT、EPUB、自动分页、字体和行距 |
| 书源引擎 | 搜索、详情、目录、章节、更新检测 |
| 本地存储 | SQLite、下载管理、章节缓存 |
| 书架系统 | 分类、排序、阅读记录 |
| 同步系统 | 账号、进度同步、书签同步 |

技术上还要注意：

**Legado 书源不是简单的 JSON API。** 它是一套包含 HTML 提取、正则表达式及部分 JavaScript 执行能力的规则系统。

如果想兼容它，需要开发真正的规则解释器，而不是只解析 JSON 字段。

---

## 三、漫画 App：推荐 Local-first + 图片流式加载架构

漫画 App 与小说 App 最大的区别是内容格式和数据量。

小说的核心是文本排版，漫画的核心是**图片加载、解码、缓存和滑动性能**。

### 推荐架构

```text
                漫画 App
                    │
          Android / iOS / PC
                    │
                 Flutter
                    │
       ┌────────────┼────────────┐
       │            │            │
    漫画阅读器    漫画源引擎     下载管理
       │            │            │
    长条漫模式    REST API      图片队列
    单页模式      JSON规则      断点续传
    双页模式      扩展适配       离线缓存
    图片预加载    本地漫画       图片解码
       │            │            │
       └────────────┼────────────┘
                    │
               本地 SQLite
                    │
            可选 Spring Boot
                    │
        ┌───────────┼───────────┐
        │           │           │
      账号管理    进度同步    书源配置管理
        │           │           │
        └───────────┼───────────┘
                    │
               MySQL/Redis
```

### 漫画图片应该怎么加载？

建议使用以下方式：

```text
用户打开漫画章节
        │
        ▼
获取章节图片清单
        │
        ▼
优先加载当前页
        │
        ▼
预加载后续 2～5 页
        │
        ▼
内存图片缓存
        │
        ▼
磁盘缓存
        │
        ▼
用户继续翻页
```

图片预加载数量需要根据设备内存、屏幕尺寸及原图大小动态调整，而不是固定缓存全部漫画页。

### 漫画 App 需要特别重视的功能

| 功能 | 必要性 |
|---|---|
| 长条漫连续滚动 | 必须 |
| 日漫右向左阅读 | 必须 |
| 普通左向右阅读 | 必须 |
| 单页/双页切换 | 必须 |
| 图片预加载 | 必须 |
| 离线缓存 | 必须 |
| CBZ/ZIP 导入 | 必须 |
| 图片缩放 | 必须 |
| 阅读进度同步 | 必须 |
| CBR/RAR 导入 | 建议 |
| 漫画翻译 | 第二阶段 |

其中，韩漫特别需要优化长条图片的解码与滚动体验。

而日漫一般更注重单页、双页及从右向左的阅读顺序。

### 漫画源引擎如何设计？

建议统一接口：

```java
public interface ComicSource {

    // 搜索漫画
    List<Comic> search(String keyword);

    // 漫画详情
    Comic getComic(String comicId);

    // 获取章节目录
    List<ComicChapter> getChapters(String comicId);

    // 获取章节图片列表
    List<ComicPage> getPages(String chapterId);
}
```

注意这里返回的是**图片资源描述信息**，不应该默认把所有图片字节都通过 Java 服务端转发。

对于有授权的来源，可以根据其协议直接使用 CDN 图片地址，或者通过授权的图片代理服务获取。

---

## 四、API 调用是收费的吗？具体多少钱？

先明确一个关键概念：

**API 免费 ≠ 内容免费 ≠ 可以免费商用。**

API 服务一般分为四种收费模式。

| 模式 | 收费方式 | 常见场景 |
|---|---|---|
| 免费开放 | 0 元，通常有频率限制 | 开源图书项目 |
| 免费额度 | 免费调用一定次数 | 图书元数据 API |
| 按调用量收费 | 按次数或流量结算 | 商业数据服务 |
| 内容授权 | 按合作协议定价 | 正版网络小说、商业漫画 |

另外，书源规则本身通常不是付费 API。JSON 文件只是告诉阅读器如何从目标网站查询和解析内容，真正的访问限制取决于目标网站。

### 1. 小说 API 费用对比

以下是截至 **2026 年 10 月 14 日** 查到的公开信息。

| API / 平台 | 公开调用价格 | 是否提供完整正文 | 是否适合公开 App |
|---|---|---|---|
| **Gutendex** | 免费，0 元 | ✅ 提供公版图书下载地址 | ⭐⭐⭐⭐⭐ |
| **维基文库 API** | 免费，0 元 | ✅ 提供可自由使用的文本 | ⭐⭐⭐⭐⭐ |
| **Google Books API** | 常规免费配额内为 0 元 | 部分书籍可全文阅读 | ⭐⭐⭐⭐ |
| **Open Library API** | 免费，0 元 | 主要提供元数据及阅读入口 | ⭐⭐⭐ |
| **Standard Ebooks** | 图书免费，完整 OPDS 订阅需满足访问条件 | ✅ 公版图书 | ⭐⭐⭐⭐ |
| **青空文库** | 免费下载，无公开按次收费 | ✅ 日文经典文学 | ⭐⭐⭐⭐ |
| 番茄小说 | 未找到公开的通用内容 API 报价 | 不向普通开发者开放通用正文 API | 需商务合作 |
| 起点中文网 | 未找到公开的通用内容 API 报价 | 不向普通开发者开放通用正文 API | 需商务合作 |

这里的免费是指公开接口或内容获取本身不按次收取费用，不包含服务器、存储、带宽等运营成本。

#### A. Gutendex：免费且可以获取图书内容

官网：

https://gutendex.com/

API：

```http
GET https://gutendex.com/books?languages=zh
```

按照书名搜索：

```http
GET https://gutendex.com/books?search=Alice
```

API 返回的数据包括：

```json
{
  "id": 11,
  "title": "Alice's Adventures in Wonderland",
  "formats": {
    "text/html": "图书HTML地址",
    "text/plain": "图书TXT地址"
  }
}
```

这是结构示例，具体格式键名以实际响应为准。

它的优点是提供图书格式与下载地址，包括 EPUB、HTML、TXT 等。

不过，官方建议长期使用者自行部署 Gutendex，避免依赖公共实例的可用性。其版权状态字段主要基于美国版权情况。:chatgpt-content-reference{index="0"}

#### B. Google Books API：免费元数据能力较强

官方文档：

https://developers.google.com/books/docs/v1/using

示例：

```http
GET https://www.googleapis.com/books/v1/volumes?q=java&key=YOUR_API_KEY
```

搜索免费电子书：

```http
GET https://www.googleapis.com/books/v1/volumes?q=java&filter=free-ebooks&key=YOUR_API_KEY
```

它可以返回书名、作者、简介、封面等信息。

需要申请 API Key，并受项目配额限制。**目前没有查到官方公布的按次付费扩容单价**，因此不能简单推断超过免费额度后支付多少钱就能无限使用。

更重要的是，Google Books 的 `free-ebooks` 并不意味着所有对应图书都允许下载并在第三方 App 中重新分发。:chatgpt-content-reference{index="1"}

#### C. Open Library：免费，但不适合当商业内容服务器

官网：

https://openlibrary.org/developers/api

目前官方明确公布的限制是：

| 请求类型 | 频率 |
|---|---|
| 未标识客户端 | 1 次/秒 |
| 提供 User-Agent 和联系信息 | 3 次/秒 |
| 大规模数据导入 | 建议使用数据转储 |
| 高流量商业后端 | 不属于其公开 API 的预期用途 |

适合做搜索、书籍信息补充、作者资料查询，不推荐依赖它向大量用户持续提供内容服务。:chatgpt-content-reference{index="2"}

### 2. 漫画 API 费用对比

| API / 来源 | 公开价格 | 完整漫画内容 | 商业化使用 |
|---|---|---|---|
| **MangaDex API** | **0 元** | ✅ 漫画章节及图片 | ❌ 禁止通过使用其 API 的服务盈利 |
| **Pepper&Carrot** | **0 元** | ✅ 完整漫画图片 | ✅ CC BY 4.0 条件下可商用 |
| **Comic Vine API** | **0 元** | ❌ 主要是漫画资料 | ❌ 仅限非商业 |
| **Keiyoushi 扩展仓库** | 仓库免费 | 取决于第三方网站 | 逐个确认 |
| **异次元漫画规则** | 多数公开规则免费 | 取决于第三方网站 | 逐个确认 |
| Lezhin Comics | 没有公开统一 API 单价 | 有正版内容 | 需要合作授权 |
| RIDI | 没有公开统一 API 单价 | 有正版内容 | 需要合作授权 |
| DLsite | 没有公开统一 API 单价 | 有正版内容 | 需要合作授权 |

#### A. MangaDex：免费漫画 API

官方文档：

https://api.mangadex.org/docs/

调用示例：

```http
GET https://api.mangadex.org/manga?limit=20
```

**价格：0 元。**

但是有三个重要条件：

1. 必须标注 MangaDex 来源。
2. 阅读章节时必须标注翻译组，并尊重作品下架要求。
3. 不允许在依赖其 API 的网站或 App 中通过广告、付费服务盈利，除非获得例外许可。

这是 MangaDex 官方明确写出的规定。:chatgpt-content-reference{index="3"}

因此，MangaDex 很适合你开发个人阅读器或非商业项目，但不能直接作为广告变现 App 的免费内容库。

此外，免费提供 API 不等于 MangaDex 对站内所有漫画都拥有可再授权的版权。

#### B. Pepper&Carrot：可以商用的免费漫画

官网：

https://www.peppercarrot.com/

**官方 JSON 目录：**

https://peppercarrot.com/0_sources/episodes.json

官方 API 文档：

https://www.peppercarrot.com/go/documentation/130_API.html

它提供：

- 漫画章节列表。
- 各章节支持的翻译语言。
- 漫画图片下载地址。
- 不同分辨率的图片。

其漫画作品采用 CC BY 4.0 授权，允许在遵守署名等许可条件下商业使用。具体应以作品及翻译文件的实际授权为准。

它还有中文翻译，是非常合适的漫画阅读器测试数据源。:chatgpt-content-reference{index="4"}

#### C. Comic Vine：免费漫画资料 API

官网：

https://comicvine.gamespot.com/api/

官方条款写明：

- API 仅限非商业用途。
- 官方支持每种资源每小时 200 次请求。
- 必须标注数据来源。
- 不提供漫画完整正文作为通用阅读接口。

因此它适合做漫画资料管理、角色资料和搜索原型，不能代替真正的漫画图片数据源。:chatgpt-content-reference{index="5"}

---

## 五、哪些免费数据源质量好，真正适合开发 App？

这是整个方案里最重要的部分。

如果你的目标是**免费内容、稳定阅读、覆盖多语言，而且未来有机会公开发布**，那么我推荐下面的组合。

### 1. 小说 App 免费数据源推荐

| 来源 | 中文 | 日文 | 韩文 | 全文 | 推荐用途 |
|---|---|---|---|---|---|
| **Gutendex** | ✅ | ✅ | 有限 | ✅ | 公版小说目录及下载 |
| **维基文库** | ✅ | ✅ | ✅ | ✅ | 中文小说、古典文学 |
| **青空文库** | ❌ | ✅ | ❌ | ✅ | 日文小说 |
| **Standard Ebooks** | 少 | 少 | 少 | ✅ | 高质量英文 EPUB |
| Google Books | ✅ | ✅ | ✅ | 部分 | 全球书籍搜索 |
| Open Library | ✅ | ✅ | ✅ | 部分 | 书籍元数据 |

其中三个建议直接作为第一版的内容来源：

**① 中文：维基文库**

https://zh.wikisource.org/

API：

```text
https://zh.wikisource.org/w/api.php
```

提供免费中文书籍和历史文献，其中包含大量公版小说。

通过 MediaWiki API 可以读取页面结构和文本。不同作品、译本及整理文本的授权可能不同，需要分别检查。([wikisource.org](https://en.wikisource.org/wiki/Wikisource%3ACopyright_policy))

**② 日文：青空文库**

https://www.aozora.gr.jp/

这是一个有长期积累的日本电子文学资料库，收录大量版权已到期的文学作品。

适合开发日文小说阅读功能，包括日文排版、注音、竖排阅读等。

它主要提供作品目录和文本下载，并不是一个统一的商业 REST API。([日本国际交流基金资料](https://sydney.jpf.go.jp/japanese-studies/resources/aozora-bunko-open-access-digital-library/))

**③ 多语言：Gutendex**

https://gutendex.com/

它适合充当小说 App 的免费内容入口。

但必须看到一个局限：**这几个来源的主要内容是公版作品，不能替代番茄、起点、七猫等平台的当代连载网文。**

如果你希望用户能够阅读大量正在连载的玄幻、都市、言情小说，那么仍然需要作者授权、出版商合作，或者让用户导入自己有权阅读的内容。

### 2. 漫画 App 免费数据源推荐

| 来源 | 中文 | 日文 | 韩文 | 成人分级内容 | 适合公开商用 |
|---|---|---|---|---|---|
| **Pepper&Carrot** | ✅ | ✅ | ✅ | 非成人专门来源 | ✅ 遵守 CC BY 4.0 |
| **MangaDex** | ✅ | ✅ | ✅ | ✅ | ❌ API 禁止盈利 |
| **Comic Vine** | 有资料 | 有资料 | 有限 | 不作为主要分级源 | ❌ |
| Keiyoushi | ✅ | ✅ | ✅ | 部分扩展包含 | 逐源授权 |
| 异次元漫画源 | ✅ | 部分 | 部分 | 部分规则包含 | 逐源授权 |

这里我要补充一个非常有价值的发现。

**Pepper&Carrot 的官方 JSON 目录中，明确存在中文、日文、韩文三个语言版本。**

其语言代码分别是：

```json
{
  "chinese": "cn",
  "japanese": "ja",
  "korean": "kr"
}
```

这是 Pepper&Carrot 自己使用的语言标记，并非完全遵循标准 ISO 语言代码。

我检查了实际公开的 `episodes.json`，其中多个章节同时列出了这三种语言。不同章节的翻译完成度可能不同。:chatgpt-content-reference{index="6"}

官方地址：

https://peppercarrot.com/0_sources/episodes.json

**这是特别适合你开发漫画 App 的免费测试源。**

因为它能够验证：

- 不同语言的漫画章节。
- 图片列表获取。
- 图片预加载。
- 漫画离线下载。
- 多端阅读进度同步。
- 中文、日文、韩文语言切换。

而且它的漫画许可证允许商业使用，只需正确履行署名、许可证链接及修改说明等要求。([Creative Commons 官方许可](https://creativecommons.org/licenses/by/4.0/))

需要说明的是，Pepper&Carrot 只是一套相对有限的漫画作品，不是包含数千部漫画的内容平台。

---

## 六、如果包含 18+ 内容，有哪些免费 API？

你前面特别提到，希望支持成人向小说和漫画。

这里需要将**个人阅读、非商业 App、商业 App** 分开考虑。

### 1. 成人小说

| 内容来源 | 18+ 内容 | 免费访问 | 第三方正式 API | 适合的接入方式 |
|---|---|---|---|---|
| Pixiv 小说 | ✅ R18 | 部分免费 | 未确认可商用的公开接口 | 官方授权或合规访问 |
| AO3 | ✅ Mature / Explicit | ✅ | 无通用官方开放 API | 官方阅读入口 |
| 维基文库 | 可能存在成人主题文学 | ✅ | ✅ | 按作品许可获取 |
| 自有授权作品 | ✅ | 由作者决定 | 自建 | 最稳定 |
| 用户本地 TXT/EPUB | 取决于用户文件 | ✅ | 不需要 | 本地导入 |

如果只是个人使用，技术上可以设计独立的成人内容过滤器和可配置书源管理系统。

但公开发布时，不应将 Pixiv、AO3 等网站的免费访问权限理解为对第三方 App 的抓取、托管和分发授权。

### 2. 成人漫画

| 内容来源 | 18+ 内容 | API 费用 | 使用限制 |
|---|---|---|---|
| **MangaDex** | ✅ | 0 元 | 不得通过使用其 API 的 App 盈利 |
| Pixiv | ✅ | 无公开统一报价 | 需要遵守登录、年龄限制和授权规则 |
| DLsite | ✅ | 无公开统一报价 | 内容购买与授权分开 |
| Lezhin | ✅ 19+ | 商务询价 | 需要内容授权 |
| RIDI | ✅ 19+ | 商务询价 | 需要内容授权 |
| Bomtoon | ✅ 19+ | 商务询价 | 需要内容授权 |

**目前我没有找到一个同时满足以下条件的成熟来源：大量中文、日文、韩文 R18 漫画，永久免费，允许商业 App 完整阅读和重新分发。**

这不是技术难题，而是内容授权问题。

你可以先用 MangaDex 测试成人分级、语言过滤、漫画阅读功能；正式发布时再根据具体作品的权利状况和 API 条款确定能否使用。

### 3. 18+ 内容会影响应用商店上架

Google Play 对图书目录应用设有有限例外，但要求相关内容只占少部分、不得主动宣传、限制未成年人访问，并且不得分发色情或违法内容。:chatgpt-content-reference{index="7"}

Apple App Store 对露骨色情内容也有明确限制。:chatgpt-content-reference{index="8"}

因此，无论小说还是漫画，18+ 都不能只依赖一个年龄确认弹窗。还需要考虑地区法规、年龄验证、内容分级及平台审核规则。

---

## 七、两款 App 的后端要不要分开？

我建议：**App 分开，基础服务共享，内容解析独立。**

这能减少重复开发。

### 最终部署架构

```text
                  用户设备
                     │
       ┌─────────────┴──────────────┐
       │                            │
    小说 App                     漫画 App
       │                            │
    Flutter                      Flutter
       │                            │
   小说阅读引擎                 漫画阅读引擎
       │                            │
   小说源适配器                 漫画源适配器
       │                            │
       └─────────────┬──────────────┘
                     │
              Spring Boot API
                     │
        ┌────────────┼─────────────┐
        │            │             │
      用户中心     进度同步      配置同步
        │            │             │
        └────────────┼─────────────┘
                     │
                 MySQL
                     │
             Redis（按需）
```

### 为什么不直接使用微服务？

对于个人开发或小团队，第一版没必要使用 Spring Cloud、Gateway、注册中心等一整套微服务基础设施。

虽然你熟悉这套技术，但阅读器业务本身并不复杂。

建议使用：

**Spring Boot 模块化单体架构。**

例如：

```text
reader-platform
│
├── reader-common
│
├── reader-auth
│
├── reader-user
│
├── reader-sync
│
├── reader-source
│
├── reader-novel
│
├── reader-comic
│
└── reader-admin
```

其中 `reader-novel` 和 `reader-comic` 分别负责两款 App 的业务服务。

在数据库层面分别维护小说、漫画的内容与进度数据，避免产生相互影响。

以后如果漫画业务流量明显增大，再考虑将其独立部署。

### 我建议两款 App 共用的功能

| 功能 | 是否共用 |
|---|---|
| 用户账号 | ✅ |
| 登录鉴权 | ✅ |
| 设备管理 | ✅ |
| 阅读进度同步服务 | ✅ |
| 云端书架基础能力 | ✅ |
| 本地 SQLite 数据 | ❌ |
| 小说阅读引擎 | ❌ |
| 漫画阅读引擎 | ❌ |
| 小说书源解析 | ❌ |
| 漫画扩展解析 | ❌ |
| 下载和缓存策略 | 分开实现 |
| 内容分级基础规则 | ✅ |
| 具体内容分类 | 分开管理 |

对于书源管理，还有一个重要的安全建议。

第三方书源规则、漫画扩展都属于不可信输入。必须限制脚本执行能力、网络目标、请求超时和资源消耗，避免发生 SSRF、恶意脚本执行及用户凭据泄露。

---

## 八、开发和运营的成本大概是多少？

如果你采用我推荐的 Local-first 架构，初期成本可以非常低。

以下是规划预算，不是云服务商的实时报价。

| 成本项目 | 个人开发阶段 | 公开运营阶段 |
|---|---|---|
| Flutter | 免费 | 免费 |
| Spring Boot | 免费 | 免费 |
| SQLite | 免费 | 免费 |
| MySQL | 免费自建 | 免费自建或付费托管 |
| Redis | 初期不需要 | 按需部署 |
| 免费图书 API | 0 元 | 按服务条款及额度使用 |
| 免费漫画 API | 0 元 | 可能限制商业化 |
| 个人阅读服务器 | 可以不部署 | 通常需要 |
| 云服务器 | 0 元至云服务费用 | 根据供应商配置 |
| CDN | 初期不需要 | 漫画内容分发可能需要 |
| 正版内容授权 | 可先不采购 | 需商务报价 |

这里最值得注意的是：

**小说和漫画的实际运营成本会明显不同。**

小说主要传输文字，网络流量通常较小。

漫画则主要传输图片。如果服务器负责分发漫画，随着用户量增加，图片带宽、对象存储、CDN 和缓存都会成为主要成本。

因此，漫画 App 尽量不要让 Spring Boot 直接传输图片二进制内容。

如果你拥有内容分发权，可以让客户端通过对象存储和 CDN 获取图片。对于第三方来源，则必须遵守其图片访问及缓存要求。

---

## 九、我建议的实际开发顺序

考虑到你准备开发两款独立 App，我会采用下面的实施顺序。

### 第一阶段：先做小说 App

| 顺序 | 功能 | 数据来源 |
|---|---|---|
| 1 | Flutter 四端基础框架 | 本地数据 |
| 2 | TXT / EPUB 阅读 | 用户本地文件 |
| 3 | 书架、进度、书签 | SQLite |
| 4 | 小说搜索和导入 | Gutendex、维基文库 |
| 5 | 多端同步 | Spring Boot |
| 6 | 自定义书源规则 | 用户配置 |
| 7 | 内容分级与过滤 | 来源元数据 |

这里我建议不要急着兼容全部 Legado 规则。

先实现标准 REST API、OPDS 和基础 HTML 规则，再逐步扩展。完整实现 Legado 的 JavaScript 规则兼容性会显著增加开发复杂度。

### 第二阶段：开发漫画 App

| 顺序 | 功能 | 数据来源 |
|---|---|---|
| 1 | Flutter 四端基础框架 | 共享基础组件 |
| 2 | CBZ、ZIP 图片阅读 | 本地文件 |
| 3 | 长条漫、单页、双页 | 本地漫画 |
| 4 | 图片预加载和缓存 | 本地 |
| 5 | 多语言漫画 API | Pepper&Carrot |
| 6 | MangaDex 非商业适配器 | MangaDex |
| 7 | 自定义漫画源 | 用户配置 |
| 8 | 阅读进度同步 | Spring Boot |
| 9 | 内容分级 | 来源元数据 |

漫画 App 可以直接复用小说 App 的账号、同步及部分 UI 基础组件。

需要强调，公开可用的第三方解析规则不代表有权绕过网站的访问控制，也不代表有权缓存或重新分发其内容。

---

## 十、最终技术方案和数据源推荐

| 比较项 | 小说 App | 漫画 App |
|---|---|---|
| **最推荐客户端** | Flutter | Flutter |
| **最推荐后端** | Spring Boot | Spring Boot |
| **核心架构** | Local-first | Local-first |
| **免费内容首选** | Gutendex、维基文库 | Pepper&Carrot |
| **日文内容** | 青空文库 | Pepper&Carrot 日文版 |
| **韩文内容** | 维基文库韩文版 | Pepper&Carrot 韩文版 |
| **非商业多语言来源** | 合规的开放书源 | MangaDex |
| **18+ 分级研究** | Pixiv、AO3 等平台 | MangaDex、Pixiv 等平台 |
| **自定义源机制** | JSON 规则、OPDS、REST | JSON 规则、扩展、REST |
| **正版商业内容** | 作者或平台授权 | 作者或平台授权 |
| **最重要的体验** | 排版、翻页、字体 | 图片加载、流畅滚动 |
| **主要运营风险** | 内容版权、书源稳定性 | 内容版权、图片流量 |

### 最终结论

对于你要做的两款软件，我认为最合适的产品定位是：

**小说 App：以强大的阅读体验、自由书源管理、多端同步为核心。**

**漫画 App：以多语言漫画阅读、高性能图片加载、离线阅读、多端同步为核心。**

两者都可以做到基础功能免费使用，并通过正规的免费内容来源完成第一版开发。

但有一个现实问题需要提前决定：

**你是更倾向于开发「类似阅读 3.0 / Mihon，用户自己添加书源」的软件，还是「类似栗知 / 快看漫画，打开就有大量作品可以直接阅读」的软件？**

这是两个完全不同的商业和技术方向。前者重点在阅读器与扩展生态，通常可以用很低的成本起步；后者的核心成本是内容资源与授权，即使 API 本身免费，也不代表拥有向用户提供这些作品的权利。

## 第 4 轮

### 用户原文

把此聊天框内容转为 codex项目，项目名称还是阅读软件保持不变

### 助手原文（未核验）

已将当前聊天内容移交至 **Codex**，创建了新的开发会话。

**项目名称保持：阅读软件**

移交的项目需求包括：

1. **小说阅读 App**：Flutter 跨平台、TXT/EPUB 阅读、书源管理、离线缓存、阅读进度同步。
2. **漫画阅读 App**：Flutter 跨平台、漫画源管理、多语言支持、图片预加载、离线阅读。
3. **支持平台**：Android、iOS、Windows、macOS。
4. **后端架构**：Spring Boot 模块化单体，优先采用 Local-first 架构。
5. **数据源**：整理此前讨论的免费 API、小说书源、漫画源，以及中文、日文、韩文资源。
6. **18+ 内容**：年龄限制、内容分级和独立管理。
7. **项目文档**：要求 Codex 建立 `AGENTS.md`、`README.md`、架构设计、需求说明、数据源清单和开发路线图。

**当前状态：** Codex 已接受移交。项目文件的实际创建情况需要在新的 Codex 会话中确认。

接下来可以在 Codex 中继续完善架构和开发计划，无需重新描述本次聊天中的需求。
