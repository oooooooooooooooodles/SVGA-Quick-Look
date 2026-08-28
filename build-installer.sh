#!/bin/bash
# ============================================================
# SVGA Quick Look 安装包构建脚本
# 每次运行:
#   1. 自动递增版本号(MARKETING_VERSION 的 minor 位 +1)
#   2. 构建 Release
#   3. 生成 DMG 安装包,文件名带版本号:SVGA Quick Look x.y.dmg
# 产物输出到 ~/Desktop/
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

PROJECT="SVGA Quick Look.xcodeproj"
SCHEME="SVGA Quick Look"
PBX="$PROJECT/project.pbxproj"
APP_NAME="SVGA Quick Look"
STAGING=".build/dmg/staging"

echo "==> 1/4 递增版本号"
# 读取当前 MARKETING_VERSION(取第一个匹配)
OLD_VER=$(grep -m1 'MARKETING_VERSION = ' "$PBX" | sed -E 's/.*MARKETING_VERSION = ([0-9]+\.[0-9]+);.*/\1/')
OLD_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBX" | sed -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/')
if [ -z "$OLD_VER" ]; then
    echo "错误:找不到 MARKETING_VERSION" >&2
    exit 1
fi

MAJOR="${OLD_VER%%.*}"
MINOR="${OLD_VER##*.}"
NEW_VER="${MAJOR}.$((MINOR + 1))"
NEW_BUILD=$((OLD_BUILD + 1))
echo "版本 $OLD_VER (build $OLD_BUILD) -> $NEW_VER (build $NEW_BUILD)"

# 替换所有 target 的版本号
sed -i '' "s/MARKETING_VERSION = ${OLD_VER};/MARKETING_VERSION = ${NEW_VER};/g" "$PBX"
sed -i '' "s/CURRENT_PROJECT_VERSION = ${OLD_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBX"

echo "==> 2/4 构建 Release (v$NEW_VER)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -derivedDataPath .build/DerivedData build 2>&1 | grep -E "error:|BUILD" | sort -u | head -10
APP_SRC=".build/DerivedData/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_SRC" ]; then
    echo "错误:构建产物不存在" >&2
    exit 1
fi

echo "==> 3/4 组装 DMG 内容"
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
ditto "$APP_SRC" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/安装说明.txt" <<'EOF'
SVGA Quick Look
==============

安装:
1. 把 "SVGA Quick Look.app" 拖入 "Applications" 文件夹
2. 首次启动时,App 会自动注册 Quick Look 扩展
3. 在系统设置 → 通用 → 登录项与扩展 → Quick Look 中确认两个扩展已启用

使用:
- Finder 中 .svga 文件图标显示动画缩略图
- 选中 .svga 文件按空格键实时播放预览
- 打开 App 后拖入或 ⌘O 打开 .svga 文件播放

说明:本安装包为本地 ad-hoc 签名构建,仅建议在本机使用。
EOF
# 背景图与窗口布局(持久模板)
if [ -f ".build/dmg/background.png" ]; then
    cp ".build/dmg/background.png" "$STAGING/.background/background.png"
fi
if [ -f ".build/dmg/layout.DS_Store" ]; then
    cp ".build/dmg/layout.DS_Store" "$STAGING/.DS_Store"
    echo "已应用窗口布局(layout.DS_Store)"
fi

echo "==> 4/4 生成 DMG"
DMG_NAME="${APP_NAME} ${NEW_VER}.dmg"
DMG_PATH="$HOME/Desktop/$DMG_NAME"
rm -f "$DMG_PATH"
hdiutil create -volname "${APP_NAME} ${NEW_VER}" \
    -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" 2>&1 | tail -1

# 同步更新 .build/dmg 里的模板(下次复用布局)
mkdir -p ".build/dmg"
rm -f ".build/dmg/SVGA Quick Look.dmg"
cp "$DMG_PATH" ".build/dmg/SVGA Quick Look.dmg"

echo ""
echo "==> 清理 LaunchServices 残留(避免打开方式出现多个本 App)"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -d ".build/DerivedData/Build/Products/Release/$APP_NAME.app" ]; then
    "$LSREG" -u ".build/DerivedData/Build/Products/Release/$APP_NAME.app" 2>/dev/null || true
fi
if [ -d ".build/DerivedData/Build/Products/Debug/$APP_NAME.app" ]; then
    "$LSREG" -u ".build/DerivedData/Build/Products/Debug/$APP_NAME.app" 2>/dev/null || true
fi
# staging 目录(打包用)也一并注销
if [ -d "$STAGING/$APP_NAME.app" ]; then
    "$LSREG" -u "$STAGING/$APP_NAME.app" 2>/dev/null || true
fi
"$LSREG" -f "/Applications/$APP_NAME.app" 2>/dev/null || true

# 注销构建产物的扩展注册(pluginkit):陈旧 appex 注册曾导致 Finder 缩略图
# 解析到已删除的拷贝而失效(仅 lsregister -u 应用不足以移除扩展注册)
for dir in ".build/DerivedData/Build/Products/Release" ".build/DerivedData/Build/Products/Debug" ".build/dmg/staging"; do
    app="$dir/$APP_NAME.app"
    [ -d "$app" ] || continue
    for appex in "$app"/Contents/PlugIns/*.appex; do
        if [ -d "$appex" ]; then
            /usr/bin/pluginkit -r "$appex" 2>/dev/null || true
        fi
    done
done
echo "==> 已完成: /Applications/$APP_NAME.app 为唯一注册的应用副本"

echo ""
echo "完成: $DMG_PATH"
open -R "$DMG_PATH" 2>/dev/null || true
