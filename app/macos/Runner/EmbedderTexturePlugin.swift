import Cocoa
import CoreVideo
import FlutterMacOS
import IOSurface

/// An external Flutter texture backed by a ring of shared IOSurfaces.
class EmbedderTexture: NSObject, FlutterTexture {
  private var buffers: [CVPixelBuffer]
  private var currentIndex: Int = 0
  private let lock = NSLock()

  init?(surfaceIds: [UInt32]) {
    guard let created = EmbedderTexture.wrap(surfaceIds) else { return nil }
    self.buffers = created
    super.init()
  }

  private static func wrap(_ surfaceIds: [UInt32]) -> [CVPixelBuffer]? {
    // The Flutter engine composites the returned pixel buffer through a Metal
    // texture cache, so the buffer must be flagged Metal-compatible.
    let attrs: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true]
    var result: [CVPixelBuffer] = []
    for id in surfaceIds {
      guard let surface = IOSurfaceLookup(IOSurfaceID(id)) else { return nil }
      var pixelBuffer: Unmanaged<CVPixelBuffer>?
      let status = CVPixelBufferCreateWithIOSurface(
        kCFAllocatorDefault, surface, attrs as CFDictionary, &pixelBuffer)
      guard status == kCVReturnSuccess, let pb = pixelBuffer else {
        return nil
      }
      result.append(pb.takeRetainedValue())
    }
    return result
  }

  /// Re-wraps a fresh set of surfaces after a resize. Returns false if any
  /// lookup fails.
  func setSurfaces(_ surfaceIds: [UInt32]) -> Bool {
    guard let created = EmbedderTexture.wrap(surfaceIds) else { return false }
    lock.lock()
    buffers = created
    currentIndex = 0
    lock.unlock()
    return true
  }

  func setCurrentIndex(_ index: Int) {
    lock.lock()
    if index >= 0 && index < buffers.count { currentIndex = index }
    lock.unlock()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard currentIndex < buffers.count else { return nil }
    return Unmanaged.passRetained(buffers[currentIndex])
  }
}

public class EmbedderTexturePlugin: NSObject, FlutterPlugin {
  private let registry: FlutterTextureRegistry
  private var textures: [Int64: EmbedderTexture] = [:]

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutterware/embedder_texture",
      binaryMessenger: registrar.messenger)
    let instance = EmbedderTexturePlugin(registry: registrar.textures)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall,
                     result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "createTexture":
      guard let ids = args["surfaceIds"] as? [Int] else {
        result(FlutterError(code: "bad_args",
                            message: "surfaceIds required", details: nil))
        return
      }
      let surfaceIds = ids.map { UInt32(truncatingIfNeeded: $0) }
      guard let texture = EmbedderTexture(surfaceIds: surfaceIds) else {
        result(FlutterError(code: "lookup_failed",
                            message: "IOSurfaceLookup failed", details: nil))
        return
      }
      let textureId = registry.register(texture)
      textures[textureId] = texture
      result(NSNumber(value: textureId))
    case "updateSurfaces":
      guard let textureId = (args["textureId"] as? Int).map({ Int64($0) }),
            let ids = args["surfaceIds"] as? [Int],
            let texture = textures[textureId] else {
        result(FlutterError(code: "bad_args",
                            message: "unknown texture", details: nil))
        return
      }
      let ok = texture.setSurfaces(
        ids.map { UInt32(truncatingIfNeeded: $0) })
      result(NSNumber(value: ok))
    case "markFrameAvailable":
      guard let textureId = (args["textureId"] as? Int).map({ Int64($0) }),
            let ringIndex = args["ringIndex"] as? Int,
            let texture = textures[textureId] else {
        result(FlutterError(code: "bad_args",
                            message: "unknown texture", details: nil))
        return
      }
      texture.setCurrentIndex(ringIndex)
      registry.textureFrameAvailable(textureId)
      result(nil)
    case "disposeTexture":
      if let textureId = (args["textureId"] as? Int).map({ Int64($0) }) {
        registry.unregisterTexture(textureId)
        textures.removeValue(forKey: textureId)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
