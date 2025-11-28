-keep class net.sqlcipher.** { *; }

# ali_auth SDK
-dontwarn javax.xml.stream.XMLStreamException

# ==========================================
# 阿里云一键登录 SDK 官方 ProGuard 配置
# 来源: SDK Demo/app/proguard-rules.pro
# ==========================================
-keepattributes Exceptions,InnerClasses,Signature,Deprecated,*Annotation*,EnclosingMethod
-keep class android.app.ActivityThread {*;}
-keep class android.os.SystemProperties {*;}

# 保护 AppCompatActivity（SDK 的 LoginAuthActivity 继承自它）
# 来源: https://help.aliyun.com/zh/pnvs/developer-reference/the-android-client-access
-keep class androidx.appcompat.app.AppCompatActivity { *; }
-keep class androidx.core.content.ContextCompat { *; }

# 保护 SDK 所有类
-keep class com.mobile.auth.gatewayauth.** { *; }
-keep class com.nirvana.** { *; }
-keep class com.cmic.** { *; }
-keep class cn.com.chinatelecom.** { *; }
-keep class com.unicom.** { *; }

# 保护 JSON 类（防止 NoSuchMethodError）
-keep class org.json.** { *; }

# 禁止警告
-dontwarn com.mobile.auth.gatewayauth.**
-dontwarn com.nirvana.**
-dontwarn com.cmic.**
-dontwarn cn.com.chinatelecom.**
-dontwarn com.unicom.**
