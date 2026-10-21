import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private func receiveDocuments(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    if let bridge = DocumentBridge.shared { bridge.receive(urls) }
    else { DocumentBridge.pending.append(contentsOf: urls) }
  }
  override func application(_ sender: NSApplication, open urls: [URL]) {
    receiveDocuments(urls.filter { $0.isFileURL })
    let other = urls.filter { !$0.isFileURL }
    if !other.isEmpty { super.application(sender, open: other) }
  }
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    receiveDocuments(filenames.map { URL(fileURLWithPath: $0) })
    sender.reply(toOpenOrPrint: .success)
  }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
