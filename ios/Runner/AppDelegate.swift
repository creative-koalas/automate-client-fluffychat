import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 注册一键登录插件
    if let registrar = self.registrar(forPlugin: "OneClickLoginPlugin") {
      OneClickLoginPlugin.register(with: registrar)
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    // iOS FIX: Prevent black screen when resuming from background
    // Set FlutterViewController background color to prevent black screen
    // when native modal views (like Aliyun auth) are dismissed
    if let controller = window?.rootViewController as? FlutterViewController {
      controller.view.backgroundColor = UIColor.white
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
