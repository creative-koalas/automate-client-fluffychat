# FluffyChat Automate 功能迁移计划

**目标**: 从 Element X Android 迁移到 FluffyChat，实现跨平台支持（Android/iOS/Web/Desktop）

**技术栈**: Flutter 3.x + Dart 3.x + Material 3 + go_router + Provider

**设计理念**: 用户体验优先，细节至上，打造精品级 UI

**原则**:
1. ✅ 一次性到位，不做过度兼容
2. ✅ 遵循 FluffyChat 现有架构和主题样式
3. ✅ 使用业界标准方案（Provider 状态管理、go_router 路由）
4. ✅ UI 打磨到位，动效流畅，交互自然
5. ❌ 不堆屎山（代码清晰、职责分离）

---

## 📊 迁移进度跟踪

| Phase | 任务 | 状态 | 完成时间 |
|-------|------|------|---------|
| Phase 1 | 基础架构层 | ✅ 完成 | 2024-11-20 |
| Phase 2 | Repository 层 | 🔲 进行中 | - |
| Phase 3 | 状态管理层 | 🔲 | - |
| Phase 4 | UI 层 | 🔲 | - |
| Phase 5 | 多语言支持 | 🔲 | - |
| Phase 6 | Matrix 集成 | 🔲 | - |
| Phase 7 | 路由配置 | 🔲 | - |
| Phase 8 | 配置和部署 | 🔲 | - |

---

## ✅ Phase 1: 基础架构层（已完成）

### 1.1 JWT Token 管理器
**文件**: `lib/automate/core/token_manager.dart` ✅
- [x] 使用 `flutter_secure_storage` 实现 Token 加密存储
- [x] 实现 Token 自动刷新逻辑（提前 5 分钟）
- [x] 实现过期检测（`isTokenExpiringSoon()`）
- [x] 存储字段：`access_token`, `refresh_token`, `user_id`, `expires_at`
- [x] 提供异步 API：`getAccessToken()`, `getUserId()`, `clearTokens()`

### 1.2 Automate API Client
**文件**: `lib/automate/core/api_client.dart` ✅
- [x] 基于 `http` 库实现
- [x] 自动注入 JWT Token（`Authorization: Bearer <token>`）
- [x] 自动发送系统语言（`Accept-Language: zh/en`）
- [x] 统一错误处理（code: 7 → 清除 Token）
- [x] 响应格式解析：`{code: 0, data: {...}, msg: "..."}`
- [x] 支持 GET/POST/DELETE 请求

### 1.3 配置管理
**文件**: `lib/automate/core/config.dart` ✅
- [x] 后端 URL 配置（环境变量支持）
- [x] 超时配置（connectTimeout: 10s, receiveTimeout: 30s）
- [x] LLM 默认配置（openrouter/gpt-5）

---

## 📋 Phase 2: 数据模型 + Repository 层

### 2.1 数据模型
**目录**: `lib/automate/models/`

#### Agent 模型
**文件**: `lib/automate/models/agent.dart`
```dart
class Agent {
  final String agentId;
  final String displayName;      // UI 显示名称
  final String name;             // K8s 内部名称
  final String? description;
  final String? avatarUrl;
  final bool isActive;
  final bool isReady;            // Pod 就绪状态
  final String? matrixUserId;    // Matrix 账号 ID
  final String createdAt;
  final String? contractExpiresAt;
  final String workStatus;       // working/idle_long/idle
  final String? lastActiveAt;
}
```

#### AgentTemplate 模型
**文件**: `lib/automate/models/agent_template.dart`
```dart
class AgentTemplate {
  final int id;
  final String name;             // 已本地化
  final String subtitle;         // 已本地化
  final String description;      // 已本地化
  final List<String> skillTags;  // 已本地化
  final String? avatarUrl;
  final String systemPrompt;
}
```

#### Plugin 模型
**文件**: `lib/automate/models/plugin.dart`
```dart
class Plugin {
  final int id;
  final String name;
  final String description;
  final String iconUrl;
  final bool isBuiltin;          // 内置插件不展示
  final int installedCount;
  final Map<String, dynamic>? configSchema;
}

class AgentPlugin {
  final int id;
  final String agentId;
  final String pluginName;
  final String status;           // active/inactive/error
}
```

### 2.2 AgentRepository
**文件**: `lib/automate/repositories/agent_repository.dart`
- [ ] `getUserAgents({int? cursor, int limit = 20})` - 获取用户 Agent 列表（分页）
- [ ] `getAgentStats(String agentId)` - 获取 Agent 统计信息

**API 端点**:
- `GET /api/agents/my-agents?cursor=&limit=20`
- `GET /api/agents/{agent_id}/stats`

### 2.3 AgentTemplateRepository
**文件**: `lib/automate/repositories/agent_template_repository.dart`
- [ ] `getActiveTemplates()` - 获取激活的模板列表（自动发送语言）
- [ ] `hireFromTemplate(int templateId, String name, {String? userRules})` - 从模板雇佣
- [ ] `customCreateAgent(String name, String systemPrompt)` - 自定义创建

**API 端点**:
- `GET /api/agent-templates/active`（无需 JWT，但需要 Accept-Language）
- `POST /api/agents/hire-from-template`
- `POST /api/agents/`

### 2.4 PluginRepository
**文件**: `lib/automate/repositories/plugin_repository.dart`
- [ ] `getPluginsWithStats()` - 获取插件列表（带安装统计）
- [ ] `getAgentPlugins(String agentId)` - 获取 Agent 已安装插件
- [ ] `installPlugin(String agentId, String pluginName, {Map? config})` - 安装插件

**API 端点**:
- `GET /plugins/stats`
- `GET /plugins/agent/{agent_id}`
- `POST /plugins/install`

---

## 📋 Phase 3: 状态管理层（Provider）

### 3.1 TeamProvider
**文件**: `lib/automate/providers/team_provider.dart`
```dart
class TeamProvider extends ChangeNotifier {
  List<Agent> employees = [];
  bool isLoading = false;
  String? error;
  int? nextCursor;
  bool hasMore = true;

  Future<void> loadEmployees();      // 首次加载
  Future<void> loadMore();           // 加载更多
  Future<void> refresh();            // 下拉刷新
  Future<void> deleteEmployee(String agentId);
}
```

### 3.2 RecruitProvider
**文件**: `lib/automate/providers/recruit_provider.dart`
```dart
class RecruitProvider extends ChangeNotifier {
  List<AgentTemplate> templates = [];
  bool isLoading = false;
  String? error;

  Future<void> loadTemplates();
  Future<Agent> hireAgent(int templateId, String name, {String? userRules});
  Future<Agent> customCreateAgent(String name, String systemPrompt);
}
```

### 3.3 TrainingProvider
**文件**: `lib/automate/providers/training_provider.dart`
```dart
class TrainingProvider extends ChangeNotifier {
  List<Plugin> plugins = [];
  Map<String, List<AgentPlugin>> agentPluginsMap = {};
  bool isLoading = false;
  String? error;

  Future<void> loadPlugins();
  Future<void> loadAgentPlugins(String agentId);
  Future<void> installPlugin(String agentId, String pluginName, {Map? config});
}
```

---

## 📋 Phase 4: UI 层（用户体验优先）

### 4.1 设计规范（FluffyChat 风格）

#### 颜色系统
```dart
// 使用 Theme.of(context).colorScheme
primary              // 主色调（按钮、强调）
surfaceContainer     // 卡片背景
surfaceContainerLow  // 页面背景
onSurface            // 主文字
onSurfaceVariant     // 次要文字
```

#### 圆角规范
```dart
BorderRadius.circular(12)  // 卡片圆角
BorderRadius.circular(24)  // Chip/Tag 圆角
BorderRadius.circular(4)   // 消息气泡圆角（微信风格）
```

#### 间距规范
```dart
EdgeInsets.all(16)                         // 标准内边距
EdgeInsets.symmetric(horizontal: 16, vertical: 8)  // 列表项
PaddingValues(bottom: 80)                  // LazyColumn 底部（避免遮挡）
```

#### 动效规范
```dart
Duration(milliseconds: 200)  // 快速动画（按钮状态）
Duration(milliseconds: 300)  // 中等动画（页面切换）
Curves.easeInOut             // 标准缓动
```

### 4.2 团队主页面
**文件**: `lib/automate/pages/team/team_page.dart`

**设计要点**:
- 顶部 AppBar 与 Home 页面风格一致（渐变背景、用户头像）
- 三个 Tab：员工 | 招聘 | 培训
- 支持左右滑动切换（PageView + TabBar 联动）
- Tab 指示器跟随滑动平滑移动

```dart
// 核心结构
Scaffold(
  appBar: _buildAppBar(),  // 渐变背景 + 用户头像
  body: Column(
    children: [
      TabBar(...),         // 三个 Tab
      Expanded(
        child: PageView(
          children: [
            EmployeesTab(),
            RecruitTab(),
            TrainingTab(),
          ],
        ),
      ),
    ],
  ),
)
```

### 4.3 员工列表页面 (EmployeesTab)
**文件**: `lib/automate/pages/team/employees_tab.dart`

**设计要点**:
- 下拉刷新（RefreshIndicator）
- 上拉加载更多（游标分页）
- 员工卡片：头像 + 名称 + 状态徽章 + 工作状态
- 点击卡片 → 发起 DM 聊天
- `isReady=false` 时显示"入职中"提示，拦截点击
- 空状态：友好的插图 + 引导文案

**员工卡片组件**: `lib/automate/widgets/employee_card.dart`
```dart
// 卡片布局
Card(
  child: ListTile(
    leading: _buildAvatar(),      // 头像 + 状态指示器
    title: Text(displayName),
    subtitle: Text(workStatusText),
    trailing: _buildStatusBadge(), // 就绪/入职中
  ),
)
```

**状态徽章颜色**:
- 就绪（working）: 绿色 + 脉冲动画
- 空闲（idle）: 灰色
- 入职中（!isReady）: 橙色 + loading 动画

### 4.4 招聘中心页面 (RecruitTab)
**文件**: `lib/automate/pages/team/recruit_tab.dart`

**设计要点**:
- 网格布局（GridView）展示模板卡片
- 模板卡片：头像 + 名称 + 副标题 + 技能标签
- 技能标签使用 Chip 组件（Wrap 布局，最多显示 3 个）
- 点击卡片 → 弹出雇佣对话框
- 顶部可选添加"自定义创建"入口

**模板卡片组件**: `lib/automate/widgets/template_card.dart`
```dart
// 卡片布局
Card(
  child: Column(
    children: [
      _buildAvatar(),           // 大头像
      Text(name),               // 名称
      Text(subtitle),           // 副标题
      Wrap(                     // 技能标签
        children: skillTags.take(3).map((tag) => Chip(label: Text(tag))).toList(),
      ),
    ],
  ),
)
```

**雇佣对话框**: `lib/automate/widgets/hire_dialog.dart`
- 输入员工名称（必填）
- 可选：额外规则/个性化描述
- 确认按钮 → 调用 `hireFromTemplate()`
- 雇佣成功 → Toast + 切换到员工 Tab

### 4.5 培训市场页面 (TrainingTab)
**文件**: `lib/automate/pages/team/training_tab.dart`

**设计要点**:
- 列表布局展示插件
- 插件卡片：图标 + 名称 + 描述 + 安装数
- 点击卡片 → 弹出培训详情 BottomSheet
- 过滤掉 `isBuiltin=true` 的内置插件

**插件卡片组件**: `lib/automate/widgets/plugin_card.dart`
```dart
// 卡片布局
Card(
  child: ListTile(
    leading: _buildIcon(),       // 插件图标
    title: Text(name),
    subtitle: Text(description),
    trailing: Text('$installedCount 人已培训'),
  ),
)
```

### 4.6 培训详情 BottomSheet
**文件**: `lib/automate/widgets/training_detail_sheet.dart`

**设计要点**:
- 顶部：插件大图标 + 名称 + 描述
- 中间：员工列表（分组：已培训 / 未培训）
- 底部：安装按钮（选择员工后激活）
- 支持配置表单（根据 configSchema 动态生成）

**员工选择逻辑**:
- 已培训员工：显示绿色勾选徽章，不可再次安装
- 未培训员工：点击选中，显示复选框
- 多选后点击"安装"按钮批量安装

---

## 📋 Phase 5: 多语言支持（i18n）

### 5.1 静态文本
**文件**: `lib/l10n/l10n_en.dart`, `lib/l10n/l10n_zh.dart`

**新增字符串**:
```dart
// 团队相关
team: '团队' / 'Team'
employees: '员工' / 'Employees'
recruit: '招聘' / 'Recruit'
training: '培训' / 'Training'

// 员工相关
employee_onboarding: '入职中' / 'Onboarding'
employee_ready: '已就绪' / 'Ready'
employee_working: '工作中' / 'Working'
employee_idle: '空闲中' / 'Idle'

// 招聘相关
hire_agent: '雇佣' / 'Hire'
employee_name: '员工名称' / 'Employee Name'
hire_success: '雇佣成功' / 'Hired Successfully'
custom_create: '自定义创建' / 'Custom Create'

// 培训相关
install_plugin: '安装' / 'Install'
plugin_installed: '已培训' / 'Trained'
training_success: '培训成功' / 'Training Complete'
```

### 5.2 动态数据
- Repository 层自动发送系统语言（`Accept-Language`）
- 后端返回本地化 JSON（客户端直接使用）
- 无需客户端额外处理

---

## 📋 Phase 6: Matrix 集成（DM 聊天）

### 6.1 点击员工卡片发起 DM
**位置**: `employee_card.dart` 的 `onTap` 回调

```dart
onTap: () async {
  if (!employee.isReady) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context)!.employee_onboarding)),
    );
    return;
  }

  final matrixUserId = employee.matrixUserId;
  if (matrixUserId == null) return;

  // 获取 Matrix Client
  final client = Matrix.of(context).client;

  // 创建/获取 DM 房间（必须使用明文，不加密）
  final roomId = await client.startDirectChat(
    matrixUserId,
    enableEncryption: false,  // 关键！后端不支持加密
  );

  // 跳转到聊天页面
  context.go('/rooms/$roomId');
}
```

### 6.2 DM 加密问题（CRITICAL）
- ❌ **禁止**使用加密 DM（`enableEncryption: true`）
- ✅ **必须**使用明文 DM（`enableEncryption: false`）
- **原因**：后端 matrix-nio MCP 服务器不支持解密 MegolmEvent

---

## 📋 Phase 7: 路由配置（go_router）

### 7.1 添加团队路由
**文件**: `lib/config/routes.dart`

```dart
GoRoute(
  path: '/team',
  pageBuilder: (context, state) => defaultPageBuilder(
    context,
    state,
    const TeamPage(),
  ),
  redirect: loggedOutRedirect,  // 未登录重定向
),
```

### 7.2 底部导航栏
**文件**: `lib/pages/chat_list/chat_list_view.dart`（修改现有）

```dart
// 在底部导航栏添加"团队"Tab
BottomNavigationBar(
  currentIndex: _currentIndex,
  onTap: (index) {
    switch (index) {
      case 0: context.go('/rooms');
      case 1: context.go('/team');  // 新增
    }
  },
  items: [
    BottomNavigationBarItem(
      icon: Icon(Icons.chat_bubble_outline),
      activeIcon: Icon(Icons.chat_bubble),
      label: L10n.of(context)!.chats,
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.people_outline),
      activeIcon: Icon(Icons.people),
      label: L10n.of(context)!.team,
    ),
  ],
)
```

---

## 📋 Phase 8: 配置和部署

### 8.1 依赖添加
**文件**: `pubspec.yaml`

```yaml
dependencies:
  provider: ^6.0.0              # 状态管理
  flutter_secure_storage: ^9.0.0  # Token 安全存储（已有）
  cached_network_image: ^3.3.0  # 图片缓存
  shimmer: ^3.0.0               # 骨架屏动画
```

### 8.2 Provider 注册
**文件**: `lib/main.dart`（或适当位置）

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => TeamProvider()),
    ChangeNotifierProvider(create: (_) => RecruitProvider()),
    ChangeNotifierProvider(create: (_) => TrainingProvider()),
  ],
  child: FluffyChatApp(),
)
```

---

## 🚨 关键注意事项

### 1. Token 隔离（CRITICAL）
- ❌ **绝不**混用 Matrix Token 和 JWT Token
- ✅ Matrix Token：由 `matrix` SDK 自动管理
- ✅ JWT Token：由 `AutomateTokenManager` 管理

### 2. DM 加密问题（CRITICAL）
- 必须确保 `enableEncryption: false`
- 后端 matrix-nio 不支持加密消息
- 测试时检查后端能否收到 `RoomMessageText` 事件

### 3. 多语言支持（CRITICAL）
- ❌ **禁止**硬编码字符串
- ✅ 静态文本：使用 `L10n.of(context)!.xxx`
- ✅ 动态数据：后端自动本地化

### 4. 用户体验细节（CRITICAL）
- ✅ 所有列表支持下拉刷新
- ✅ 长列表支持分页加载
- ✅ 操作有即时反馈（loading、toast）
- ✅ 错误状态友好展示
- ✅ 空状态有引导性内容
- ✅ 动画流畅自然（200-300ms）

### 5. LazyColumn 底部内边距
- ✅ 所有带底部导航栏的列表添加 `contentPadding: PaddingValues(bottom: 80)`
- 避免最后一项被遮挡

---

## 📝 验收标准

### 功能验收
- [ ] Android 模拟器：完整功能测试
- [ ] iOS 模拟器：完整功能测试
- [ ] Web 浏览器：完整功能测试
- [ ] 桌面应用：基础功能测试

### 性能验收
- [ ] 列表滚动流畅（60fps）
- [ ] 下拉刷新响应及时（< 500ms）
- [ ] 图片加载不卡顿
- [ ] 首屏渲染 < 1s

### 代码质量
- [ ] 无硬编码字符串
- [ ] 无 TODO 注释残留
- [ ] 通过 `flutter analyze`
- [ ] 通过 `flutter test`（如果有测试）

### 用户体验验收
- [ ] 所有点击有视觉反馈
- [ ] 加载状态清晰可见
- [ ] 错误信息友好易懂
- [ ] 空状态有引导内容
- [ ] 动画流畅不卡顿

---

## 🎯 预估工时
- **Phase 2**: 0.5 天（数据模型 + Repository）
- **Phase 3**: 0.5 天（状态管理）
- **Phase 4**: 2 天（UI 层，重点打磨）
- **Phase 5-8**: 0.5 天（多语言 + 路由 + 配置）

**总计**: 3.5 天（全职开发）

---

**开始时间**: 2025-11-20
**负责人**: Claude Code
**审核人**: Linus Torvalds（哥）
