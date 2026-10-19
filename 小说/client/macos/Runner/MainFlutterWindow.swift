import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    #if DEBUG
    let probeRegistrar = flutterViewController.registrar(forPlugin: "Mac06Probe")
    probeRegistrar.register(Mac06Factory(probeRegistrar.messenger), withId: "local.yueqi.mac06.webview")
    #endif

    super.awakeFromNib()
  }
}
