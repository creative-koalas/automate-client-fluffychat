import Cocoa
import CoreGraphics
import FlutterMacOS
import ImageIO
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private let screenshotChannelName = "com.creativekoalas.psygo/macos_screenshot"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerScreenshotChannel(flutterViewController)

    super.awakeFromNib()
  }

  private func registerScreenshotChannel(_ flutterViewController: FlutterViewController) {
    let screenshotChannel = FlutterMethodChannel(
      name: screenshotChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    screenshotChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Window released.", details: nil))
        return
      }
      self.handleScreenshotChannel(call: call, result: result)
    }
  }

  private func handleScreenshotChannel(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "captureScreenBuffer" else {
      result(FlutterMethodNotImplemented)
      return
    }

    print("[Screenshot] captureScreenBuffer invoked")

    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
      print("[Screenshot] Screen recording permission denied")
      result(FlutterError(code: "PERMISSION_DENIED", message: "Screen recording permission is required.", details: nil))
      return
    }

    guard let screenshot = CGWindowListCreateImage(
      .infinite,
      .optionOnScreenOnly,
      kCGNullWindowID,
      [.boundsIgnoreFraming, .bestResolution]
    ) else {
      print("[Screenshot] CGWindowListCreateImage returned nil")
      result(FlutterError(code: "CAPTURE_FAILED", message: "Failed to capture the current screen buffer.", details: nil))
      return
    }

    do {
      let outputUrl = try screenshotOutputURL()
      print("[Screenshot] Writing screen buffer to \(outputUrl.path)")
      guard let destination = CGImageDestinationCreateWithURL(
        outputUrl as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
        print("[Screenshot] Failed to create PNG destination")
        result(FlutterError(code: "WRITE_FAILED", message: "Unable to create PNG destination.", details: nil))
        return
      }

      CGImageDestinationAddImage(destination, screenshot, nil)
      guard CGImageDestinationFinalize(destination) else {
        print("[Screenshot] Failed to finalize PNG destination")
        result(FlutterError(code: "WRITE_FAILED", message: "Unable to finalize screenshot PNG.", details: nil))
        return
      }

      print("[Screenshot] Screen buffer captured successfully")
      result(outputUrl.path)
    } catch {
      print("[Screenshot] Failed to write screenshot: \(error.localizedDescription)")
      result(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private func screenshotOutputURL() throws -> URL {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let fileName = "psygo_screenshot_\(Int(Date().timeIntervalSince1970 * 1000)).png"
    let outputUrl = tempDir.appendingPathComponent(fileName)

    if FileManager.default.fileExists(atPath: outputUrl.path) {
      try FileManager.default.removeItem(at: outputUrl)
    }

    return outputUrl
  }
}
