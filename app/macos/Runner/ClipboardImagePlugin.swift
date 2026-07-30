import AppKit
import FlutterMacOS

/// Puts an image on the system clipboard.
///
/// Flutter's own `Clipboard` carries text and nothing else, so copying a
/// catalog preview has no framework route. The alternative was a package that
/// builds through cargokit — and since the CLI compiles this app on the user's
/// machine at first run, that would make a Rust toolchain a requirement for
/// installing flutterware. A pasteboard write is small enough to own.
public class ClipboardImagePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutterware/clipboard",
      binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(ClipboardImagePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall,
                     result: @escaping FlutterResult) {
    switch call.method {
    case "setImage":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let data = args["png"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args",
                            message: "png bytes required", details: nil))
        return
      }
      // Decoded first as a check on the bytes, and because TIFF below is
      // derived from it. `writeObjects([image])` on its own is *not* enough:
      // NSImage advertises only `.tiff` as a writable pasteboard type, so a
      // target that reads `public.png` — several Electron and web-based editors
      // do exactly that — would find nothing, while `writeObjects` still
      // returned true and the copy reported success.
      guard let image = NSImage(data: data.data) else {
        result(FlutterError(code: "decode_failed",
                            message: "the bytes are not a readable image",
                            details: nil))
        return
      }
      let pasteboard = NSPasteboard.general
      // Clears the pasteboard as well as announcing the types. Both are needed:
      // without the clear the new item joins whatever was already there and the
      // paste target picks by its own preference order rather than getting what
      // was just copied.
      //
      // PNG first, because the order here *is* the offered preference order and
      // the PNG is the bytes we were handed — a target that can take either
      // should get those rather than a re-encode.
      pasteboard.declareTypes([.png, .tiff], owner: nil)
      var wrote = pasteboard.setData(data.data, forType: .png)
      // TIFF as well, for the targets that only ever learned that one.
      if let tiff = image.tiffRepresentation {
        wrote = pasteboard.setData(tiff, forType: .tiff) || wrote
      }
      result(NSNumber(value: wrote))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
