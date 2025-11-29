package com.creativekoalas.automate

import android.app.Activity
import android.content.Context
import android.util.Log
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
import android.util.TypedValue

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
        private const val CHANNEL = "com.creativekoalas.automate/one_click_login"
    }

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var phoneNumberAuthHelper: PhoneNumberAuthHelper? = null
    private var pendingResult: Result? = null
    private var isPreLoginSuccess: Boolean = false  // 预取号是否成功

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

            // 配置授权页 UI - 简洁全屏模式
            helper.setAuthUIConfig(
                AuthUIConfig.Builder()
                    // ========== 状态栏 ==========
                    .setStatusBarColor(Color.WHITE)
                    .setLightColor(true)

                    // ========== 导航栏（简化） ==========
                    .setNavColor(Color.WHITE)
                    .setNavText("")
                    .setNavReturnHidden(false)

                    // ========== Logo ==========
                    .setLogoHidden(false)
                    .setLogoImgDrawable(act.getDrawable(R.drawable.auth_logo))
                    .setLogoWidth(90)
                    .setLogoHeight(90)
                    .setLogoOffsetY(100)

                    // ========== Slogan ==========
                    .setSloganHidden(false)
                    .setSloganText("AutoMate")
                    .setSloganTextColor(Color.parseColor("#1A1A1A"))
                    .setSloganTextSize(20)
                    .setSloganOffsetY(210)

                    // ========== 手机号 ==========
                    .setNumberColor(Color.parseColor("#1A1A1A"))
                    .setNumberSize(28)
                    .setNumFieldOffsetY(260)

                    // ========== 登录按钮 ==========
                    .setLogBtnText("本机号码一键登录")
                    .setLogBtnTextColor(Color.WHITE)
                    .setLogBtnTextSize(17)
                    .setLogBtnWidth(btnWidthDp)
                    .setLogBtnHeight(50)
                    .setLogBtnOffsetY(340)
                    .setLogBtnBackgroundDrawable(act.getDrawable(R.drawable.auth_login_btn))

                    // ========== 其他登录方式 ==========
                    .setSwitchAccText("其他方式登录")
                    .setSwitchAccTextColor(Color.parseColor("#007AFF"))
                    .setSwitchAccTextSize(15)
                    .setSwitchOffsetY(410)
                    .setSwitchAccHidden(false)

                    // ========== 隐私协议 ==========
                    .setPrivacyState(false)
                    .setCheckboxHidden(false)
                    .setCheckedImgDrawable(act.getDrawable(R.drawable.auth_checkbox_checked))
                    .setUncheckedImgDrawable(act.getDrawable(R.drawable.auth_checkbox_unchecked))
                    .setPrivacyOffsetY_B(80)
                    .setPrivacyTextSize(12)
                    .setAppPrivacyOne("《用户协议》", "https://automate.creativekoalas.com/agreement")
                    .setAppPrivacyTwo("《隐私政策》", "https://automate.creativekoalas.com/privacy")
                    .setAppPrivacyColor(Color.parseColor("#999999"), Color.parseColor("#007AFF"))
                    .setPrivacyBefore("登录即同意")
                    .setPrivacyEnd("")
                    .setVendorPrivacyPrefix("《")
                    .setVendorPrivacySuffix("》")

                    // ========== 页面背景 ==========
                    .setPageBackgroundDrawable(act.getDrawable(android.R.color.white))

                    .create()
            )

            // 控制返回键和左上角返回按钮
            helper.userControlAuthPageCancel()
            // 横屏水滴屏全屏适配
            helper.keepAuthPageLandscapeFullSreen(true)
            // 隐藏底部导航栏
            helper.keepAllPageHideNavigationBar()
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
                    val token = tokenRet.token
                    Log.d(TAG, "Got token: ${token?.take(20)}...")
                    activity?.runOnUiThread {
                        result.success(mapOf(
                            "code" to code,
                            "msg" to msg,
                            "token" to token
                        ))
                    }
                    // 关闭授权页
                    phoneNumberAuthHelper?.quitLoginPage()
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
            result.success(true)
        } catch (e: Exception) {
            result.error("QUIT_FAILED", e.message, null)
        }
    }
}
