import Cocoa
import CoreFoundation
import FlutterMacOS
import UniformTypeIdentifiers

/// Read-only URLs granted by the system; no caller-supplied external path opens.
private struct DocumentBridgeFailure: Error { let code: String }
final class DocumentBridge {
  static var shared: DocumentBridge?
  static var pending: [URL] = []
  let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "local.yueqi.documents.io")
  private var urls: [String: URL] = [:]
  private var readers: [String: (FileHandle, URL, Bool)] = [:]
  private var ready = false
  private let limit = 64 * 1024 * 1024
  init(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "local.yueqi.documents", binaryMessenger: messenger)
    DocumentBridge.shared = self
    channel.setMethodCallHandler { [weak self] call, reply in self?.handle(call, reply) }
  }
  private func failure(_ code: String) -> DocumentBridgeFailure { DocumentBridgeFailure(code: code) }
  private func id(_ value: Any?) throws -> String {
    guard let value = value as? String, UUID(uuidString: value) != nil else { throw failure("permission") }
    return value
  }
  private func bookmarks() throws -> URL {
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let root = support.appendingPathComponent("local.yueqi.novel/novel-device/grants", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return root
  }
  private func register(_ values: [URL]) -> [[String: String]] {
    values.map { url in
      let key = UUID().uuidString
      urls[key] = url
      return ["id": key, "name": url.lastPathComponent]
    }
  }
  func receive(_ values: [URL]) {
    guard !values.isEmpty else { return }
    guard values.count <= 32 else {
      let alert = NSAlert(); alert.messageText = "每批最多32个文件"; alert.informativeText = "本次未导入，请减少所选文件后重试。"; alert.runModal(); return
    }
    guard ready else { DocumentBridge.pending.append(contentsOf: values); return }
    queue.async {
      let rows = self.register(values)
      DispatchQueue.main.async { self.channel.invokeMethod("incoming", arguments: rows) }
    }
  }
  private func resolve(_ key: String) throws -> URL {
    if let url = urls[key] { return url }
    let file = try bookmarks().appendingPathComponent(key)
    let info = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard info.isRegularFile == true, info.isSymbolicLink != true,
          let size = info.fileSize, size > 0, size < 1024 * 1024 else { throw failure("permission") }
    let data = try Data(contentsOf: file)
    guard data.count < 1024 * 1024 else { throw failure("permission") }
    var stale = false
    let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    guard !stale else { throw failure("permission") }
    urls[key] = url
    return url
  }
  private func handle(_ call: FlutterMethodCall, _ reply: @escaping FlutterResult) {
    if call.method == "ready" {
      ready = true
      let initial = DocumentBridge.pending
      DocumentBridge.pending = []
      receive(initial)
      reply(nil)
      return
    }
    if call.method == "choose" {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = true
      panel.canChooseDirectories = false
      panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "epub") ?? .data]
      panel.prompt = "选择文件"
      panel.begin { response in
        var selected = response == .OK ? panel.urls : []
        if selected.count > 32 {
          let alert = NSAlert(); alert.messageText = "每批最多32个文件"; alert.informativeText = "本次未导入，请减少所选文件后重试。"; alert.runModal(); selected = []
        }
        self.queue.async {
          let rows = self.register(selected)
          DispatchQueue.main.async { reply(rows) }
        }
      }
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    queue.async {
      do {
        let result = try self.perform(call.method, args)
        DispatchQueue.main.async { reply(result) }
      } catch {
        let failure = FlutterError(code: (error as? DocumentBridgeFailure)?.code ?? "permission", message: nil, details: nil)
        DispatchQueue.main.async { reply(failure) }
      }
    }
  }
  private func perform(_ method: String, _ args: [String: Any]) throws -> Any? {
    if method == "decodeSnapshot" {
      guard let path = args["path"] as? String, let encoding = args["encoding"] as? String,
            ["gb18030", "big5"].contains(encoding) else { throw failure("encoding") }
      let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
      let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).resolvingSymlinksInPath()
      guard url.path.hasPrefix(support.path + "/"), url.path.contains("/novel/import-stage/"),
            (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? limit + 1) <= limit else { throw failure("encoding") }
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      return try NativeTextCodec.preview(data, encoding: encoding)
    }
    if method == "read" || method == "close" {
      let key = try id(args["handle"])
      guard let (file, url, scoped) = readers[key] else { throw failure("permission") }
      if method == "close" {
        readers.removeValue(forKey: key)
        try? file.close()
        if scoped { url.stopAccessingSecurityScopedResource() }
        return nil
      }
      return FlutterStandardTypedData(bytes: try file.read(upToCount: 64 * 1024) ?? Data())
    }
    let key = try id(args["id"])
    if method == "release" { urls.removeValue(forKey: key); return nil }
    if method == "forget" {
      urls.removeValue(forKey: key)
      let file = try bookmarks().appendingPathComponent(key)
      if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
      return nil
    }
    let url = try resolve(key)
    let scoped = url.startAccessingSecurityScopedResource()
    var transferred = false
    defer { if scoped && !transferred { url.stopAccessingSecurityScopedResource() } }
    let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard info.isRegularFile == true, info.isSymbolicLink != true else { throw failure("missing") }
    guard let size = info.fileSize, size > 0, size <= limit else { throw failure("tooLarge") }
    switch method {
    case "restore":
      let test = try FileHandle(forReadingFrom: url); try test.close()
      return ["name": url.lastPathComponent]
    case "open":
      guard readers.count < 4 else { throw failure("permission") }
      let handle = UUID().uuidString
      let start = (args["start"] as? NSNumber)?.int64Value ?? 0
      guard start >= 0, start <= Int64(size) else { throw failure("missing") }
      let file = try FileHandle(forReadingFrom: url)
      do { try file.seek(toOffset: UInt64(start)) }
      catch { try? file.close(); throw error }
      readers[handle] = (file, url, scoped)
      transferred = true
      return handle
    case "retain":
      let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
      let file = try bookmarks().appendingPathComponent(key)
      try data.write(to: file, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      return nil
    default: throw failure("unsupported")
    }
  }
}
