import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
  @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
    DocumentBridge.shared?.receive(urls)
    return true
  }
  private var readingWindowChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    _ = DocumentBridge(flutterViewController.engine.binaryMessenger)
    readingWindowChannel = FlutterMethodChannel(name: "reader/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    readingWindowChannel?.setMethodCallHandler { [weak self] call, reply in
      if call.method == "fullscreen" { self?.toggleFullScreen(nil); reply(nil) }
      else { reply(FlutterMethodNotImplemented) }
    }
    registerForDraggedTypes([.fileURL])
    let epubRegistrar = flutterViewController.registrar(forPlugin: "EpubReader")
    epubRegistrar.register(EpubFactory(epubRegistrar.messenger), withId: "local.yueqi.epub")
    #if DEBUG
    let probeRegistrar = flutterViewController.registrar(forPlugin: "Mac06Probe")
    probeRegistrar.register(Mac06Factory(probeRegistrar.messenger), withId: "local.yueqi.mac06.webview")
    #endif

    super.awakeFromNib()
  }
}
