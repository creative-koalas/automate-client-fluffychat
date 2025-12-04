# AutoMate Flutter Client - 构建指南

## 环境变量配置

本项目使用环境变量来管理敏感信息和本地配置，避免将这些信息提交到版本控制。

### 必需的环境变量

1. **K8S_NODE_IP**: K8s 集群节点 IP（局域网访问）
2. **ALIYUN_SECRET_KEY**: 阿里云一键登录 SDK 密钥

### 配置步骤

1. 复制环境变量模板：
```bash
cp .env.example .env
```

2. 编辑 `.env` 文件，填入实际值：
```bash
K8S_NODE_IP=192.168.31.22
ALIYUN_SECRET_KEY=your-actual-secret-key
```

## 构建命令

### 开发构建（Debug）
```bash
flutter run \
  --dart-define=K8S_NODE_IP=192.168.31.22 \
  --dart-define=ALIYUN_SECRET_KEY=your-secret-key
```

### 生产构建（Release）
```bash
flutter build apk --release \
  --dart-define=K8S_NODE_IP=192.168.31.22 \
  --dart-define=ALIYUN_SECRET_KEY=your-secret-key
```

### 使用脚本简化构建

创建一个构建脚本 `build.sh`：

```bash
#!/bin/bash
# 从 .env 文件读取环境变量
source .env

flutter run --release \
  --dart-define=K8S_NODE_IP=$K8S_NODE_IP \
  --dart-define=ALIYUN_SECRET_KEY=$ALIYUN_SECRET_KEY \
  -d V2403A  # 你的设备ID
```

使其可执行：
```bash
chmod +x build.sh
```

运行：
```bash
./build.sh
```

## 可选环境变量

- **ONBOARDING_CHATBOT_URL**: Onboarding Chatbot 服务地址
  - 如果不指定，会自动使用 `http://$K8S_NODE_IP:30300`

## 注意事项

- `.env` 文件已添加到 `.gitignore`，不会被提交到版本控制
- 请勿将敏感信息（如 Secret Key）提交到代码仓库
- 团队成员需要各自配置自己的 `.env` 文件
