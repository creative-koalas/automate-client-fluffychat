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
│                           消息推送流程                                       │
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
│         │                   │                           │     API 发送通知   │
│         │                   │                           │                   │
│  ┌──────────────┐           │                           │                   │
│  │  阿里云推送  │<────────── 11. 推送到设备 ─────────────│                   │
│  │   服务器     │           │                           │                   │
│  └──────┬───────┘           │                           │                   │
│         │                   │                           │                   │
│         │ 12. 通过厂商通道  │                           │                   │
│         │     推送到设备    │                           │                   │
│         v                   │                           │                   │
│  ┌──────────────┐           │                           │                   │
│  │ Android/iOS  │           │                           │                   │
│  │   显示通知   │           │                           │                   │
│  └──────────────┘           │                           │                   │
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
| `matrix` SDK | Matrix 协议客户端，用于注册 pusher |

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
   ├─ 调用阿里云 SDK initPush()
   ├─ 设置消息回调 addMessageReceiver()
   └─ 获取 deviceId = getDeviceId()
3. 如果用户已登录，执行阶段二
```

### 阶段二：注册推送（用户登录后）

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

### 阶段三：消息推送

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
   └─ 调用阿里云推送 API
5. 阿里云推送服务器
   ├─ 通过 device_id 定位设备
   └─ 通过厂商通道推送通知
6. 设备显示通知
```

## 关键设计决策

### 1. pushkey 设计

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

### 2. 旧 Pusher 清理机制

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

### 3. NotificationChannel 配置

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

### 4. Synapse IP 白名单

**问题**：Synapse 默认阻止对内网 IP 的 HTTP 请求（SSRF 防护）

**解决方案**：在 homeserver.yaml 添加白名单

```yaml
ip_range_whitelist:
  - "10.0.0.0/8"
  - "192.168.0.0/16"
  - "172.16.0.0/12"
```

### 5. 禁用 FluffyChat 原有推送

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
