# Automate 移动推送架构设计

本文档描述 Automate 客户端的移动推送完整架构，包括阿里云移动推送 SDK 集成、Matrix Push Gateway 协议实现、以及与 Synapse 的交互流程。

## 架构概述

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              完整推送链路                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────────┐  │
│  │ Android/iOS  │    │   Synapse    │    │    automate-assistant        │  │
│  │   客户端     │    │  (Matrix)    │    │     (Push Gateway)           │  │
│  └──────┬───────┘    └──────┬───────┘    └──────────────┬───────────────┘  │
│         │                   │                           │                   │
│         │ 1. 初始化阿里云SDK │                           │                   │
│         │ 2. 获取 deviceId   │                           │                   │
│         │                   │                           │                   │
│         │ 3. POST /api/push/register ──────────────────>│                   │
│         │    {matrix_user_id, device_id, push_key}      │                   │
│         │                   │                           │                   │
│         │<─────────── 4. 返回成功 ──────────────────────│                   │
│         │                   │                           │                   │
│         │ 5. POST /_matrix/client/v3/pushers/set ──────>│                   │
│         │    {pushkey, app_id, url=Push Gateway}        │                   │
│         │                   │                           │                   │
│         │<─────────── 6. 注册 pusher 成功 ──────────────│                   │
│         │                   │                           │                   │
│         │                   │                           │                   │
│  ═══════════════════════════════════════════════════════════════════════   │
│                   消息推送流程（透传消息模式）                                │
│  ═══════════════════════════════════════════════════════════════════════   │
│         │                   │                           │                   │
│         │                   │ 7. 房间收到新消息         │                   │
│         │                   │    查找该用户的 pushers   │                   │
│         │                   │                           │                   │
│         │                   │ 8. POST /_matrix/push/v1/notify ────────────>│  │
│         │                   │    {notification: {devices: [{pushkey}]}}    │  │
│         │                   │                           │                   │
│         │                   │                           │ 9. 查询 push_devices│
│         │                   │                           │    通过 pushkey    │
│         │                   │                           │    获取 device_id  │
│         │                   │                           │                   │
│         │                   │                           │ 10. 调用阿里云推送 │
│         │                   │                           │     发送透传消息   │
│         │                   │                           │     (PushType=MESSAGE)│
│         │                   │                           │                   │
│  ┌──────────────┐           │                           │                   │
│  │  阿里云推送  │<────────── 11. 推送透传消息 ───────────│                   │
│  │   服务器     │           │                           │                   │
│  └──────┬───────┘           │                           │                   │
│         │                   │                           │                   │
│         │ 12. 通过厂商通道  │                           │                   │
│         │     推送到设备    │                           │                   │
│         v                   │                           │                   │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ Android/iOS 客户端                                                    │  │
│  │  ┌─────────────────────┐                                              │  │
│  │  │ AliyunPushService   │  13. onMessage 回调接收透传消息              │  │
│  │  │ _handleMessage()    │      解析 JSON payload                       │  │
│  │  └──────────┬──────────┘                                              │  │
│  │             │                                                          │  │
│  │             ├─ 14. 检查 activeRoomId == room_id ?                      │  │
│  │             │   ├─ 是：用户在当前房间，跳过通知                        │  │
│  │             │   └─ 否：用户不在当前房间，显示本地通知                  │  │
│  │             │                                                          │  │
│  │  ┌──────────v──────────┐                                              │  │
│  │  │ flutter_local_      │  15. 显示本地通知                            │  │
│  │  │ notifications       │      点击通知 → onNotificationTapped         │  │
│  │  └─────────────────────┘      → 导航到对应房间                        │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 组件说明

### 1. 客户端 (Flutter)

**文件位置**: `lib/utils/aliyun_push_service.dart`

| 组件 | 说明 |
|------|------|
| `AliyunPushService` | 阿里云推送 SDK 封装，单例模式 |
| `aliyun_push` 插件 | Flutter 阿里云推送插件 |
| `flutter_local_notifications` | 本地通知插件，用于显示透传消息 |
| `matrix` SDK | Matrix 协议客户端，用于注册 pusher |

**回调函数**:
| 回调 | 说明 |
|------|------|
| `activeRoomIdGetter` | 获取当前活跃房间 ID，用于过滤当前房间的通知 |
| `onNotificationTapped` | 通知点击回调，用于导航到对应房间 |

**关键配置**:
```dart
// 阿里云推送 App Key/Secret
static const _androidAppKey = '335631945';
static const _androidAppSecret = '5972362998844c5c8cdb8b0d38e16969';
static const _iosAppKey = '335631946';
static const _iosAppSecret = '91669fd16fb6431a87d70314226a62b6';

// App ID（用于区分平台）
static const String _androidAppId = 'com.creativekoalas.automate.android';
static const String _iosAppId = 'com.creativekoalas.automate.ios';
```

### 2. Android 原生层

**文件位置**: `android/app/src/main/kotlin/com/creativekoalas/automate/MainActivity.kt`

**关键配置** - NotificationChannel（Android 8.0+ 必须）:
```kotlin
private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val channelId = "automate_push_channel"  // 必须与服务端一致
        val channelName = "消息通知"
        val importance = NotificationManager.IMPORTANCE_HIGH

        val channel = NotificationChannel(channelId, channelName, importance).apply {
            enableLights(true)
            enableVibration(true)
            setShowBadge(true)
        }

        notificationManager.createNotificationChannel(channel)
    }
}
```

### 3. Push Gateway (Go)

**文件位置**: `automate-assistant/api/push_gateway.go`

| 端点 | 说明 |
|------|------|
| `POST /api/push/register` | 客户端注册推送设备 |
| `DELETE /api/push/unregister` | 客户端注销推送设备 |
| `GET /api/push/status` | 查询推送设备状态 |
| `POST /_matrix/push/v1/notify` | Matrix Push Gateway 协议端点（Synapse 调用） |

### 4. 阿里云推送服务 (Go)

**文件位置**: `automate-assistant/service/aliyun/push.go`

```go
type PushNotification struct {
    DeviceID      string // 阿里云设备 ID
    Title         string // 通知标题
    Body          string // 通知内容
    Platform      string // 平台：android / ios
    ExtParameters string // 扩展参数（JSON，点击通知后传递给 App）
    Badge         int    // iOS 角标数量
}
```

### 5. Synapse (Matrix Server)

**配置文件**: `k8s/matrix-synapse-deployment.yaml` 中的 ConfigMap

**关键配置** - IP 白名单（允许访问内网 Push Gateway）:
```yaml
ip_range_whitelist:
  - "10.0.0.0/8"      # K8s Pod/Service 网段
  - "192.168.0.0/16"  # 私有网段
  - "172.16.0.0/12"   # Docker 默认网段
```

> **重要**: 不加这个配置，Synapse 会阻止对内网 IP 的 HTTP 请求（SSRF 防护），导致无法调用 Push Gateway。

## 数据库表

### push_devices 表 (automate-assistant MySQL)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | bigint | 主键 |
| user_id | bigint | 关联 users 表 |
| matrix_user_id | varchar | Matrix 用户 ID（如 @user:localhost） |
| device_id | varchar | 阿里云设备 ID（UTDID） |
| push_key | varchar | 唯一推送标识（格式：{platform}_{device_id}） |
| app_id | varchar | 应用 ID（区分 Android/iOS） |
| platform | varchar | 平台（android/ios） |
| device_name | varchar | 设备名称 |
| is_active | boolean | 是否激活 |
| created_at | timestamp | 创建时间 |
| updated_at | timestamp | 更新时间 |

### Synapse pushers 表 (PostgreSQL)

| 字段 | 说明 |
|------|------|
| user_name | Matrix 用户 ID |
| app_id | 应用 ID |
| pushkey | 推送标识（与 push_devices.push_key 对应） |
| data | JSON 数据（包含 Push Gateway URL） |

## 完整流程

### 阶段一：初始化（App 启动时）

```
1. App 启动
2. AliyunPushService.initialize()
   ├─ 初始化本地通知插件 flutter_local_notifications
   ├─ 设置回调 activeRoomIdGetter / onNotificationTapped
   ├─ 调用阿里云 SDK initPush()
   ├─ 设置消息回调 addMessageReceiver()
   └─ 获取 deviceId = getDeviceId()
3. 如果用户已登录，执行阶段二
```

### 阶段二：权限请求（用户登录后）

```
1. 用户登录成功，触发 _requestPermissionsAndRegisterPush()
2. 延迟 500ms 等待 UI 稳定
3. 请求通知权限 PermissionService.requestNotificationPermission()
   ├─ 检查当前状态
   ├─ 如果已授权 → 跳过
   ├─ 如果永久拒绝 → 显示"去设置"对话框
   └─ 否则：
       ├─ 显示预授权对话框（解释为什么需要）
       ├─ 用户同意 → 调用系统权限弹窗
       └─ 用户拒绝 → 跳过
4. [Android] 请求电池优化白名单 Permission.ignoreBatteryOptimizations
   ├─ 显示预授权对话框
   └─ 调用系统设置
5. 执行阶段三：注册推送
```

### 阶段三：注册推送

```
1. _registerAliyunPushAfterLogin(client)
2. 绑定阿里云账号 bindAccount(userID)
3. 生成 pushKey = "{platform}_{deviceId}"
4. 注册到后端 registerPusherToBackend()
   ├─ POST /api/push/register
   │   {matrix_user_id, device_id, push_key, app_id, platform}
   ├─ 后端清理该用户的旧 pusher（软删除）
   └─ 创建新的 push_devices 记录
5. 注册到 Synapse registerPusherToSynapse()
   ├─ 获取当前所有 pusher: getPushers()
   ├─ 删除同 app_id 的旧 pusher: deletePusher()
   └─ 注册新 pusher: postPusher()
       {pushkey, app_id, url=Push Gateway URL}
```

### 阶段三：消息推送（透传消息模式）

```
1. 房间收到新消息
2. Synapse 查找该用户的 pushers
3. Synapse 调用 Push Gateway
   POST /_matrix/push/v1/notify
   {
     notification: {
       room_id, sender, content,
       devices: [{app_id, pushkey}]
     }
   }
4. Push Gateway 处理
   ├─ 通过 pushkey 查询 push_devices 表
   ├─ 获取 device_id
   └─ 构建透传消息 JSON:
       {
         "type": "matrix_message",
         "title": "发送者名称",
         "body": "消息内容",
         "room_id": "!roomid:server",
         "event_id": "$eventid",
         "sender": "@user:server",
         "badge": 5
       }
   └─ 调用阿里云推送 API (PushType=MESSAGE)
5. 阿里云推送服务器
   ├─ 通过 device_id 定位设备
   └─ 通过厂商通道推送透传消息
6. 客户端 AliyunPushService._handleMessage()
   ├─ 解析 JSON payload
   ├─ 检查 activeRoomId == room_id ?
   │   ├─ 是：用户在当前房间，跳过通知
   │   └─ 否：用户不在当前房间
   ├─ 调用 flutter_local_notifications 显示本地通知
   └─ 更新角标
7. 用户点击通知
   ├─ _onNotificationTapped() 回调
   └─ 导航到对应房间
```

## 关键设计决策

### 1. 透传消息设计（MESSAGE vs NOTICE）

**问题**：阿里云推送有两种推送类型
- `NOTICE`：通知消息，阿里云 SDK 直接显示系统通知，App 无法干预
- `MESSAGE`：透传消息，消息到达 App 代码，由 App 决定是否显示通知

**选择 MESSAGE 的原因**：
1. **智能过滤**：用户在当前聊天室时不显示通知（避免打扰）
2. **可定制**：App 可以自定义通知样式、声音、振动等
3. **可拦截**：App 在前台时可以选择不显示通知
4. **数据传递**：可以传递 room_id、event_id 等结构化数据

**实现方式**：
```go
// push_gateway.go - 构建透传消息
messagePayload := map[string]interface{}{
    "type":     "matrix_message",
    "title":    title,
    "body":     body,
    "room_id":  req.Notification.RoomID,
    "event_id": req.Notification.EventID,
    "sender":   req.Notification.Sender,
    "badge":    req.Notification.Counts.Unread,
}
api.pushService.SendMessage(deviceID, messageJSON, platform)
```

```dart
// aliyun_push_service.dart - 处理透传消息
void _handleMessage(Map<dynamic, dynamic> message) {
    // 解析 JSON payload
    final payload = jsonDecode(content);
    final roomId = payload['room_id'];

    // 检查用户是否在当前房间
    if (activeRoomIdGetter?.call() == roomId) {
        return; // 跳过通知
    }

    // 显示本地通知
    _showLocalNotification(title, body, payload);
}
```

**注意**：透传消息需要 `flutter_local_notifications` 插件来显示本地通知

### 2. 权限请求设计（业界最佳实践）

**核心原则**：
1. **延迟请求**：不在启动时请求，而在登录成功后请求
2. **预授权对话框**：系统弹窗前先用自定义 UI 解释原因（提高通过率 40%+）
3. **优雅降级**：拒绝后提供"去设置"入口

**权限类型**：
| 权限 | Android | iOS | 用途 |
|------|---------|-----|------|
| 通知权限 | 13+ 需要 | 需要 | 显示推送通知 |
| 电池优化白名单 | 需要 | 不需要 | 后台保活 |

**实现**：
```dart
// lib/utils/permission_service.dart
class PermissionService {
  Future<void> requestPushPermissions(BuildContext context) async {
    // 1. 通知权限
    await requestNotificationPermission(context);
    // 2. 电池优化白名单（Android）
    if (Platform.isAndroid) {
      await requestBatteryOptimization(context);
    }
  }
}
```

**预授权对话框流程**：
```
用户登录成功
    ↓
显示预授权对话框："开启消息通知，不错过重要信息"
    ↓
用户点击"好的" → 系统权限弹窗
用户点击"稍后再说" → 跳过，不影响使用
```

### 3. pushkey 设计

```
格式：{platform}_{deviceId}
示例：android_41fe111ea7f044768b90d4194b690c52
```

**设计原则**:
- 同一设备的 pushkey 保持不变
- 避免每次启动生成新 pushkey 导致重复注册
- 平台前缀便于后端区分 Android/iOS

**陷阱**:
- Debug 模式下 `flutter run` 会重新安装 App，导致 device_id 变化
- 解决方案：在注册时清理旧的 pusher

### 4. 旧 Pusher 清理机制

**问题**：device_id 变化 → 新 pushkey → Synapse 累积多个 pusher → 重复推送

**解决方案**：

1. **后端清理**（push_gateway.go）:
   ```go
   // 注册新 pusher 前，先清理该用户的所有旧 pusher
   global.DB.Model(&models.PushDevice{}).
       Where("matrix_user_id = ? AND is_active = ?", req.MatrixUserID, true).
       Update("is_active", false)
   ```

2. **客户端清理**（aliyun_push_service.dart）:
   ```dart
   // 删除同 app_id 的旧 pusher
   for (final pusher in existingPushers ?? []) {
       if (pusher.appId == _appId && pusher.pushkey != pushKey) {
           await client.deletePusher(pusher);
       }
   }
   ```

### 5. NotificationChannel 配置

**问题**：Android 8.0+ 必须创建 NotificationChannel 才能显示通知

**解决方案**：
- 客户端创建 channel: `automate_push_channel`
- 服务端推送时指定相同 channel ID

```go
// push.go
request.AndroidNotificationChannel = "automate_push_channel"
```

```kotlin
// MainActivity.kt
val channelId = "automate_push_channel"
```

### 6. Synapse IP 白名单

**问题**：Synapse 默认阻止对内网 IP 的 HTTP 请求（SSRF 防护）

**解决方案**：在 homeserver.yaml 添加白名单

```yaml
ip_range_whitelist:
  - "10.0.0.0/8"
  - "192.168.0.0/16"
  - "172.16.0.0/12"
```

### 7. 禁用 FluffyChat 原有推送

**问题**：FluffyChat 原有 BackgroundPush（Firebase/UnifiedPush）与阿里云推送冲突

**解决方案**：注释掉 BackgroundPush 初始化

```dart
// matrix.dart - 已注释
// backgroundPush = BackgroundPush(this, ...);

// main.dart - 已注释
// BackgroundPush.clientOnly(clients.first);
```

## 配置清单

### 阿里云控制台

| 配置项 | Android | iOS |
|--------|---------|-----|
| App Key | 335631945 | 335631946 |
| App Secret | 5972362998844c5c8cdb8b0d38e16969 | 91669fd16fb6431a87d70314226a62b6 |
| 包名 | com.creativekoalas.automate | com.creativekoalas.automate |

### automate-assistant 环境变量

```bash
# 阿里云推送配置
ALIYUN_ACCESS_KEY_ID=xxx
ALIYUN_ACCESS_KEY_SECRET=xxx
ALIYUN_REGION_ID=cn-hangzhou
ALIYUN_PUSH_ANDROID_APP_KEY=335631945
ALIYUN_PUSH_IOS_APP_KEY=335631946
```

### K8s ConfigMap (synapse-config)

```yaml
# 关键配置
ip_range_whitelist:
  - "10.0.0.0/8"
  - "192.168.0.0/16"
  - "172.16.0.0/12"
```

## 故障排查

### 1. 推送未到达设备

**检查点**:
1. 阿里云控制台 → 推送记录 → 查看状态
2. 检查 device_id 是否正确
3. 检查 NotificationChannel 是否创建

### 2. 重复推送

**检查点**:
1. 查询 Synapse pushers 表，检查是否有多个 pusher
   ```sql
   SELECT * FROM pushers WHERE user_name = '@user:localhost';
   ```
2. 查询 push_devices 表，检查是否有多个 is_active=true 的记录
3. 清理旧数据后重新注册

### 3. Synapse 无法调用 Push Gateway

**检查点**:
1. 确认 `ip_range_whitelist` 已配置
2. 检查网络连通性
   ```bash
   kubectl exec -it <synapse-pod> -- curl http://automate-assistant:8080/health
   ```

### 4. 日志 `[Push] cannot get token - PushToken is null`

**原因**：FluffyChat 原有 BackgroundPush 未完全禁用

**解决**：确认以下代码已注释
- `matrix.dart`: `backgroundPush = BackgroundPush(...)`
- `main.dart`: `BackgroundPush.clientOnly(clients.first)`

## 迁移注意事项

迁移到新机器时，确保以下配置已包含：

1. **K8s ConfigMap** - Synapse IP 白名单
   ```bash
   kubectl apply -f k8s/matrix-synapse-deployment.yaml
   ```

2. **阿里云配置** - 环境变量或 Secrets
   ```bash
   kubectl apply -f k8s/secrets.yaml
   ```

3. **数据库** - push_devices 表数据迁移

## 版本历史

| 日期 | 变更 |
|------|------|
| 2025-11-30 | 初始化阿里云推送集成 |
| 2025-11-30 | 修复 NotificationChannel 配置 |
| 2025-11-30 | 修复重复推送问题（清理旧 pusher） |
| 2025-11-30 | 禁用 FluffyChat 原有 BackgroundPush |
| 2025-11-30 | 添加 Synapse IP 白名单配置 |
| 2025-12-01 | 改用透传消息（MESSAGE）模式 |
| 2025-12-01 | 添加智能通知过滤（用户在当前房间时不显示） |
| 2025-12-01 | 集成 flutter_local_notifications 显示本地通知 |
| 2025-12-01 | 实现通知点击导航到对应房间 |
| 2025-12-01 | 添加 PermissionService 统一管理权限请求 |
| 2025-12-01 | 实现预授权对话框（提高权限通过率） |
| 2025-12-01 | 支持电池优化白名单请求（Android 后台保活） |
