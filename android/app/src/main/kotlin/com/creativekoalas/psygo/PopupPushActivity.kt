package com.creativekoalas.psygo

import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.alibaba.sdk.android.push.AndroidPopupActivity

/**
 * 厂商通道辅助弹窗 Activity
 *
 * 当 App 被杀死后，通过 vivo/华为/小米等厂商通道推送的通知，
 * 点击后会打开这个 Activity，然后跳转到 MainActivity 并传递推送参数。
 */
class PopupPushActivity : AndroidPopupActivity() {

    private val TAG = "PopupPushActivity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate called")
    }

    /**
     * 厂商通道通知被点击时的回调
     *
     * @param title 通知标题
     * @param summary 通知内容
     * @param extMap 扩展参数（包含 room_id, event_id 等）
     */
    override fun onSysNoticeOpened(title: String?, summary: String?, extMap: MutableMap<String, String>?) {
        Log.d(TAG, "onSysNoticeOpened: title=$title, summary=$summary, extMap=$extMap")

        // 启动 MainActivity 并传递推送参数
        val intent = Intent(this, MainActivity::class.java).apply {
            // 设置 flags 确保正确的启动行为
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

            // 传递推送参数
            putExtra("push_title", title)
            putExtra("push_body", summary)

            // 传递扩展参数
            extMap?.let { map ->
                putExtra("room_id", map["room_id"])
                putExtra("event_id", map["event_id"])
                putExtra("type", map["type"])
            }
        }

        startActivity(intent)
        finish()
    }

    /**
     * 没有获取到推送数据的回调
     */
    override fun onNotPushData(intent: Intent?) {
        Log.w(TAG, "onNotPushData: No push data received")

        // 仍然启动 MainActivity
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(mainIntent)
        finish()
    }

    /**
     * 解析推送数据失败的回调
     */
    override fun onParseFailed(intent: Intent?) {
        Log.e(TAG, "onParseFailed: Failed to parse push data")

        // 仍然启动 MainActivity
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(mainIntent)
        finish()
    }
}
