package com.creativekoalas.psygo

import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.util.Log
import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.mobile.auth.gatewayauth.PhoneNumberAuthHelper
import com.mobile.auth.gatewayauth.TokenResultListener
import com.mobile.auth.gatewayauth.PreLoginResultListener
import com.mobile.auth.gatewayauth.ResultCode
import com.mobile.auth.gatewayauth.model.TokenRet
import com.mobile.auth.gatewayauth.AuthUIConfig
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.util.TypedValue
import com.mobile.auth.gatewayauth.ActivityResultListener
import com.mobile.auth.gatewayauth.CustomInterface

/**
 * 阿里云一键登录 Flutter 插件（使用官方 SDK）
 *
 * 正确流程：
 * 1. initSdk - 初始化 SDK
 * 2. accelerateLogin - 预取号（必须成功后才能唤起授权页）
 * 3. oneClickLogin - 唤起授权页获取 token
 */
class OneClickLoginPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    companion object {
        private const val TAG = "OneClickLoginPlugin"
        private const val CHANNEL = "com.creativekoalas.psygo/one_click_login"
    }

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var phoneNumberAuthHelper: PhoneNumberAuthHelper? = null
    private var pendingResult: Result? = null
    private var isPreLoginSuccess: Boolean = false  // 预取号是否成功
    private var previousDecorFitsSystemWindows: Boolean? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        Log.d(TAG, "Plugin attached to engine")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        phoneNumberAuthHelper?.setAuthListener(null)
        phoneNumberAuthHelper = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        Log.d(TAG, "Plugin attached to activity")
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initSdk" -> {
                val secretKey = call.argument<String>("secretKey")
                if (secretKey.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "secretKey is required", null)
                    return
                }
                initSdk(secretKey, result)
            }
            "accelerateLogin" -> {
                val timeout = call.argument<Int>("timeout") ?: 5000
                accelerateLogin(timeout, result)
            }
            "oneClickLogin" -> {
                val timeout = call.argument<Int>("timeout") ?: 5000
                oneClickLogin(timeout, result)
            }
            "checkEnvAvailable" -> {
                checkEnvAvailable(result)
            }
            "quitLoginPage" -> {
                quitLoginPage(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun initSdk(secretKey: String, result: Result) {
        val ctx = context
        if (ctx == null) {
            result.error("NO_CONTEXT", "Context is not available", null)
            return
        }

        try {
            val tokenResultListener = object : TokenResultListener {
                override fun onTokenSuccess(response: String) {
                    Log.d(TAG, "Token success: $response")
                    handleTokenResult(response, true)
                }

                override fun onTokenFailed(response: String) {
                    Log.e(TAG, "Token failed: $response")
                    handleTokenResult(response, false)
                }
            }

            phoneNumberAuthHelper = PhoneNumberAuthHelper.getInstance(ctx, tokenResultListener)
            phoneNumberAuthHelper?.getReporter()?.setLoggerEnable(true)
            phoneNumberAuthHelper?.setAuthSDKInfo(secretKey)

            // 重置预取号状态
            isPreLoginSuccess = false

            Log.d(TAG, "SDK initialized successfully")
            result.success(mapOf(
                "code" to "600000",
                "msg" to "SDK初始化成功"
            ))
        } catch (e: Exception) {
            Log.e(TAG, "SDK init failed", e)
            result.error("INIT_FAILED", e.message, null)
        }
    }

    /**
     * 预取号（加速登录）
     * 必须在 getLoginToken 之前调用并成功
     */
    private fun accelerateLogin(timeout: Int, result: Result) {
        val helper = phoneNumberAuthHelper
        if (helper == null) {
            result.error("NOT_INITIALIZED", "请先调用 initSdk", null)
            return
        }

        try {
            Log.d(TAG, "Starting accelerateLoginPage with timeout: $timeout")

            helper.accelerateLoginPage(timeout, object : PreLoginResultListener {
                override fun onTokenSuccess(vendor: String?) {
                    Log.d(TAG, "Pre-login success, vendor: $vendor")
                    isPreLoginSuccess = true
                    activity?.runOnUiThread {
                        result.success(mapOf(
                            "code" to "600000",
                            "msg" to "预取号成功",
                            "vendor" to (vendor ?: "unknown")
                        ))
                    }
                }

                override fun onTokenFailed(vendor: String?, errorCode: String?) {
                    Log.e(TAG, "Pre-login failed, vendor: $vendor, errorCode: $errorCode")
                    isPreLoginSuccess = false
                    activity?.runOnUiThread {
                        result.error(
                            errorCode ?: "PRE_LOGIN_FAILED",
                            "预取号失败: vendor=$vendor, code=$errorCode",
                            null
                        )
                    }
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "Accelerate login failed", e)
            result.error("ACCELERATE_FAILED", e.message, null)
        }
    }

    private fun checkEnvAvailable(result: Result) {
        val helper = phoneNumberAuthHelper
        if (helper == null) {
            result.error("NOT_INITIALIZED", "请先调用 initSdk", null)
            return
        }

        try {
            // 使用 SERVICE_TYPE_LOGIN = 1 检查一键登录环境
            helper.checkEnvAvailable(PhoneNumberAuthHelper.SERVICE_TYPE_LOGIN)
            Log.d(TAG, "Environment check started (async)")
            // 注意：实际结果通过 TokenResultListener 回调
            result.success(mapOf(
                "code" to "600000",
                "msg" to "环境检查已启动（请等待回调）"
            ))
        } catch (e: Exception) {
            Log.e(TAG, "Environment check failed", e)
            result.error("CHECK_FAILED", e.message, null)
        }
    }

    private fun oneClickLogin(timeout: Int, result: Result) {
        val helper = phoneNumberAuthHelper
        val act = activity

        if (helper == null) {
            result.error("NOT_INITIALIZED", "请先调用 initSdk", null)
            return
        }

        if (act == null) {
            result.error("NO_ACTIVITY", "Activity is not available", null)
            return
        }

        if (!isPreLoginSuccess) {
            Log.w(TAG, "Pre-login not completed, attempting anyway...")
            // 即使预取号未成功也尝试，但可能会失败
        }

        try {
            pendingResult = result

            // 获取屏幕密度
            val density = act.resources.displayMetrics.density
            val screenWidth = act.resources.displayMetrics.widthPixels
            val btnWidthDp = ((screenWidth / density) - 64).toInt()

            // 适配安全区，避免协议区域顶到状态栏
            val window = act.window
            val decorView = window.decorView
            if (previousDecorFitsSystemWindows == null) {
                previousDecorFitsSystemWindows = ViewCompat.getFitsSystemWindows(decorView)
            }
            WindowCompat.setDecorFitsSystemWindows(window, true)
            val statusBarPx = ViewCompat.getRootWindowInsets(decorView)
                ?.getInsets(WindowInsetsCompat.Type.statusBars())
                ?.top ?: 0
            val statusBarDp = (statusBarPx / density).toInt()

            val logoOffsetY = 100 + statusBarDp
            val sloganOffsetY = 210 + statusBarDp
            val numFieldOffsetY = 260 + statusBarDp
            val logBtnOffsetY = 340 + statusBarDp

            // 检测系统深色模式
            val isDarkMode = (act.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            Log.d(TAG, "Dark mode detected: $isDarkMode")

            // 根据深色/浅色模式设置颜色
            val backgroundColor = if (isDarkMode) Color.parseColor("#121212") else Color.WHITE
            val primaryTextColor = if (isDarkMode) Color.parseColor("#E0E0E0") else Color.parseColor("#1A1A1A")
            val secondaryTextColor = if (isDarkMode) Color.parseColor("#9E9E9E") else Color.parseColor("#999999")
            val privacyLinkColor = if (isDarkMode) Color.parseColor("#64B5F6") else Color.parseColor("#007AFF")
            val alertBgColor = if (isDarkMode) Color.parseColor("#1E1E1E") else Color.WHITE
            val alertContentColor = if (isDarkMode) Color.parseColor("#BDBDBD") else Color.parseColor("#666666")
            // 状态栏图标颜色：深色模式用浅色图标，浅色模式用深色图标
            val isLightStatusBar = !isDarkMode

            // 配置授权页 UI - 简洁全屏模式，适配深色/浅色主题
            helper.setAuthUIConfig(
                AuthUIConfig.Builder()
                    // ========== 状态栏 ==========
                    .setStatusBarColor(backgroundColor)
                    .setStatusBarHidden(false)  // 显式设置状态栏不隐藏
                    .setLightColor(isLightStatusBar)

                    // ========== 导航栏（简化） ==========
                    .setNavColor(backgroundColor)
                    .setNavText("")
                    .setNavReturnHidden(true)

                    // ========== Logo ==========
                    .setLogoHidden(false)
                    .setLogoImgDrawable(act.getDrawable(if (isDarkMode) R.drawable.auth_logo_dark else R.drawable.auth_logo))
                    .setLogoWidth(90)
                    .setLogoHeight(90)
                    .setLogoOffsetY(logoOffsetY)

                    // ========== Slogan ==========
                    .setSloganHidden(false)
                    .setSloganText("Psygo")
                    .setSloganTextColor(primaryTextColor)
                    .setSloganTextSize(20)
                    .setSloganOffsetY(sloganOffsetY)

                    // ========== 手机号 ==========
                    .setNumberColor(primaryTextColor)
                    .setNumberSize(28)
                    .setNumFieldOffsetY(numFieldOffsetY)

                    // ========== 登录按钮 ==========
                    .setLogBtnText("本机号码一键登录")
                    .setLogBtnTextColor(Color.WHITE)
                    .setLogBtnTextSize(17)
                    .setLogBtnWidth(btnWidthDp)
                    .setLogBtnHeight(50)
                    .setLogBtnOffsetY(logBtnOffsetY)
                    .setLogBtnBackgroundDrawable(act.getDrawable(R.drawable.auth_login_btn))

                    // ========== 其他登录方式（已隐藏，目前只支持一键登录） ==========
                    .setSwitchAccHidden(true)

                    // ========== 隐私协议 ==========
                    .setPrivacyState(false)  // 默认未勾选
                    .setCheckboxHidden(false)
                    .setCheckedImgDrawable(act.getDrawable(R.drawable.auth_checkbox_checked))
                    .setUncheckedImgDrawable(act.getDrawable(if (isDarkMode) R.drawable.auth_checkbox_unchecked_dark else R.drawable.auth_checkbox_unchecked))
                    .setPrivacyOffsetY_B(80)
                    .setPrivacyTextSize(12)
                    // 协议名称和链接（使用自定义 Scheme 跳转到 App 内页面，避免 SDK WebView 适配问题）
                    .setAppPrivacyOne("《用户协议》", "https://psygoai.com/legal/user-agreement.html")
                    .setAppPrivacyTwo("《隐私政策》", "https://psygoai.com/legal/privacy-policy.html")
                    .setAppPrivacyColor(secondaryTextColor, privacyLinkColor)
                    .setPrivacyBefore("登录即同意")
                    .setPrivacyEnd("")
                    .setVendorPrivacyPrefix("《")
                    .setVendorPrivacySuffix("》")
                    // 未勾选协议时，点击登录按钮弹出二次确认弹窗
                    .setLogBtnToastHidden(true)  // 隐藏 Toast，改用弹窗
                    .setPrivacyAlertIsNeedShow(true)  // 启用二次确认弹窗
                    .setPrivacyAlertIsNeedAutoLogin(true)  // 点击同意后自动登录
                    // 二次确认弹窗 UI 配置 - 紧凑简洁风格
                    .setPrivacyAlertTitleContent("温馨提示")
                    .setPrivacyAlertTitleTextSize(17)
                    .setPrivacyAlertTitleColor(primaryTextColor)
                    .setPrivacyAlertContentTextSize(14)
                    .setPrivacyAlertContentColor(alertContentColor)
                    .setPrivacyAlertContentBaseColor(alertContentColor)
                    .setPrivacyAlertContentHorizontalMargin(16)
                    .setPrivacyAlertContentVerticalMargin(10)
                    .setPrivacyAlertBtnContent("同意并登录")
                    .setPrivacyAlertBtnTextColor(Color.WHITE)
                    .setPrivacyAlertBtnTextSize(15)
                    .setPrivacyAlertBtnBackgroundImgDrawable(act.getDrawable(R.drawable.auth_login_btn))
                    .setPrivacyAlertCloseBtnShow(true)  // 显示关闭按钮
                    .setPrivacyAlertMaskIsNeedShow(true)  // 显示背景遮罩
                    .setPrivacyAlertMaskAlpha(if (isDarkMode) 0.5f else 0.3f)
                    .setPrivacyAlertCornerRadiusArray(intArrayOf(16, 16, 16, 16))
                    .setPrivacyAlertAlignment(1)  // 0-居左 1-居中 2-居右
                    .setPrivacyAlertWidth(280)  // 更紧凑的宽度
                    .setPrivacyAlertHeight(200)  // 更紧凑的高度
                    .setPrivacyAlertBtnWidth(240)
                    .setPrivacyAlertBtnHeigth(42)
                    .setPrivacyAlertBackgroundColor(alertBgColor)
                    // 协议页面（SDK 内置 WebView）
                    .setWebNavColor(backgroundColor)
                    .setWebNavTextColor(primaryTextColor)
                    .setWebNavTextSize(18)
                    .setWebNavReturnImgDrawable(act.getDrawable(if (isDarkMode) R.drawable.auth_close_dark else R.drawable.auth_close))
                    .setWebSupportedJavascript(true)
                    .setWebViewStatusBarColor(backgroundColor)
                    // 设置底部虚拟按键背景色
                    .setBottomNavColor(backgroundColor)

                    // ========== 页面背景 ==========
                    .setPageBackgroundDrawable(ColorDrawable(backgroundColor))

                    .create()
            )

            // 控制返回键和左上角返回按钮
            helper.userControlAuthPageCancel()
            // 禁用横屏水滴屏全屏适配，避免内容进入状态栏
            // helper.keepAuthPageLandscapeFullSreen(true)
            // 不隐藏底部导航栏，而是设置为白色（已在 UI 配置中设置）
            // helper.keepAllPageHideNavigationBar()
            // 扩大协议按钮选择范围
            helper.expandAuthPageCheckedScope(true)

            Log.d(TAG, "Starting getLoginToken with timeout: $timeout, preLoginSuccess: $isPreLoginSuccess")
            helper.getLoginToken(act, timeout)
        } catch (e: Exception) {
            Log.e(TAG, "One-click login failed", e)
            pendingResult?.error("LOGIN_FAILED", e.message, null)
            pendingResult = null
        }
    }

    private fun handleTokenResult(response: String, isSuccess: Boolean) {
        val result = pendingResult ?: run {
            Log.w(TAG, "No pending result for token callback, ignoring")
            return
        }
        pendingResult = null

        try {
            val tokenRet = TokenRet.fromJson(response)
            val code = tokenRet.code
            val msg = tokenRet.msg

            Log.d(TAG, "Token result - code: $code, msg: $msg, success: $isSuccess")

            when {
                ResultCode.CODE_SUCCESS == code -> {
                    // 获取 token 成功
                    // 注意：不在这里关闭授权页，让 Flutter 端完成后续操作后再调用 quitLoginPage()
                    // 这样用户会在授权页上看到 loading，而不是跳到另一个页面显示 loading
                    val token = tokenRet.token
                    Log.d(TAG, "Got token: ${token?.take(20)}...")
                    activity?.runOnUiThread {
                        result.success(mapOf(
                            "code" to code,
                            "msg" to msg,
                            "token" to token
                        ))
                    }
                    // 不调用 quitLoginPage()，由 Flutter 端手动调用
                }
                ResultCode.CODE_START_AUTHPAGE_SUCCESS == code -> {
                    // 授权页唤起成功，继续等待用户操作
                    Log.d(TAG, "Auth page launched successfully, waiting for user action...")
                    // 恢复 pendingResult，继续等待用户点击登录
                    pendingResult = result
                }
                ResultCode.CODE_ERROR_USER_CANCEL == code -> {
                    // 用户取消
                    activity?.runOnUiThread {
                        result.error("USER_CANCEL", msg ?: "用户取消登录", null)
                    }
                    phoneNumberAuthHelper?.quitLoginPage()
                }
                else -> {
                    // 其他错误
                    activity?.runOnUiThread {
                        result.error(code ?: "UNKNOWN_ERROR", msg ?: "未知错误", null)
                    }
                    phoneNumberAuthHelper?.quitLoginPage()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse token result", e)
            activity?.runOnUiThread {
                result.error("PARSE_ERROR", e.message, null)
            }
        }
    }

    private fun quitLoginPage(result: Result) {
        try {
            phoneNumberAuthHelper?.quitLoginPage()
            val act = activity
            val fitsSystemWindows = previousDecorFitsSystemWindows
            if (act != null && fitsSystemWindows != null) {
                WindowCompat.setDecorFitsSystemWindows(act.window, fitsSystemWindows)
                previousDecorFitsSystemWindows = null
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("QUIT_FAILED", e.message, null)
        }
    }
}
