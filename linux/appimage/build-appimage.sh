#!/bin/bash
# Psygo Linux AppImage 打包脚本
# 此脚本将 Flutter 应用打包为 AppImage 格式，包含系统托盘所需的依赖

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/linux/x64/release/bundle"
APPDIR="$PROJECT_ROOT/build/AppDir"
APP_NAME="Psygo"
APP_ID="com.psygo.app"

echo "=== Psygo AppImage 打包脚本 ==="
echo "项目目录: $PROJECT_ROOT"
echo "构建目录: $BUILD_DIR"

# 检查是否已构建 Release 版本
if [ ! -d "$BUILD_DIR" ]; then
    echo "错误: 未找到 Release 构建目录"
    echo "请先运行: flutter build linux --release"
    exit 1
fi

# 清理旧的 AppDir
rm -rf "$APPDIR"
mkdir -p "$APPDIR"

echo "1. 复制应用文件..."
# 复制整个 bundle 目录内容
cp -r "$BUILD_DIR"/* "$APPDIR/"

# 重命名可执行文件
if [ -f "$APPDIR/automate" ]; then
    mv "$APPDIR/automate" "$APPDIR/psygo"
fi

echo "2. 创建 AppRun 启动脚本..."
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
# AppImage 启动脚本

SELF=$(readlink -f "$0")
HERE=${SELF%/*}

# 设置库路径
export LD_LIBRARY_PATH="${HERE}/lib:${HERE}/usr/lib:${LD_LIBRARY_PATH}"

# 设置 GDK_PIXBUF 路径（用于系统托盘图标）
if [ -d "${HERE}/usr/lib/gdk-pixbuf-2.0" ]; then
    export GDK_PIXBUF_MODULE_FILE="${HERE}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
    export GDK_PIXBUF_MODULEDIR="${HERE}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders"
fi

# 运行应用
exec "${HERE}/psygo" "$@"
EOF
chmod +x "$APPDIR/AppRun"

echo "3. 复制桌面文件和图标..."
# 复制 desktop 文件
cp "$SCRIPT_DIR/psygo.desktop" "$APPDIR/psygo.desktop"

# 复制图标
if [ -f "$PROJECT_ROOT/assets/logo.png" ]; then
    cp "$PROJECT_ROOT/assets/logo.png" "$APPDIR/psygo.png"
else
    echo "警告: 未找到 assets/logo.png，使用默认图标"
    # 创建一个简单的占位图标
    touch "$APPDIR/psygo.png"
fi

echo "4. 复制系统托盘依赖库..."
# 创建 usr/lib 目录用于存放依赖
mkdir -p "$APPDIR/usr/lib"

# 复制 libayatana-appindicator 及其依赖
LIBS_TO_COPY=(
    "/usr/lib/x86_64-linux-gnu/libayatana-appindicator3.so.1"
    "/usr/lib/x86_64-linux-gnu/libayatana-indicator3.so.7"
    "/usr/lib/x86_64-linux-gnu/libayatana-ido3-0.4.so.0"
    "/usr/lib/x86_64-linux-gnu/libdbusmenu-glib.so.4"
    "/usr/lib/x86_64-linux-gnu/libdbusmenu-gtk3.so.4"
)

for lib in "${LIBS_TO_COPY[@]}"; do
    if [ -f "$lib" ]; then
        echo "  复制: $lib"
        cp "$lib" "$APPDIR/usr/lib/"
    else
        # 尝试不同的路径
        alt_lib="${lib/x86_64-linux-gnu\//}"
        if [ -f "$alt_lib" ]; then
            echo "  复制: $alt_lib"
            cp "$alt_lib" "$APPDIR/usr/lib/"
        else
            echo "  警告: 未找到 $lib"
        fi
    fi
done

# 复制 lib 目录中的库到 usr/lib（合并）
if [ -d "$APPDIR/lib" ]; then
    cp -n "$APPDIR/lib"/* "$APPDIR/usr/lib/" 2>/dev/null || true
fi

echo "5. 下载 appimagetool..."
APPIMAGETOOL="$PROJECT_ROOT/build/appimagetool"
if [ ! -f "$APPIMAGETOOL" ]; then
    echo "  下载 appimagetool..."
    wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -O "$APPIMAGETOOL"
    chmod +x "$APPIMAGETOOL"
fi

echo "6. 生成 AppImage..."
cd "$PROJECT_ROOT/build"

# 设置 ARCH 环境变量
export ARCH=x86_64

# 生成 AppImage
"$APPIMAGETOOL" --no-appstream "$APPDIR" "${APP_NAME}-x86_64.AppImage"

echo ""
echo "=== 打包完成 ==="
echo "AppImage 文件: $PROJECT_ROOT/build/${APP_NAME}-x86_64.AppImage"
echo ""
echo "用户可以直接运行此文件，无需安装任何依赖！"
