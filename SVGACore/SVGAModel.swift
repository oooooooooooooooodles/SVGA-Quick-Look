//
//  SVGAModel.swift
//  SVGACore
//
//  SVGA 动画数据模型。
//  schema 依据 SVGAPlayer-iOS 的 svga.proto(Svga.pbobjc.h)移植,
//  同时兼容 SVGA 1.0(JSON, movie.spec)与 SVGA 2.x(protobuf, movie.binary)。
//

import Foundation
import CoreGraphics

// MARK: - Movie

/// 一部 SVGA 动画(等价于 SVGAVideoEntity)。
public struct SVGAMovie {
    public var version: String
    public var videoSize: CGSize
    public var fps: Int
    public var frames: Int

    /// 位图字典:键为 imageKey(不含扩展名),值为原始图片数据(PNG/JPEG)。
    public var images: [String: Data]

    /// 音频数据:键为 audioKey,值为 MP3 数据。
    public var audiosData: [String: Data]

    public var sprites: [SVGASprite]
    public var audios: [SVGAAudio]

    public init(version: String = "",
                videoSize: CGSize = CGSize(width: 100, height: 100),
                fps: Int = 20,
                frames: Int = 0,
                images: [String: Data] = [:],
                audiosData: [String: Data] = [:],
                sprites: [SVGASprite] = [],
                audios: [SVGAAudio] = []) {
        self.version = version
        self.videoSize = videoSize
        self.fps = fps
        self.frames = frames
        self.images = images
        self.audiosData = audiosData
        self.sprites = sprites
        self.audios = audios
    }
}

// MARK: - Sprite

/// 一个元件(等价于 SVGAVideoSpriteEntity)。
public struct SVGASprite {
    public var imageKey: String
    public var matteKey: String?
    public var frames: [SVGAFrame]

    public init(imageKey: String, matteKey: String? = nil, frames: [SVGAFrame] = []) {
        self.imageKey = imageKey
        self.matteKey = matteKey
        self.frames = frames
    }
}

// MARK: - Frame

/// 一帧关键帧(等价于 SVGAVideoSpriteFrameEntity)。
public struct SVGAFrame {
    public var alpha: CGFloat
    public var layout: CGRect
    public var transform: CGAffineTransform
    public var clipPath: String?
    public var shapes: [SVGAShape]

    public init(alpha: CGFloat = 0,
                layout: CGRect = .zero,
                transform: CGAffineTransform = .identity,
                clipPath: String? = nil,
                shapes: [SVGAShape] = []) {
        self.alpha = alpha
        self.layout = layout
        self.transform = transform
        self.clipPath = clipPath
        self.shapes = shapes
    }

    /// 与官方实现一致:变换后 layout 四角的 minX / minY。
    public var nx: CGFloat {
        let l = layout
        let t = transform
        let x = [t.a * l.minX + t.c * l.minY + t.tx,
                 t.a * l.maxX + t.c * l.minY + t.tx,
                 t.a * l.minX + t.c * l.maxY + t.tx,
                 t.a * l.maxX + t.c * l.maxY + t.tx]
        return x.min() ?? 0
    }

    public var ny: CGFloat {
        let l = layout
        let t = transform
        let y = [t.b * l.minX + t.d * l.minY + t.ty,
                 t.b * l.maxX + t.d * l.minY + t.ty,
                 t.b * l.minX + t.d * l.maxY + t.ty,
                 t.b * l.maxX + t.d * l.maxY + t.ty]
        return y.min() ?? 0
    }
}

// MARK: - Shape

/// 矢量元素类型(对应 SVGAProtoShapeEntity_ShapeType)。
public enum SVGAShapeType: Int {
    case shape = 0    // 路径
    case rect = 1     // 矩形
    case ellipse = 2  // 圆形
    case keep = 3     // 与前帧一致
}

/// 矢量元素(对应 SVGAProtoShapeEntity)。
public struct SVGAShape {
    public var type: SVGAShapeType
    public var pathD: String?          // type == .shape
    public var rect: SVGAArgRect?      // type == .rect
    public var ellipse: SVGAArgEllipse? // type == .ellipse
    public var styles: SVGAShapeStyle?
    public var transform: CGAffineTransform?

    public init(type: SVGAShapeType,
                pathD: String? = nil,
                rect: SVGAArgRect? = nil,
                ellipse: SVGAArgEllipse? = nil,
                styles: SVGAShapeStyle? = nil,
                transform: CGAffineTransform? = nil) {
        self.type = type
        self.pathD = pathD
        self.rect = rect
        self.ellipse = ellipse
        self.styles = styles
        self.transform = transform
    }
}

public struct SVGAArgRect {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public var cornerRadius: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.cornerRadius = cornerRadius
    }
}

public struct SVGAArgEllipse {
    public var x: CGFloat
    public var y: CGFloat
    public var radiusX: CGFloat
    public var radiusY: CGFloat

    public init(x: CGFloat, y: CGFloat, radiusX: CGFloat, radiusY: CGFloat) {
        self.x = x; self.y = y; self.radiusX = radiusX; self.radiusY = radiusY
    }
}

// MARK: - ShapeStyle

/// 线段端点样式(对应 SVGAProtoShapeEntity_ShapeStyle_LineCap)。
public enum SVGALineCap: Int {
    case butt = 0
    case round = 1
    case square = 2
}

/// 线段连接样式(对应 SVGAProtoShapeEntity_ShapeStyle_LineJoin)。
public enum SVGALineJoin: Int {
    case miter = 0
    case round = 1
    case bevel = 2
}

/// 矢量渲染参数(对应 SVGAProtoShapeEntity_ShapeStyle)。
public struct SVGAShapeStyle {
    public var fill: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)?
    public var stroke: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)?
    public var strokeWidth: CGFloat
    public var lineCap: SVGALineCap
    public var lineJoin: SVGALineJoin
    public var miterLimit: CGFloat
    public var lineDashI: CGFloat
    public var lineDashII: CGFloat
    public var lineDashIII: CGFloat

    public init(fill: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? = nil,
                stroke: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? = nil,
                strokeWidth: CGFloat = 0,
                lineCap: SVGALineCap = .butt,
                lineJoin: SVGALineJoin = .miter,
                miterLimit: CGFloat = 4,
                lineDashI: CGFloat = 0,
                lineDashII: CGFloat = 0,
                lineDashIII: CGFloat = 0) {
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.lineDashI = lineDashI
        self.lineDashII = lineDashII
        self.lineDashIII = lineDashIII
    }
}

// MARK: - Audio

/// 音频实体(对应 SVGAProtoAudioEntity)。
public struct SVGAAudio {
    public var audioKey: String
    public var startFrame: Int
    public var endFrame: Int
    public var startTime: Int
    public var totalTime: Int

    public init(audioKey: String, startFrame: Int, endFrame: Int, startTime: Int, totalTime: Int) {
        self.audioKey = audioKey
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.startTime = startTime
        self.totalTime = totalTime
    }
}
