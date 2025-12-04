#!/bin/bash
# AutoMate Flutter Client 构建脚本
# 自动从 .env 文件读取环境变量并构建

set -e

# 检查 .env 文件是否存在
if [ ! -f .env ]; then
    echo "错误: .env 文件不存在"
    echo "请复制 .env.example 并填入实际值："
    echo "  cp .env.example .env"
    exit 1
fi

# 从 .env 文件读取环境变量
source .env

# 检查必需的环境变量
if [ -z "$K8S_NODE_IP" ]; then
    echo "错误: K8S_NODE_IP 未设置"
    exit 1
fi

if [ -z "$ALIYUN_SECRET_KEY" ]; then
    echo "错误: ALIYUN_SECRET_KEY 未设置"
    exit 1
fi

echo "================================================"
echo "开始构建 AutoMate Flutter Client"
echo "K8S_NODE_IP: $K8S_NODE_IP"
echo "ALIYUN_SECRET_KEY: ${ALIYUN_SECRET_KEY:0:20}..." # 只显示前20个字符
echo "================================================"

# 构建参数
DEVICE=${1:-V2403A}  # 默认设备
MODE=${2:-release}   # 默认 release 模式

echo "目标设备: $DEVICE"
echo "构建模式: $MODE"

# 执行 Flutter 构建
flutter run --$MODE \
    --dart-define=K8S_NODE_IP=$K8S_NODE_IP \
    --dart-define=ALIYUN_SECRET_KEY=$ALIYUN_SECRET_KEY \
    -d $DEVICE

echo "构建完成！"
