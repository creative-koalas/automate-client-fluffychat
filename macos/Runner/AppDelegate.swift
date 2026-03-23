import Cocoa
import Carbon.HIToolbox
import FlutterMacOS

let screenshotHotKeySignature: OSType = 0x50535947
let screenshotHotKeyIdentifier: UInt32 = 1
let screenshotHotKeyNotificationName = Notification.Name(
  "com.creativekoalas.psygo.globalScreenshotHotKeyPressed"
)

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      if let window = sender.windows.first {
        window.makeKeyAndOrderFront(self)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    GlobalScreenshotHotKeyManager.shared.unregister()
    super.applicationWillTerminate(notification)
  }
}

final class GlobalScreenshotHotKeyManager {
  static let shared = GlobalScreenshotHotKeyManager()

  private var screenshotHotKeyRef: EventHotKeyRef?
  private var screenshotHotKeyHandlerRef: EventHandlerRef?

  private init() {}

  private func log(_ message: String) {
    NSLog("[GlobalHotKey] \(message)")
  }

  func ensureRegistered() {
    guard screenshotHotKeyRef == nil else {
      log("register skipped because hotkey is already registered")
      return
    }

    log("Installing hotkey handler")
    let eventTarget = GetEventDispatcherTarget()

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let handlerStatus = InstallEventHandler(
      eventTarget,
      { _, event, _ in
        guard let event else {
          return noErr
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard status == noErr else {
          NSLog("[GlobalHotKey] Failed to read hotkey event parameter: \(status)")
          return status
        }
        guard hotKeyID.signature == screenshotHotKeySignature,
          hotKeyID.id == screenshotHotKeyIdentifier else {
          return noErr
        }

        DispatchQueue.main.async {
          NotificationCenter.default.post(name: screenshotHotKeyNotificationName, object: nil)
        }
        return noErr
      },
      1,
      &eventType,
      nil,
      &screenshotHotKeyHandlerRef
    )
    if handlerStatus != noErr {
      log("Failed to install macOS screenshot hotkey handler: \(handlerStatus)")
      screenshotHotKeyHandlerRef = nil
      return
    }

    log("Hotkey handler installed successfully")

    let hotKeyID = EventHotKeyID(
      signature: screenshotHotKeySignature,
      id: screenshotHotKeyIdentifier
    )
    let modifiers = UInt32(cmdKey | optionKey)
    let keyCode = UInt32(kVK_ANSI_S)
    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      eventTarget,
      0,
      &screenshotHotKeyRef
    )

    if status != noErr {
      log("Failed to register macOS screenshot hotkey: \(status)")
      screenshotHotKeyRef = nil
      return
    }

    log("Registered macOS screenshot hotkey keyCode=\(keyCode) modifiers=\(modifiers)")
  }

  func unregister() {
    if let screenshotHotKeyRef {
      log("Unregistering macOS screenshot hotkey")
      UnregisterEventHotKey(screenshotHotKeyRef)
      self.screenshotHotKeyRef = nil
    }
    if let screenshotHotKeyHandlerRef {
      log("Removing macOS screenshot hotkey handler")
      RemoveEventHandler(screenshotHotKeyHandlerRef)
      self.screenshotHotKeyHandlerRef = nil
    }
  }
}
