package com.creativekoalas.psygo

import android.app.Activity
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsetsController
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

/**
 * 协议页面 Activity
 * 使用原生 WebView 显示协议内容，正确处理状态栏适配
 * 解决阿里云 SDK 内置 WebView 状态栏适配问题
 */
class ProtocolActivity : Activity() {
    companion object {
        private const val TAG = "ProtocolActivity"
    }

    private lateinit var webView: WebView
    private lateinit var progressBar: ProgressBar
    private lateinit var titleText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.d(TAG, "ProtocolActivity started")
        Log.d(TAG, "Intent action: ${intent?.action}")
        Log.d(TAG, "Intent data: ${intent?.data}")
        Log.d(TAG, "Intent extras: ${intent?.extras}")

        val url = intent?.data?.toString() ?: run {
            Log.e(TAG, "No URL provided")
            finish()
            return
        }
        Log.d(TAG, "Protocol URL: $url")

        // 检测深色模式
        val isDarkMode = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val backgroundColor = if (isDarkMode) Color.parseColor("#121212") else Color.WHITE
        val textColor = if (isDarkMode) Color.parseColor("#E0E0E0") else Color.parseColor("#1A1A1A")
        val dividerColor = if (isDarkMode) Color.parseColor("#2C2C2C") else Color.parseColor("#E0E0E0")

        // 设置状态栏颜色
        window.statusBarColor = backgroundColor
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.setSystemBarsAppearance(
                if (isDarkMode) 0 else WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS,
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
            )
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (isDarkMode) 0 else View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }

        // 让内容延伸到状态栏下方，然后手动处理 padding
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // 创建根布局
        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(backgroundColor)
            fitsSystemWindows = false
        }

        // 处理状态栏高度
        ViewCompat.setOnApplyWindowInsetsListener(rootLayout) { view, windowInsets ->
            val insets = windowInsets.getInsets(WindowInsetsCompat.Type.statusBars())
            view.setPadding(0, insets.top, 0, 0)
            windowInsets
        }

        // 导航栏
        val navBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(backgroundColor)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dpToPx(56)
            )
            setPadding(dpToPx(4), 0, dpToPx(16), 0)
            gravity = android.view.Gravity.CENTER_VERTICAL
        }

        // 返回按钮
        val backButton = ImageButton(this).apply {
            setImageResource(if (isDarkMode) R.drawable.auth_close_dark else R.drawable.auth_close)
            setBackgroundColor(Color.TRANSPARENT)
            layoutParams = LinearLayout.LayoutParams(dpToPx(48), dpToPx(48))
            setOnClickListener { finish() }
            contentDescription = "返回"
        }

        // 标题
        titleText = TextView(this).apply {
            text = "加载中..."
            setTextColor(textColor)
            textSize = 18f
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dpToPx(8)
            }
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }

        navBar.addView(backButton)
        navBar.addView(titleText)

        // 分割线
        val divider = View(this).apply {
            setBackgroundColor(dividerColor)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dpToPx(1)
            )
        }

        // 进度条
        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dpToPx(3)
            )
            isIndeterminate = false
            max = 100
            progress = 0
        }

        // WebView 容器
        val webViewContainer = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
            setBackgroundColor(backgroundColor)
        }

        // WebView
        webView = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(backgroundColor)

            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                useWideViewPort = true
                loadWithOverviewMode = true
            }

            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    progressBar.visibility = View.GONE
                }
            }

            webChromeClient = object : WebChromeClient() {
                override fun onProgressChanged(view: WebView?, newProgress: Int) {
                    progressBar.progress = newProgress
                    if (newProgress < 100) {
                        progressBar.visibility = View.VISIBLE
                    }
                }

                override fun onReceivedTitle(view: WebView?, title: String?) {
                    titleText.text = title ?: "协议"
                }
            }
        }

        webViewContainer.addView(webView)

        // 组装布局
        rootLayout.addView(navBar)
        rootLayout.addView(divider)
        rootLayout.addView(progressBar)
        rootLayout.addView(webViewContainer)

        setContentView(rootLayout)

        // 加载 URL
        webView.loadUrl(url)
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.destroy()
        }
        super.onDestroy()
    }
}
