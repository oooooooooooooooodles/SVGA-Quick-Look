# SVGA Quick Look

<div align="center">
  <img src="/material/svga logo.png" width="128" alt="SVGA Quick Look">
</div>

> 在 Finder 里不打开任何软件，就能看到 SVGA 动画的实时缩略图；按一下空格键，立刻播放预览——轻点即见的动效体验，让每个动画文件都活起来。

<div align="center">
  <img src="/material/Screenshot.png" width="300" alt="SVGA Quick Look">
</div>


SVGA Quick Look 是专为 [SVGA](https://github.com/svga/SVGAPlayer-iOS) 动画格式打造的 macOS 原生工具，由 **Finder 缩略图扩展**、**Quick Look 空格预览扩展** 和 **播放器主程序** 三部分组成，全部基于 SVGAPlayer-iOS 渲染逻辑移植，零第三方依赖、完全自包含（Swift 实现）。

![macOS](https://img.shields.io/badge/macOS-26.0+-333333?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white)
![Xcode](https://img.shields.io/badge/Xcode-26-147EFB?logo=xcode&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

---

## ✨ 功能特性

- 🖼️ **Finder 缩略图** — `.svga` 文件图标直接显示动画画面（多帧采样评分自动选取最佳可见帧，支持 Retina）
- ⚡ **空格键实时预览** — 在 Finder 中选中 `.svga` 按空格，以原生视图播放动画
- 🎬 **播放器主程序** — macOS 26 液态玻璃（Liquid Glass）设计，三栏布局：
  - **左侧 · 素材检视器**：位图素材缩略图列表，右键拷贝、拖拽到桌面/其他软件
  - **中间 · 动画画板**：播放/暂停、进度拖动（实时渲染对应帧）、0.5×–5× 缩放、平移浏览、15 种画板主题（透明棋盘格 / 黑 / 白 / 多彩 / 彩虹流光…）
  - **右侧 · 参数检查器**：文件名、大小、画布尺寸、总帧数、帧率、图层/位图/音频数量、格式版本
- 📤 **导出所有图片**（⌘E）— 一键导出全部位图素材到任意文件夹
- 🖱️ **拖拽即开** — 把 `.svga` 拖进窗口立即播放；双击画布或 ⌘O 打开文件
- 🎹 **快捷键** — ⌘O 打开文件、⌘E 导出图片、⌘P 播放/暂停
- 🌓 **深色/浅色模式自适应**，界面全中文
- 🔁 **单实例** — 重复启动或双击文件时，自动把文件转发给已运行实例，无双窗口

## 📋 环境要求

- macOS 26 (Tahoe) 或更高
- Apple Silicon 或 Intel（当前在 Intel x86_64 上构建验证）
- 构建需要 Xcode 26+、Swift 6

## 📦 安装

1. 从 Release 下载 `SVGA Quick Look x.y.dmg`
2. 把 `SVGA Quick Look.app` 拖入「应用程序」文件夹
3. 首次启动时 App 自动注册两个 Quick Look 扩展（无需手动操作）
4. 可在「系统设置 → 通用 → 登录项与扩展 → Quick Look」中确认扩展已启用

## 🚀 使用

| 操作 | 效果 |
|---|---|
| Finder 中浏览 `.svga` 文件 | 图标直接显示动画画面 |
| 选中 `.svga` 文件按空格 | 实时播放动画预览 |
| 打开 App 拖入 `.svga` | 播放 + 素材/参数面板 |
| ⌘P / 空格 | 播放 / 暂停 |
| 拖动进度条 | 实时渲染对应帧，松手续播 |
| 画板缩放按钮 / 拖动画布 | 0.5×–5× 缩放、平移浏览 |
| 右键素材 → 拷贝图片 / 拖出 | 导出素材到剪贴板 / 桌面 |
| ⌘E | 导出所有图片 |

命令行快速验证：

```bash
# 缩略图（任意 .svga 文件）
qlmanage -t -s 256 -o /tmp/ql-test your-animation.svga

# 空格预览（弹出 Quick Look 面板）
qlmanage -p your-animation.svga
```

## 🔧 从源码构建

```bash
# 一键构建 Release 并生成 DMG 安装包
# （自动递增版本号，产物输出到 ~/Desktop/）
./build-installer.sh

# 或直接用 Xcode
open "SVGA Quick Look.xcodeproj"
```

工程默认 ad-hoc 签名，本地自用可直接 ⌘R 运行；分发需在 Xcode 中配置开发者证书并公证。

## 📁 项目结构

```
SVGA Quick Look.xcodeproj        Xcode 工程（3 个 target）
SVGACore/                        共享解析/渲染核心（主程序与两个扩展共用）
  ├── SVGAModel.swift           数据模型（移植自 svga.proto）
  ├── SVGAProto.swift            手写 protobuf wire-format 解码器
  ├── SVGAMovieParser.swift      入口解析：ZIP + zlib + JSON + protobuf
  ├── SVGABezierPath.swift       SVG 路径（"d"）→ CGPath
  ├── SVGALayers.swift           CALayer 渲染树（移植 SVGAContentLayer/BitmapLayer/VectorLayer）
  ├── SVGAPlayerView.swift       macOS 播放视图（NSView + 逐帧步进）
  └── SVGAMovieRenderer.swift    帧快照渲染（缩略图用）
SVGA Quick Look/                  宿主 App（SwiftUI，液态玻璃风格）
  └── Sources/                   三栏界面、播放控制、主题、菜单、扩展注册
SVGA Quick Look Thumbnail Extension/   Finder 缩略图扩展
SVGA Quick Look Preview Extension/     Quick Look 预览扩展
svga logo.icon / Resources/      应用图标
build-installer.sh               版本递增 + Release 构建 + DMG 打包脚本
```

## 🧠 技术实现

- **格式兼容**：支持全部三种 SVGA 形态
  - SVGA 1.x（ZIP + `movie.spec` JSON）
  - SVGA 2.x（ZIP + `movie.binary` protobuf + `images/`）
  - SVGA 2.0.0 扁平单文件（zlib 压缩的 protobuf，位图内嵌）
- **自包含解析**：未引入 Protobuf 库，按 `Svga.pbobjc.h` 字段编号手写 wire 解码器；自实现极简 ZIP 读取器（中央目录 + 本地头），DEFLATE 条目用系统 zlib（`inflateInit2` windowBits=-15）解压；解压输出与字段长度均设 512MB 上限、ZIP 边界校验，防恶意文件崩溃
- **渲染引擎**：CALayer 层级逐帧移植自官方 [SVGAPlayer-iOS](https://github.com/svga/SVGAPlayer-iOS)（每个 sprite 一个内容层，内嵌位图层与矢量层），逐帧更新 `layout/transform/alpha/clipPath`，支持 `.matte` 遮罩、`keep` 帧缓存、虚线/圆角/椭圆等矢量样式；`stepToFrame` 严格遵循官方几何计算顺序
- **性能**：帧状态独立对象发布 + 30Hz 节流，避免 60fps 全界面重渲染；缩略图多帧采样评分取最佳画面；加载代际（generation）防并发竞态
- **UI 框架**：SwiftUI NavigationSplitView + Inspector + `.glassEffect` 液态玻璃，macOS 26 官方设计语言
- **缩略图两个坑**（均已实测修复）：
  - `QLThumbnailReply(contextSize:)` 的绘制上下文实际像素尺寸 = contextSize × request.scale，图像须按 `maximumSize × scale` 矩形绘制，否则缩略图只覆盖画布一角
  - QL 缩略图上下文图像绘制是翻转的，绘制前需做 y 轴补偿，否则上下颠倒

## ⚠️ 已知限制

- 预览与缩略图不含**音频**（官方库音频播放基于 UIKit 的 AVAudioPlayer，未移植）
- 与官方播放器一致，不做关键帧插值（直接按下标取帧）
- 动态对象/文本替换（`setImage:forKey:` 等）未移植
- 安装包为 ad-hoc 签名，仅建议本机使用

## 🙏 致谢与许可

渲染与解析核心参考 [SVGAPlayer-iOS](https://github.com/svga/SVGAPlayer-iOS)（YY Inc. 开源，MIT）；Quick Look 扩展遵循 Apple 官方 [QLThumbnailProvider / QLPreviewingController](https://developer.apple.com/documentation/quicklookthumbnailing) 契约。本项目代码同样以 MIT 协议提供，仅供学习交流。
