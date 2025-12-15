import Flutter
import UIKit
import ATAuthSDK

/// 阿里云一键登录 Flutter 插件（iOS 端）
///
/// 正确流程：
/// 1. initSdk - 初始化 SDK
/// 2. accelerateLogin - 预取号（必须成功后才能唤起授权页）
/// 3. oneClickLogin - 唤起授权页获取 token
class OneClickLoginPlugin: NSObject, FlutterPlugin {

    private static let channelName = "com.creativekoalas.psygo/one_click_login"

    private var isPreLoginSuccess = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = OneClickLoginPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initSdk":
            guard let args = call.arguments as? [String: Any],
                  let secretKey = args["secretKey"] as? String, !secretKey.isEmpty else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "secretKey is required", details: nil))
                return
            }
            initSdk(secretKey: secretKey, result: result)

        case "accelerateLogin":
            let timeout = (call.arguments as? [String: Any])?["timeout"] as? Int ?? 5000
            accelerateLogin(timeout: timeout, result: result)

        case "oneClickLogin":
            let timeout = (call.arguments as? [String: Any])?["timeout"] as? Int ?? 5000
            oneClickLogin(timeout: timeout, result: result)

        case "checkEnvAvailable":
            checkEnvAvailable(result: result)

        case "quitLoginPage":
            quitLoginPage(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - SDK Methods

    private func initSdk(secretKey: String, result: @escaping FlutterResult) {
        print("OneClickLogin iOS: Initializing SDK...")

        // 重置预取号状态
        isPreLoginSuccess = false

        // 开启日志
        TXCommonHandler.sharedInstance().getReporter().setLoggerEnable(true)

        TXCommonHandler.sharedInstance().setAuthSDKInfo(secretKey) { [weak self] resultDic in
            guard let resultDic = resultDic else {
                result([
                    "code": "600010",
                    "msg": "SDK初始化失败：返回结果为空"
                ])
                return
            }

            let code = resultDic["resultCode"] as? String ?? "600010"
            let msg = resultDic["msg"] as? String ?? "未知错误"

            print("OneClickLogin iOS: SDK init result - code: \(code), msg: \(msg)")

            if code == PNSCodeSuccess {
                result([
                    "code": "600000",
                    "msg": "SDK初始化成功"
                ])
            } else {
                result([
                    "code": code,
                    "msg": msg
                ])
            }
        }
    }

    private func accelerateLogin(timeout: Int, result: @escaping FlutterResult) {
        print("OneClickLogin iOS: Starting accelerateLoginPage with timeout: \(timeout)")

        let timeoutSeconds = TimeInterval(timeout) / 1000.0

        TXCommonHandler.sharedInstance().accelerateLoginPage(withTimeout: timeoutSeconds) { [weak self] resultDic in
            guard let resultDic = resultDic else {
                result(FlutterError(code: "PRE_LOGIN_FAILED", message: "预取号失败：返回结果为空", details: nil))
                return
            }

            let code = resultDic["resultCode"] as? String ?? "600010"
            let msg = resultDic["msg"] as? String ?? "未知错误"

            print("OneClickLogin iOS: Pre-login result - code: \(code), msg: \(msg)")

            if code == PNSCodeSuccess {
                self?.isPreLoginSuccess = true
                result([
                    "code": "600000",
                    "msg": "预取号成功",
                    "vendor": resultDic["carrierName"] ?? "unknown"
                ])
            } else {
                self?.isPreLoginSuccess = false
                result(FlutterError(code: code, message: "预取号失败: \(msg)", details: nil))
            }
        }
    }

    private func checkEnvAvailable(result: @escaping FlutterResult) {
        print("OneClickLogin iOS: Checking environment...")

        TXCommonHandler.sharedInstance().checkEnvAvailable(with: .loginToken) { resultDic in
            guard let resultDic = resultDic else {
                result([
                    "code": "600010",
                    "msg": "环境检查失败：返回结果为空"
                ])
                return
            }

            let code = resultDic["resultCode"] as? String ?? "600010"
            let msg = resultDic["msg"] as? String ?? "未知错误"

            print("OneClickLogin iOS: Environment check result - code: \(code), msg: \(msg)")

            result([
                "code": code,
                "msg": msg
            ])
        }
    }

    private func oneClickLogin(timeout: Int, result: @escaping FlutterResult) {
        print("OneClickLogin iOS: Starting login with timeout: \(timeout), preLoginSuccess: \(isPreLoginSuccess)")

        guard let viewController = getTopViewController() else {
            result(FlutterError(code: "NO_ACTIVITY", message: "无法获取当前 ViewController", details: nil))
            return
        }

        if !isPreLoginSuccess {
            print("OneClickLogin iOS: Warning - Pre-login not completed, attempting anyway...")
        }

        let timeoutSeconds = TimeInterval(timeout) / 1000.0

        // 配置授权页 UI
        let model = buildAuthUIModel()

        TXCommonHandler.sharedInstance().getLoginToken(withTimeout: timeoutSeconds, controller: viewController, model: model) { [weak self] resultDic in
            guard let resultDic = resultDic else {
                result(FlutterError(code: "LOGIN_FAILED", message: "登录失败：返回结果为空", details: nil))
                return
            }

            let code = resultDic["resultCode"] as? String ?? "600010"
            let msg = resultDic["msg"] as? String ?? "未知错误"

            print("OneClickLogin iOS: Login result - code: \(code), msg: \(msg)")

            switch code {
            case PNSCodeSuccess:
                // 获取 token 成功
                let token = resultDic["token"] as? String ?? ""
                print("OneClickLogin iOS: Got token: \(String(token.prefix(20)))...")
                result([
                    "code": code,
                    "msg": msg,
                    "token": token
                ])

            case PNSCodeLoginControllerPresentSuccess:
                // 授权页唤起成功，继续等待用户操作
                print("OneClickLogin iOS: Auth page launched successfully, waiting for user action...")
                // 注意：这里不能调用 result，因为还在等待用户操作
                // SDK 会在用户点击登录后再次回调

            case PNSCodeLoginControllerClickCancel:
                // 用户点击返回按钮
                result(FlutterError(code: "USER_CANCEL", message: msg, details: nil))
                TXCommonHandler.sharedInstance().cancelLoginVC(animated: true, complete: nil)

            case PNSCodeLoginControllerClickChangeBtn:
                // 用户点击"其他方式登录"
                result([
                    "code": "700001",
                    "msg": "用户选择其他登录方式"
                ])
                TXCommonHandler.sharedInstance().cancelLoginVC(animated: true, complete: nil)

            case PNSCodeLoginControllerClickLoginBtn:
                // 用户点击登录按钮，继续等待 token 获取结果
                print("OneClickLogin iOS: User clicked login button, waiting for token...")

            case PNSCodeLoginControllerClickCheckBoxBtn:
                // 用户点击 checkbox
                print("OneClickLogin iOS: User clicked checkbox")

            case PNSCodeLoginControllerClickProtocol:
                // 用户点击协议链接
                print("OneClickLogin iOS: User clicked protocol link")
                // 处理自定义协议跳转
                if let privacyUrl = resultDic["privacyUrl"] as? String {
                    self?.handleProtocolClick(url: privacyUrl)
                }

            default:
                // 其他错误
                result(FlutterError(code: code, message: msg, details: nil))
                TXCommonHandler.sharedInstance().cancelLoginVC(animated: true, complete: nil)
            }
        }
    }

    private func quitLoginPage(result: @escaping FlutterResult) {
        TXCommonHandler.sharedInstance().cancelLoginVC(animated: true) {
            result(true)
        }
    }

    // MARK: - UI Configuration

    private func buildAuthUIModel() -> TXCustomModel {
        let model = TXCustomModel()

        // 状态栏
        model.prefersStatusBarHidden = false
        model.preferredStatusBarStyle = .darkContent

        // 背景
        model.backgroundColor = .white

        // 导航栏 - 隐藏
        model.navIsHidden = true

        // Logo
        model.logoIsHidden = false
        if let logoImage = UIImage(named: "auth_logo") {
            model.logoImage = logoImage
        }
        model.logoFrameBlock = { screenSize, superViewSize, frame in
            let logoSize: CGFloat = 90
            let topOffset: CGFloat = 100
            return CGRect(
                x: (superViewSize.width - logoSize) / 2,
                y: topOffset,
                width: logoSize,
                height: logoSize
            )
        }

        // Slogan
        model.sloganIsHidden = false
        model.sloganText = NSAttributedString(
            string: "Psygo",
            attributes: [
                .foregroundColor: UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
                .font: UIFont.systemFont(ofSize: 20, weight: .medium)
            ]
        )
        model.sloganFrameBlock = { screenSize, superViewSize, frame in
            return CGRect(
                x: 0,
                y: 210,
                width: superViewSize.width,
                height: 30
            )
        }

        // 手机号
        model.numberColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        model.numberFont = UIFont.systemFont(ofSize: 28, weight: .medium)
        model.numberFrameBlock = { screenSize, superViewSize, frame in
            return CGRect(
                x: 0,
                y: 260,
                width: superViewSize.width,
                height: 40
            )
        }

        // 登录按钮
        model.loginBtnText = NSAttributedString(
            string: "本机号码一键登录",
            attributes: [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 17, weight: .medium)
            ]
        )

        // 登录按钮背景图片
        let btnNormalImage = createRoundedRectImage(color: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0), cornerRadius: 25)
        let btnDisabledImage = createRoundedRectImage(color: UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0), cornerRadius: 25)
        let btnHighlightedImage = createRoundedRectImage(color: UIColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 1.0), cornerRadius: 25)
        model.loginBtnBgImgs = [btnNormalImage, btnDisabledImage, btnHighlightedImage]

        model.loginBtnFrameBlock = { screenSize, superViewSize, frame in
            let btnWidth = superViewSize.width - 64
            let btnHeight: CGFloat = 50
            return CGRect(
                x: 32,
                y: 340,
                width: btnWidth,
                height: btnHeight
            )
        }

        // 隐藏"其他方式登录"按钮
        model.changeBtnIsHidden = true

        // 协议 Checkbox
        model.checkBoxIsHidden = false
        model.checkBoxIsChecked = false
        model.checkBoxWH = 20
        if let uncheckedImage = UIImage(named: "auth_checkbox_unchecked"),
           let checkedImage = UIImage(named: "auth_checkbox_checked") {
            model.checkBoxImages = [uncheckedImage, checkedImage]
        }

        // 协议文案
        model.privacyPreText = "登录即同意"
        model.privacySufText = ""
        model.privacyOne = ["《用户协议》", "app-privacy://user_agreement"]
        model.privacyTwo = ["《隐私政策》", "app-privacy://privacy_policy"]
        model.privacyConectTexts = ["和", "、", "、"]
        model.privacyColors = [
            UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0),
            UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        ]
        model.privacyFont = UIFont.systemFont(ofSize: 12)
        model.privacyAlignment = .center
        model.privacyOperatorPreText = "《"
        model.privacyOperatorSufText = "》"
        model.expandAuthPageCheckedScope = true

        model.privacyFrameBlock = { screenSize, superViewSize, frame in
            return CGRect(
                x: 20,
                y: superViewSize.height - 80,
                width: superViewSize.width - 40,
                height: 50
            )
        }

        // 二次确认弹窗
        model.privacyAlertIsNeedShow = true
        model.privacyAlertIsNeedAutoLogin = true
        model.privacyAlertTitleContent = "温馨提示"
        model.privacyAlertTitleFont = UIFont.systemFont(ofSize: 17, weight: .medium)
        model.privacyAlertTitleColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        model.privacyAlertTitleAlignment = .center
        model.privacyAlertContentFont = UIFont.systemFont(ofSize: 14)
        model.privacyAlertContentColors = [
            UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0),
            UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        ]
        model.privacyAlertBtnContent = "同意并登录"
        model.privacyAlertButtonFont = UIFont.systemFont(ofSize: 15, weight: .medium)
        model.privacyAlertButtonTextColors = [UIColor.white, UIColor.white]
        model.privacyAlertBtnBackgroundImages = [btnNormalImage, btnHighlightedImage]
        model.privacyAlertCloseButtonIsNeedShow = true
        model.privacyAlertMaskIsNeedShow = true
        model.privacyAlertMaskAlpha = 0.3
        model.privacyAlertCornerRadiusArray = [NSNumber(value: 16), NSNumber(value: 16), NSNumber(value: 16), NSNumber(value: 16)]
        model.privacyAlertContentAlignment = .center

        model.privacyAlertFrameBlock = { screenSize, superViewSize, frame in
            let alertWidth: CGFloat = 280
            let alertHeight: CGFloat = 200
            return CGRect(
                x: (screenSize.width - alertWidth) / 2,
                y: (screenSize.height - alertHeight) / 2,
                width: alertWidth,
                height: alertHeight
            )
        }

        model.privacyAlertButtonFrameBlock = { screenSize, superViewSize, frame in
            return CGRect(
                x: 20,
                y: superViewSize.height - 62,
                width: superViewSize.width - 40,
                height: 42
            )
        }

        // 协议详情页
        model.privacyVCIsCustomized = true  // 使用自定义处理协议链接点击
        model.privacyNavColor = .white
        model.privacyNavTitleFont = UIFont.systemFont(ofSize: 18, weight: .medium)
        model.privacyNavTitleColor = .black

        return model
    }

    // MARK: - Helper Methods

    private func createRoundedRectImage(color: UIColor, cornerRadius: CGFloat) -> UIImage {
        let size = CGSize(width: cornerRadius * 2 + 10, height: cornerRadius * 2)
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)

        let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius)
        color.setFill()
        path.fill()

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image?.resizableImage(withCapInsets: UIEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius), resizingMode: .stretch) ?? UIImage()
    }

    private func handleProtocolClick(url: String) {
        // 处理自定义协议跳转
        // app-privacy://user_agreement -> 用户协议页面
        // app-privacy://privacy_policy -> 隐私政策页面
        print("OneClickLogin iOS: Protocol clicked - \(url)")

        // 关闭授权页后由 Flutter 端处理跳转
        // 这里可以通过 EventChannel 或其他方式通知 Flutter 端
    }

    private func getTopViewController() -> UIViewController? {
        var keyWindow: UIWindow?

        if #available(iOS 13.0, *) {
            keyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            keyWindow = UIApplication.shared.keyWindow
        }

        guard let rootViewController = keyWindow?.rootViewController else {
            return nil
        }

        return getTopViewController(from: rootViewController)
    }

    private func getTopViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return getTopViewController(from: presented)
        }
        if let navigationController = viewController as? UINavigationController,
           let visible = navigationController.visibleViewController {
            return getTopViewController(from: visible)
        }
        if let tabBarController = viewController as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            return getTopViewController(from: selected)
        }
        return viewController
    }
}
