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

        // 开启日志（SDK 2.14.12 已移除此方法）
        // TXCommonHandler.sharedInstance().getReporter().setLoggerEnable(true)

        TXCommonHandler.sharedInstance().setAuthSDKInfo(secretKey) { [weak self] resultDic in
            // resultDic 在新版 SDK 中不再是 Optional 类型
            let resultDic = resultDic as! [AnyHashable: Any]

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
            // resultDic 在新版 SDK 中不再是 Optional 类型
            let resultDic = resultDic as! [AnyHashable: Any]

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
            // resultDic 在新版 SDK 中不再是 Optional 类型
            let resultDic = resultDic as! [AnyHashable: Any]

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

            // 二次授权弹窗相关
            case "700006": // PNSCodeLoginClickPrivacyAlertView
                // 弹出二次授权弹窗，继续等待用户操作
                print("OneClickLogin iOS: Privacy alert view shown, waiting for user action...")
                // 不能调用 result，继续等待

            case "700007": // PNSCodeLoginPrivacyAlertViewClose
                // 二次授权弹窗关闭（用户点击继续后自动关闭，不是取消操作）
                print("OneClickLogin iOS: Privacy alert closed, waiting for token...")
                // 不能调用 result，弹窗在用户点击继续后会自动关闭，继续等待 token

            case "700008": // PNSCodeLoginPrivacyAlertViewClickContinue
                // 用户在二次授权弹窗点击"继续"，继续等待 token
                print("OneClickLogin iOS: User clicked continue in privacy alert, waiting for token...")
                // 不能调用 result，继续等待 token

            case "700009": // PNSCodeLoginPrivacyAlertViewPrivacyContentClick
                // 用户点击二次授权弹窗中的隐私协议
                print("OneClickLogin iOS: User clicked privacy content in alert")
                // 不能调用 result，继续等待

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

        // ========== 状态栏 ==========
        model.prefersStatusBarHidden = false
        if #available(iOS 13.0, *) {
            model.preferredStatusBarStyle = .darkContent  // 黑色文字（浅色状态栏）
        } else {
            model.preferredStatusBarStyle = .default
        }

        // ========== 页面背景 ==========
        model.backgroundColor = .white

        // ========== 导航栏（隐藏） ==========
        model.navIsHidden = true

        // 获取状态栏高度，用于适配安全区域
        let statusBarHeight: CGFloat
        if #available(iOS 13.0, *) {
            statusBarHeight = UIApplication.shared.windows.first?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
        } else {
            statusBarHeight = UIApplication.shared.statusBarFrame.height
        }

        // ========== Logo ==========
        model.logoIsHidden = false
        if let logoImage = UIImage(named: "auth_logo") {
            model.logoImage = logoImage
        }
        model.logoFrameBlock = { screenSize, superViewSize, frame in
            let logoSize: CGFloat = 90  // 与 Android 一致
            let topOffset: CGFloat = 100 + statusBarHeight  // 与 Android 一致
            return CGRect(
                x: (superViewSize.width - logoSize) / 2,
                y: topOffset,
                width: logoSize,
                height: logoSize
            )
        }

        // ========== Slogan ==========
        model.sloganIsHidden = false
        model.sloganText = NSAttributedString(
            string: "Psygo",
            attributes: [
                .foregroundColor: UIColor(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x1A/255.0, alpha: 1.0),  // #1A1A1A
                .font: UIFont.systemFont(ofSize: 20, weight: .medium)  // 与 Android 一致
            ]
        )
        model.sloganFrameBlock = { screenSize, superViewSize, frame in
            return CGRect(
                x: 0,
                y: 210 + statusBarHeight,  // 与 Android 一致
                width: superViewSize.width,
                height: 30
            )
        }

        // ========== 手机号（SDK 默认居中显示）==========
        model.numberColor = UIColor(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x1A/255.0, alpha: 1.0)  // #1A1A1A
        model.numberFont = UIFont.systemFont(ofSize: 28, weight: .medium)
        // 注意：numberFrameBlock 只有 x、y 生效，SDK会自动计算宽高
        // 不设置 x 则默认居中，这里只设置 y 值
        model.numberFrameBlock = { screenSize, superViewSize, frame in
            return CGRect(
                x: frame.origin.x,  // 使用SDK默认的x（居中）
                y: 260 + statusBarHeight,  // 与 Android 一致
                width: frame.size.width,  // 使用SDK默认的宽度
                height: frame.size.height  // 使用SDK默认的高度
            )
        }

        // ========== 登录按钮 ==========
        model.loginBtnText = NSAttributedString(
            string: "本机号码一键登录",
            attributes: [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 17, weight: .medium)
            ]
        )

        // 登录按钮背景（渐变蓝色按钮，和 Android 一致）
        // 注意：由于启用了二次确认弹窗，按钮在所有状态下都应该保持蓝色可点击
        let btnNormalImage = createGradientButtonImage(
            startColor: UIColor(red: 0x00/255.0, green: 0x7A/255.0, blue: 0xFF/255.0, alpha: 1.0),  // #007AFF
            endColor: UIColor(red: 0x00/255.0, green: 0x56/255.0, blue: 0xCC/255.0, alpha: 1.0),    // #0056CC
            cornerRadius: 24  // 与 Android 一致
        )
        // 禁用状态也使用蓝色（因为启用了二次确认弹窗，按钮始终可点击）
        let btnDisabledImage = btnNormalImage
        // 高亮状态使用稍深的蓝色
        let btnHighlightedImage = createGradientButtonImage(
            startColor: UIColor(red: 0x00/255.0, green: 0x66/255.0, blue: 0xE6/255.0, alpha: 1.0),  // #0066E6
            endColor: UIColor(red: 0x00/255.0, green: 0x44/255.0, blue: 0xB3/255.0, alpha: 1.0),    // #0044B3
            cornerRadius: 24  // 与 Android 一致
        )
        model.loginBtnBgImgs = [btnNormalImage, btnDisabledImage, btnHighlightedImage]

        model.loginBtnFrameBlock = { screenSize, superViewSize, frame in
            let horizontalMargin: CGFloat = 32  // 左右边距
            let btnWidth = superViewSize.width - horizontalMargin * 2
            let btnHeight: CGFloat = 50
            return CGRect(
                x: horizontalMargin,
                y: 340 + statusBarHeight,  // 与 Android 一致
                width: btnWidth,
                height: btnHeight
            )
        }

        // ========== 其他登录方式（隐藏） ==========
        model.changeBtnIsHidden = true

        // ========== 隐私协议 ==========
        model.checkBoxIsHidden = false
        model.checkBoxIsChecked = false  // 默认未勾选
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
            UIColor(red: 0x99/255.0, green: 0x99/255.0, blue: 0x99/255.0, alpha: 1.0),  // #999999
            UIColor(red: 0x00/255.0, green: 0x7A/255.0, blue: 0xFF/255.0, alpha: 1.0)   // #007AFF
        ]
        model.privacyFont = UIFont.systemFont(ofSize: 12)
        model.privacyAlignment = .center
        model.privacyOperatorPreText = "《"
        model.privacyOperatorSufText = "》"
        model.expandAuthPageCheckedScope = true

        model.privacyFrameBlock = { screenSize, superViewSize, frame in
            let horizontalMargin: CGFloat = 20
            let bottomMargin: CGFloat = 80
            let privacyHeight: CGFloat = 50
            return CGRect(
                x: horizontalMargin,
                y: superViewSize.height - bottomMargin,
                width: superViewSize.width - horizontalMargin * 2,
                height: privacyHeight
            )
        }

        // ========== 二次确认弹窗 ==========
        model.privacyAlertIsNeedShow = true  // 启用二次确认弹窗
        model.privacyAlertIsNeedAutoLogin = true  // 点击同意后自动登录

        // 弹窗标题
        model.privacyAlertTitleContent = "温馨提示"
        model.privacyAlertTitleFont = UIFont.systemFont(ofSize: 17, weight: .medium)
        model.privacyAlertTitleColor = UIColor(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x1A/255.0, alpha: 1.0)  // #1A1A1A
        model.privacyAlertTitleAlignment = .center

        // 弹窗内容（只显示协议链接，不要前后缀文案，保持和 Android 一致）
        model.privacyAlertPreText = ""
        model.privacyAlertSufText = ""
        model.privacyAlertContentFont = UIFont.systemFont(ofSize: 14)
        model.privacyAlertContentAlignment = .center
        model.privacyAlertContentColors = [
            UIColor(red: 0x66/255.0, green: 0x66/255.0, blue: 0x66/255.0, alpha: 1.0),  // #666666
            UIColor(red: 0x00/255.0, green: 0x7A/255.0, blue: 0xFF/255.0, alpha: 1.0)   // #007AFF
        ]

        // 弹窗按钮
        model.privacyAlertBtnContent = "同意并登录"
        model.privacyAlertButtonFont = UIFont.systemFont(ofSize: 15, weight: .medium)
        model.privacyAlertButtonTextColors = [UIColor.white, UIColor.white]
        model.privacyAlertBtnBackgroundImages = [btnNormalImage, btnHighlightedImage]
        model.privacyAlertCloseButtonIsNeedShow = true  // 显示关闭按钮

        // 弹窗背景遮罩
        model.privacyAlertMaskIsNeedShow = true
        model.privacyAlertMaskAlpha = 0.3
        model.privacyAlertCornerRadiusArray = [
            NSNumber(value: 16), NSNumber(value: 16),
            NSNumber(value: 16), NSNumber(value: 16)
        ]

        // 弹窗尺寸和位置（自适应布局）
        model.privacyAlertFrameBlock = { screenSize, superViewSize, frame in
            let alertWidth = screenSize.width - 80  // 左右各留40边距
            let alertHeight: CGFloat = 220
            return CGRect(
                x: (screenSize.width - alertWidth) / 2,
                y: (screenSize.height - alertHeight) / 2,
                width: alertWidth,
                height: alertHeight
            )
        }

        // 弹窗标题位置（自适应）
        model.privacyAlertTitleFrameBlock = { screenSize, superViewSize, frame in
            let margin: CGFloat = 20
            return CGRect(
                x: margin,
                y: margin,
                width: superViewSize.width - margin * 2,
                height: 25
            )
        }

        // 弹窗内容区域（自适应）
        model.privacyAlertPrivacyContentFrameBlock = { screenSize, superViewSize, frame in
            let margin: CGFloat = 20
            let titleHeight: CGFloat = 25
            let titleMargin: CGFloat = 20
            let contentTop = titleMargin + titleHeight + 10  // 标题下方留10pt间距
            return CGRect(
                x: margin,
                y: contentTop,
                width: superViewSize.width - margin * 2,
                height: 100
            )
        }

        // 弹窗按钮（自适应）
        model.privacyAlertButtonFrameBlock = { screenSize, superViewSize, frame in
            let margin: CGFloat = 20
            let btnHeight: CGFloat = 42
            return CGRect(
                x: margin,
                y: superViewSize.height - btnHeight - margin,
                width: superViewSize.width - margin * 2,
                height: btnHeight
            )
        }

        // 关闭按钮位置（自适应，距右侧15，距顶部0）
        model.privacyAlertCloseFrameBlock = { screenSize, superViewSize, frame in
            let btnSize: CGFloat = 44
            let rightMargin: CGFloat = 15
            return CGRect(
                x: superViewSize.width - btnSize - rightMargin,
                y: 0,
                width: btnSize,
                height: btnSize
            )
        }

        // ========== 登录loading动画 ==========
        // 自动隐藏登录loading，默认为YES
        model.autoHideLoginLoading = true

        // ========== 协议详情页（使用自定义处理） ==========
        model.privacyVCIsCustomized = true
        model.privacyNavColor = .white
        model.privacyNavTitleFont = UIFont.systemFont(ofSize: 18, weight: .medium)
        model.privacyNavTitleColor = .black

        return model
    }

    // MARK: - Helper Methods

    private func createGradientButtonImage(startColor: UIColor, endColor: UIColor, cornerRadius: CGFloat) -> UIImage {
        // 创建一个足够大的画布来绘制圆角矩形
        let size = CGSize(width: cornerRadius * 2 + 10, height: cornerRadius * 2)
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)

        guard let context = UIGraphicsGetCurrentContext() else {
            return UIImage()
        }

        // 创建圆角矩形路径
        let rect = CGRect(origin: .zero, size: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        path.addClip()

        // 创建水平渐变（从左到右，angle=0）
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [startColor.cgColor, endColor.cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]

        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
            return UIImage()
        }

        // 绘制水平渐变
        let startPoint = CGPoint(x: 0, y: rect.midY)
        let endPoint = CGPoint(x: rect.maxX, y: rect.midY)
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // 设置可拉伸区域，使图片可以缩放到任意尺寸
        return image?.resizableImage(
            withCapInsets: UIEdgeInsets(
                top: cornerRadius,
                left: cornerRadius,
                bottom: cornerRadius,
                right: cornerRadius
            ),
            resizingMode: .stretch
        ) ?? UIImage()
    }

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
