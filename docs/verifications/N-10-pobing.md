# N-10-pobing：破冰书源

核验人Codex；2026-10-15；整体pending。定位作者仓库与两个分发版本，包级检查通过，逐条阅读/许可/App兼容未通过。原N-10含两个候选，分别记录以免混淆。

## 版本与差异

- AOA目录链接至[PB-pobing/pobing](https://github.com/PB-pobing/pobing)，默认pb分支，提交a0d7655b078dbc674bc3a775005ae8c8e15d72c7，最近观测提交2023-08-22T06:58:05Z；未归档不等于近期维护。
- [固定作者sy.json](https://raw.githubusercontent.com/PB-pobing/pobing/a0d7655b078dbc674bc3a775005ae8c8e15d72c7/sy.json)HTTP200、883518字节、128条，SHA-256 567cc1bc3e101d6b3b31816a7b380eb499ac911e52ac2401ffe95d8da755eeb0；与[AOA镜像](https://legado.aoaostar.com/sources/4dc410d1.json)解析后字段一致。
- [分发页](https://yuedu.miaogongzi.net/gx.html)另指向[sy.json分发文件](https://legado.miaogongzi.org/%E9%98%85%E8%AF%BB%E4%B9%A6%E6%BA%90/sy.json)，实测HTTP200、508616字节、91条，SHA-256 5f4fa106158ba51c4a1817d53060fa094e9b1c978045bd8844ec50e49ada75ab；页面标128与当前链接实际91不一致。
- 128条作者版：71条JS/运行时标记、26条Java/helper标记、9条登录配置，1条缺非空ruleContent；包含其他数值类型，不能将总数全部当文字小说站。

## 实测与限制

起点普通搜索路径手工请求返回202、209字节脚本页，0个预期列表节点，未执行规则。其余127条未逐条测通；缺字段/旧提交只记录事实，不一概判全部失效。

作者仓库根目录未见独立许可文件，目标站作品/翻译/封面、署名、缓存/离线/代理/再分发/商用未逐项明确。本次取得配置未付费，但规则指向付费平台，不能当免费全文保证。未确认作品年龄/地区条件，没有统一分级字段，不批准整包启用。

后续先确定使用128还是91版本及来源权利，再做有权限的单源试验。见 [报告](../source-collections-audit-2026-10-15.md)、[证据](evidence/2026-10-15-collection-observations.json)。
