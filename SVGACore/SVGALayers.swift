//
//  SVGALayers.swift
//  SVGACore
//
//  CALayer 渲染层:忠实移植 SVGAPlayer-iOS 的
//  SVGAContentLayer / SVGABitmapLayer / SVGAVectorLayer 与 SVGAPlayer.draw()。
//  通过 CALayer 层级(而非直接 CG 绘制)渲染,保证与官方实现行为一致。
//

import AppKit
import QuartzCore

// MARK: - 位图层

/// 位图内容层(对应 SVGABitmapLayer);contents 为 CGImage,Aspect 适配。
final class SVGABitmapLayer: CALayer {
    private let frames: [SVGAFrame]

    init(frames: [SVGAFrame]) {
        self.frames = frames
        super.init()
        backgroundColor = NSColor.clear.cgColor
        masksToBounds = false
        contentsGravity = .resizeAspect
        stepToFrame(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// CA 创建 presentation 层时调用,必须实现(否则隐式动画触发时崩溃)。
    override init(layer: Any) {
        if let other = layer as? SVGABitmapLayer {
            frames = other.frames
        } else {
            frames = []
        }
        super.init(layer: layer)
    }

    /// 官方实现中位图内容不随帧变化(帧间变化由 ContentLayer 的 transform 承担)。
    func stepToFrame(_ frame: Int) {
        _ = frames
        _ = frame
    }
}

// MARK: - 矢量层

/// 矢量元素层(对应 SVGAVectorLayer):每帧重建 shape 子层。
final class SVGAVectorLayer: CALayer {
    private let frames: [SVGAFrame]
    private var drawedFrame: Int = -1
    private var keepFrameCache: [Int: Int] = [:]

    init(frames: [SVGAFrame]) {
        self.frames = frames
        super.init()
        backgroundColor = NSColor.clear.cgColor
        masksToBounds = false
        resetKeepFrameCache()
        stepToFrame(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// CA 创建 presentation 层时调用,必须实现(否则隐式动画触发时崩溃)。
    override init(layer: Any) {
        if let other = layer as? SVGAVectorLayer {
            frames = other.frames
            drawedFrame = other.drawedFrame
            keepFrameCache = other.keepFrameCache
        } else {
            frames = []
        }
        super.init(layer: layer)
    }

    func stepToFrame(_ frame: Int) {
        if frame < frames.count {
            drawFrame(frame)
        }
    }

    private func resetKeepFrameCache() {
        var lastKeep = 0
        var cache: [Int: Int] = [:]
        for (idx, f) in frames.enumerated() {
            if isKeepFrame(f) {
                cache[idx] = lastKeep
            } else {
                lastKeep = idx
            }
        }
        keepFrameCache = cache
    }

    private func isKeepFrame(_ f: SVGAFrame) -> Bool {
        guard let first = f.shapes.first else { return false }
        return first.type == .keep
    }

    private func requestKeepFrame(_ frame: Int) -> Int? {
        keepFrameCache[frame]
    }

    private func drawFrame(_ frame: Int) {
        let frameItem = frames[frame]
        if isKeepFrame(frameItem) {
            // keep 帧的"目标绘制帧"是 requestKeepFrame 返回的帧;
            // 若该目标帧已绘制过则跳过,避免每轮循环重复重建图层
            let target = requestKeepFrame(frame) ?? frame
            if drawedFrame == target { return }
            drawedFrame = target
        } else {
            drawedFrame = frame
        }
        sublayers?.forEach { $0.removeFromSuperlayer() }
        for shape in frameItem.shapes {
            if let layer = makeShapeLayer(shape) {
                addSublayer(layer)
            }
        }
    }

    private func makeShapeLayer(_ shape: SVGAShape) -> CALayer? {
        let layer: CAShapeLayer
        switch shape.type {
        case .shape:
            guard let d = shape.pathD, !d.isEmpty else { return nil }
            layer = CAShapeLayer()
            layer.path = SVGABezierPath.path(from: d)
        case .rect:
            guard let r = shape.rect else { return nil }
            layer = CAShapeLayer()
            layer.path = CGPath(roundedRect: CGRect(x: r.x, y: r.y, width: r.width, height: r.height),
                                cornerWidth: r.cornerRadius,
                                cornerHeight: r.cornerRadius,
                                transform: nil)
        case .ellipse:
            guard let e = shape.ellipse else { return nil }
            layer = CAShapeLayer()
            layer.path = CGPath(ellipseIn: CGRect(x: e.x - e.radiusX,
                                                  y: e.y - e.radiusY,
                                                  width: e.radiusX * 2,
                                                  height: e.radiusY * 2),
                                transform: nil)
        case .keep:
            return nil
        }
        applyStyle(layer, style: shape.styles)
        if let t = shape.transform {
            layer.setAffineTransform(t)
        }
        return layer
    }

    private func applyStyle(_ layer: CAShapeLayer, style: SVGAShapeStyle?) {
        layer.masksToBounds = false
        layer.backgroundColor = NSColor.clear.cgColor
        guard let s = style else { return }
        if let fill = s.fill {
            layer.fillColor = CGColor(red: fill.r, green: fill.g, blue: fill.b, alpha: fill.a)
        } else {
            layer.fillColor = NSColor.clear.cgColor
        }
        if let stroke = s.stroke {
            layer.strokeColor = CGColor(red: stroke.r, green: stroke.g, blue: stroke.b, alpha: stroke.a)
        }
        layer.lineWidth = s.strokeWidth
        switch s.lineCap {
        case .round: layer.lineCap = .round
        case .square: layer.lineCap = .square
        default: layer.lineCap = .butt
        }
        switch s.lineJoin {
        case .round: layer.lineJoin = .round
        case .bevel: layer.lineJoin = .bevel
        default: layer.lineJoin = .miter
        }
        layer.lineDashPhase = s.lineDashIII
        if s.lineDashI > 0 || s.lineDashII > 0 {
            layer.lineDashPattern = [
                NSNumber(value: s.lineDashI < 1.0 ? 1.0 : s.lineDashI),
                NSNumber(value: s.lineDashII < 0.1 ? 0.1 : s.lineDashII),
            ]
        }
        layer.miterLimit = s.miterLimit
    }
}

// MARK: - 内容层

/// 单个 sprite 的内容层(对应 SVGAContentLayer):承载位图 + 矢量,逐帧更新布局/变换。
/// 采用"直接计算最终几何 + 变化去重",仅在值实际变化时写回 CALayer,
/// 大幅降低播放时的 CA 合成开销。
final class SVGAContentLayer: CALayer {
    private let frames: [SVGAFrame]
    var imageKey: String = ""

    /// 对应官方 setBitmapLayer: 访问器,赋值时挂载为子层。
    var bitmapLayer: SVGABitmapLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let layer = bitmapLayer { addSublayer(layer) }
        }
    }

    /// 对应官方 setVectorLayer: 访问器,赋值时挂载为子层。
    var vectorLayer: SVGAVectorLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let layer = vectorLayer { addSublayer(layer) }
        }
    }

    /// 用户在图层检视器中手动隐藏(优先级高于帧 alpha)。
    var isUserHidden = false

    // MARK: - 状态去重缓存

    private var lastAlpha: CGFloat = .nan
    private var lastBoundsSize: CGSize = .zero
    private var lastTransform: CGAffineTransform = .identity
    private var lastPosition: CGPoint = .zero
    private var lastClipPath: String?

    init(frames: [SVGAFrame]) {
        self.frames = frames
        super.init()
        backgroundColor = NSColor.clear.cgColor
        masksToBounds = false
        stepToFrame(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// CA 创建 presentation 层时调用,必须实现(否则隐式动画触发时崩溃)。
    override init(layer: Any) {
        if let other = layer as? SVGAContentLayer {
            frames = other.frames
        } else {
            frames = []
        }
        super.init(layer: layer)
    }

    /// 对应官方 setFrame: 覆写:帧变化时同步位图/矢量子层的 bounds。
    override var frame: CGRect {
        get { super.frame }
        set {
            super.frame = newValue
            bitmapLayer?.frame = bounds
            vectorLayer?.frame = bounds
        }
    }

    func stepToFrame(_ frame: Int) {
        if isUserHidden {
            if !isHidden { isHidden = true }
            return
        }
        guard frame < frames.count else { return }
        let frameItem = frames[frame]
        guard frameItem.alpha > 0 else {
            if !isHidden { isHidden = true }
            return
        }
        if isHidden { isHidden = false }

        if frameItem.alpha != lastAlpha {
            opacity = Float(frameItem.alpha)
            lastAlpha = frameItem.alpha
        }

        // 忠实移植官方 SVGAContentLayer.stepToFrame 的分步设置顺序:
        //   1) position 归零 → 2) transform 归零 → 3) frame = layout
        //   → 4) 设 transform → 5) 用 nx/ny 修正 position。
        // CALayer 的 frame 是只读的,用等价操作:先归零,再设 bounds
        // 与 position(= layout 中心),设置 transform 后 frame.origin 反映
        // 旋转/缩放后的原点,最后修正 position。
        let layout = frameItem.layout
        let t = frameItem.transform

        position = .zero
        transform = CATransform3DIdentity
        bounds = CGRect(origin: .zero, size: layout.size)
        position = CGPoint(x: layout.midX, y: layout.midY)
        bitmapLayer?.frame = bounds
        vectorLayer?.frame = bounds

        // 设置 transform(绕 anchorPoint = bounds 中心旋转)
        transform = CATransform3DMakeAffineTransform(t)

        // 官方:offsetX = frame.origin.x - nx; position = -(offsetX, offsetY)
        // frame.origin 是设置 transform 后的帧原点(受旋转/缩放影响)
        let offsetX = self.frame.origin.x - frameItem.nx
        let offsetY = self.frame.origin.y - frameItem.ny
        position = CGPoint(x: position.x - offsetX, y: position.y - offsetY)

        if frameItem.alpha != lastAlpha {
            opacity = Float(frameItem.alpha)
            lastAlpha = frameItem.alpha
        }
        if frameItem.clipPath != lastClipPath {
            lastClipPath = frameItem.clipPath
            if let maskLayer = makeMaskLayer(frameItem) as? CAShapeLayer {
                let clone = CAShapeLayer()
                clone.path = maskLayer.path
                clone.fillColor = maskLayer.fillColor
                mask = clone
            } else {
                mask = nil
            }
        }
        lastBoundsSize = layout.size
        lastTransform = t
        lastPosition = position
        bitmapLayer?.stepToFrame(frame)
        vectorLayer?.stepToFrame(frame)
    }

    /// clipPath → 黑色填充的遮罩 shape layer(对应官方 SVGABezierPath createLayer)。
    private func makeMaskLayer(_ frameItem: SVGAFrame) -> CALayer? {
        guard let clipPath = frameItem.clipPath, !clipPath.isEmpty else { return nil }
        let layer = CAShapeLayer()
        layer.path = SVGABezierPath.path(from: clipPath)
        layer.fillColor = NSColor.black.cgColor
        return layer
    }
}

// MARK: - 图层树构建

/// 将 SVGAMovie 构建为可渲染的 CALayer 树(对应官方 SVGAPlayer.draw())。
enum SVGALayerTree {

    static func build(movie: SVGAMovie, images: [String: CGImage]) -> (drawLayer: CALayer, contentLayers: [SVGAContentLayer]) {
        let drawLayer = CALayer()
        drawLayer.frame = CGRect(origin: .zero, size: movie.videoSize)
        drawLayer.masksToBounds = true

        var tempHostLayers: [String: CALayer] = [:]
        var tempContentLayers: [SVGAContentLayer] = []

        for (idx, sprite) in movie.sprites.enumerated() {
            var bitmap: CGImage?
            if !sprite.imageKey.isEmpty {
                let bitmapKey = (sprite.imageKey as NSString).deletingPathExtension
                bitmap = images[bitmapKey] ?? images[sprite.imageKey]
            }

            let contentLayer = SVGAContentLayer(frames: sprite.frames)
            contentLayer.imageKey = sprite.imageKey
            tempContentLayers.append(contentLayer)

            if let bitmap = bitmap {
                let bitmapLayer = SVGABitmapLayer(frames: sprite.frames)
                bitmapLayer.contents = bitmap
                contentLayer.bitmapLayer = bitmapLayer
            }
            contentLayer.vectorLayer = SVGAVectorLayer(frames: sprite.frames)

            if sprite.imageKey.hasSuffix(".matte") {
                // matte 图层:作为宿主层的 mask
                let hostLayer = CALayer()
                hostLayer.mask = contentLayer
                tempHostLayers[sprite.imageKey] = hostLayer
            } else if let matteKey = sprite.matteKey, !matteKey.isEmpty,
                      let hostLayer = tempHostLayers[matteKey] {
                // 被遮罩图层:挂到对应 matte 宿主层
                hostLayer.addSublayer(contentLayer)
                if idx > 0 && sprite.matteKey != movie.sprites[idx - 1].matteKey {
                    drawLayer.addSublayer(hostLayer)
                }
            } else {
                drawLayer.addSublayer(contentLayer)
            }
        }
        return (drawLayer, tempContentLayers)
    }
}
