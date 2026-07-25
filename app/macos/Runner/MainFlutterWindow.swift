import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Extend content under the titlebar and reclaim that band for the shell.
    // The traffic lights stay real — they just float over our content, which
    // insets itself on the left to clear them.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)
    EmbedderTexturePlugin.register(
      with: flutterViewController.registrar(forPlugin: "EmbedderTexturePlugin"))

    super.awakeFromNib()
  }
}
