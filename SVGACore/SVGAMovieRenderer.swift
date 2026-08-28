//
//  SVGAMovieRenderer.swift
//  SVGACore
//
//  缩略图渲染:将指定帧快照为 CGImage(供 Quick Look ThumbnailProvider 与测试用)。
//

import AppKit
import CoreGraphics
import ImageIO
import QuartzCore

public enum SVGAMovieRenderer {

    /// 将 PNG/JPEG 数据解码为 CGImage。
    public static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 把 movie 的第 frame 帧渲染为 size 尺寸的位图。
    /// - Parameter contentMode: .fit = 等比完整显示(留边); .fill = 填满并裁切溢出。
    public static func renderFrame(movie: SVGAMovie,
                                   frame: Int,
                                   size: CGSize,
                                   contentMode: ContentMode = .fit,
                                   backgroundColor: CGColor = CGColor(gray: 0.0, alpha: 1.0)) -> CGImage? {
        guard movie.videoSize.width > 0, movie.videoSize.height > 0,
              size.width > 0, size.height > 0 else { return nil }

        let images = movie.images.compactMapValues { cgImage(from: $0) }
        let built = SVGALayerTree.build(movie: movie, images: images)
        let safeFrame = min(max(0, frame), max(0, movie.frames - 1))
        for layer in built.contentLayers {
            layer.stepToFrame(safeFrame)
        }

        guard let ctx = CGContext(data: nil,
                                  width: Int(size.width.rounded()),
                                  height: Int(size.height.rounded()),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        ctx.setFillColor(backgroundColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        // 翻转为 y-down(与图层坐标一致),并按 contentMode 缩放居中
        let video = movie.videoSize
        let scaleX = size.width / video.width
        let scaleY = size.height / video.height
        let s: CGFloat
        switch contentMode {
        case .fill: s = max(scaleX, scaleY)
        default: s = min(scaleX, scaleY)
        }
        let dx = (size.width - video.width * s) / 2
        let dy = (size.height - video.height * s) / 2
        ctx.translateBy(x: dx, y: size.height - dy)
        ctx.scaleBy(x: s, y: -s)

        built.drawLayer.render(in: ctx)
        return ctx.makeImage()
    }

    public enum ContentMode {
        case fit
        case fill
    }

    /// 选择一个"内容丰富"的帧用于缩略图:在多个采样点中挑可见内容最多的帧,
    /// 避免开头空白/近透明帧被选中导致缩略图黑屏。
    public static func thumbnailFrame(for movie: SVGAMovie) -> Int {
        guard movie.frames > 0 else { return 0 }
        // 采样点:开头、1/4、1/3、1/2、2/3,覆盖常见动画节奏
        let candidates: [Int] = {
            var pts = [0, movie.frames / 4, movie.frames / 3, movie.frames / 2, movie.frames * 2 / 3]
            if movie.frames > 1 { pts.append(movie.frames - 1) }
            return pts.map { min(max(0, $0), movie.frames - 1) }
        }()

        var bestFrame = 0
        var bestScore = -1
        for f in candidates {
            var score = 0
            var anyVisible = false
            for sprite in movie.sprites where f < sprite.frames.count {
                let frame = sprite.frames[f]
                // 有效可见:alpha 明显 >0 且有形状或布局(位图 sprite 由 layout 承载)
                if frame.alpha > 0.05 {
                    if frame.shapes.count > 0 {
                        score += frame.shapes.count
                        anyVisible = true
                    }
                    if !frame.layout.isEmpty {
                        score += 1
                        anyVisible = true
                    }
                }
            }
            if anyVisible && score > bestScore {
                bestScore = score
                bestFrame = f
            }
        }
        return bestFrame
    }
}
