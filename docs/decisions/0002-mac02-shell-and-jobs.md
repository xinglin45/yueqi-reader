# ADR-0002：MAC-02应用壳与任务所有权

日期：2026-10-16。状态：采用；只适用于当前应用壳，不冻结后续数据库/阅读引擎选型。

## 决定

- 以确认提交e7764cc的D1为视觉基线，实际Flutter页面位于小说/client/lib/app与features。Flutter保留系统标题栏，内容顶栏64、侧栏276/220、760以下改抽屉；纸色、深色、宋体正文及Phosphor light图标沿用D1。首次启动为空库，自产样本必须主动进入；不把设计原型的42%进度、书签或模拟来源写成真实数据。
- 当前装配使用构造函数注入AppDependencies；导航使用固定SDK的RouterDelegate/RouteInformationParser，稳定ID编码为/reader/:bookId，未知地址给可返回空态。AppNavigation保存最多100条会话内返回记录。此前Riverpod/go_router为待试验候选，本批没有引入：当前规模用SDK接口已能验证装配、返回、无效路由和生命周期，无需额外依赖。以后复杂调度或隐私重定向需要时可替换装配/路由实现，领域端口不变。
- JobController属于页面/对话框，JobContext、JobResult和错误类别属于纯Dart领域契约；领域不依赖application或Flutter。每次运行生成会话内唯一递增job_id，取消、替换、终态和dispose均使代际失效。取消后的进度/成功/错误丢弃，合作任务在阶段边界checkCancelled；不合作的Future也不能回写。同步任务不得伪造后台下载能力。
- null进度表示未知；数字进度仅接受0～1、有限且不倒退。ready/partial/empty/failed/cancelled是不同状态；partial保留成功数据，错误仅保存枚举，未知异常统一unexpected。全局只留最多20条会话内错误代码，不保存原始异常、堆栈、书名、文件路径、凭据或诊断上传。
- platform_services现在是实际使用的纯Dart包，只含FileAccess、SecureStore、SpeechService、WindowIntegration草案和明确unsupported回退。原生选择文件、授权恢复、Keychain、语音、NSStatusItem/窗口、系统全局快捷键仍在MAC-04/12/13/17；没有用内存成功结果冒充系统安全存储。

## 图标兼容性与许可

2026-10-16核对[Phosphor原维护仓库问题61](https://github.com/phosphor-icons/flutter/issues/61)：原phosphor_flutter 2.1.0继承IconData，与当前SDK的final声明冲突。核对[维护分支](https://github.com/funccloud/phosphor-icons)和[3.0.1发布页](https://pub.dev/packages/phosphor_icons/versions/3.0.1)，采用phosphor_icons **3.0.1精确版本**，不是原官方包更新声明。实际缓存源码为IconData别名/常量，无新增原生插件或网络依赖；本App只使用light常量和Flutter Icon。没有降级或修改SDK。

已读取MIT原文并保留[副本](../licenses/mac-02/phosphor_icons-LICENSE.txt)。实际解析SHA-256见应用pubspec.lock；pub归档元数据为`0f32a6c6a7bbadb2e42cba15ec103dcd23dfa47137f17a6f5b5a078081ac55f8`。只作包的版本/许可记录，不替作品来源或本项目选定源码许可证。所有图标与封面本地打包，无字体CDN。

## 边界与验证

本批没有接入SQLite、TXT/EPUB引擎、真实来源、成年声明持久化、听书或低存在感系统表面。App内的“界面状态检查”是显式本地模拟，不接受私人文件、不发网络请求；不等于下载队列。

构造注入的受控Repository/FileAccess测试替身用于制造迟到成功、迟到错误、切书、取消、权限拒绝与恢复。键盘/响应布局和真实macOS构建证据见[MAC-02验收](../verifications/mac-02-2026-10-16.md)。真实输入法、VoiceOver、系统窗口/菜单和四端行为仍需对应任务真机验证。
