# ADR-0008：只读文件授权与有界导入

日期：2026-10-21。状态：采用；对应第06步MAC-04与MAC-13文件部分。沿用D1、Local-first与MAC-16门禁。

## 选择与边界

使用系统NSOpenPanel多选TXT/EPUB，Finder拖放和“打开方式”进入同一导入用例。不自行扫描文件系统，不向领域暴露外部绝对路径。macOS MethodChannel只接受不透明UUID（及内部暂存旧编码解码路径），串行IO队列持有最多4个读取句柄，每次64 KiB；开始/结束security scope成对执行。平台端口是纯Dart的DocumentAccess，共享包不依赖App或Cocoa。

默认托管原始字节副本；可选择引用，生成系统read-only app-scope bookmark，保存于设备目录novel-device/grants（目录0700、文件0600），书库只记本机grant_id。书签失效返回错误，由用户选择同摘要原件重新关联。不用全磁盘权限解决授权，原件不写入、不自动改名/删除。Release新增user-selected.read-only和bookmarks.app-scope，Debug也保持相同文件权限；现有Debug调试权限独立。

系统行为依据Apple的[沙盒文件访问说明](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)、[窗口拖放注册](https://developer.apple.com/documentation/appkit/nswindow/registerfordraggedtypes%28_%3A%29)及[拖放目标协议](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Concepts/dragdestination.html)。文件系统/其他平台差异不能由这些文档推定实测通过。

## 导入流程

每批最多32项，每个原文件0 < size ≤ 64 MiB。流式复制到本App的import-stage并计算SHA-256；验证期间引用也使用临时一致快照，提交后删除，不保留永久引用副本。标题最多200个Unicode标量；预览最多2000标量。每项明确选择普通/成人分级；未知不归普通，声明/锁定检查在提交及后续状态/关联用例重做。成人内容不因搜索OFF而删除，门禁承接MAC-16。测试只使用自产中性文本。

TXT自动只接受严格UTF-8/BOM或有BOM的UTF-16；可明确选择UTF-16LE/BE、GB18030、Big5。UTF-8/16流式校验全文并检查代理对/NUL，旧中文编码在原生后台对有上限的快照严格解码并逐字节回编码比对；不猜测后静默吞字或写替换字符。旧编码解码会处理完整快照，最多64 MiB，并非无界内存或本批已验证的大书性能承诺。歧义由用户看预览后确认。

EPUB检查在后台isolate执行，自写有界ZIP验证器，不调用研究版epub_view/epubx导入不可信文件。要求OCF首项未压缩mimetype、container→OPF、manifest/spine存在；逐项CRC校验，不解包到外部路径，不渲染正文/脚本。最多4096项、中央目录4 MiB、单项展开16 MiB、总展开128 MiB、元信息XML128 KiB、64层/4096标签/8192节点。仅stored/deflate；拒绝路径穿越/重复/重叠、DOCTYPE/ENTITY、加密标记（含字体混淆）、ZIP64与多卷等不支持形式。只取标题；不宣称完整EPUB兼容、DRM支持或完整阅读器已完成。

托管对象先完成，再在同一SQL事务写books/content_policy/documents/resources/imports及成人分组关系。schema5新增imports状态awaiting_parser，不伪造章节/进度。提交在单一队列串行；摘要＋格式重复沿用已有记录，保留旧标题/分级/位置；同名不同内容独立。重新导入相同原件可修复丢失/损坏托管对象；引用不能被重复导入静默转成托管。

## 取消与恢复

取消停止未提交项，之前已提交项保留，逐文件展示结果；关闭弹窗等候正在进行的清理，迟到结果不更新已销毁界面。SQL失败回滚并删除本次新对象，引用失败撤销新书签，未提交暂存清理；启动持有单写入租约后清除旧暂存。文件系统与SQL没有跨系统原子事务，崩溃窗口可能留孤儿对象/未引用书签，不能声称绝无残留；现有audit只报告正文孤儿，不自动删正文。

引用verify重新开授权并校验摘要；变化不覆盖旧修订，relink只接受相同摘要并以旧grant_id进行比较更新。新关联提交后旧书签清理失败不撤销新记录，可能留本机未引用书签。书签及grant_id不可跨设备同步/便携导出，MAC-14须转换为待关联状态；本批没有备份UI。

## 验证与后续

自动化覆盖真实SQLite与暂存/对象、并发、只读原件、错误编码、恶意包、取消、磁盘/事务注入、门禁、引用重开/失效/改动/重关联；真实AppKit选择、中文旧编码、托管与引用重启见[验收](../verifications/mac-04-2026-10-21.md)。真实物理满盘、断电和所有Finder桌面组合没有实测，矩阵中分别注明。

本步只导入已验证原件及元数据。文件卡片使用通用图标并标“阅读解析待接入”，不能跳到演示正文。下一步MAC-05接TXT DocumentReader与章节索引，MAC-07再接EPUB阅读资源；MAC-13菜单、快捷键、双模式窗口仍待实现。
