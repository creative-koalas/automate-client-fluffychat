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

    // 注册应用控制插件（用于退到后台）
    if let controller = window?.rootViewController as? FlutterViewController {
      let appControlChannel = FlutterMethodChannel(
        name: "com.creativekoalas.psygo/app_control",
        binaryMessenger: controller.binaryMessenger
      )

      appControlChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "moveToBackground" {
          self?.moveAppToBackground(result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
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

  /// 将应用移到后台
  /// iOS 限制：应用不能主动退到后台，这里使用一些 workaround
  private func moveAppToBackground(result: @escaping FlutterResult) {
    // iOS 安全策略：应用无法主动退到后台
    // 但我们可以通过触发 Home 按钮事件来实现类似效果

    // 方法1: 使用 URL scheme 打开系统设置（会切换到设置 app）
    // 这不完美，因为会打开设置而不是回到桌面，但至少会离开当前 app

    // 方法2: 使用私有 API（会被 App Store 拒绝，不推荐）
    // UIApplication.shared.perform(#selector(NSXPCConnection.suspend))

    // 方法3: 最安全的方法 - 通知 Dart 端不支持此功能
    // 让 Dart 代码决定如何处理（比如直接导航而不退到后台）

    // iOS 上我们无法安全地实现此功能
    // 返回 false 表示不支持
    result(false)
  }
}
