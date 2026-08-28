//
//  SVGAPlayerView.swift
//  SVGACore
//
//  macOS 播放视图(NSView):承载 CALayer 树,以 Timer 步进帧实现动画播放。
//  对应官方 SVGAPlayer(UIView)在 macOS 上的移植。
//

import AppKit
import QuartzCore

public final class SVGAPlayerView: NSView {

    public enum ContentMode {
        case scaleAspectFit
        case scaleAspectFill
        case stretch
    }

    /// 显示模式:.fit 等比适应视口;.native 按原始分辨率 × zoomScale 渲染。
    public enum DisplayMode {
        case fit
        case native
    }

    public var contentMode: ContentMode = .scaleAspectFit
    public var displayMode: DisplayMode = .fit
    /// >0 表示播放 loops 次后停止(0 = 无限循环)。
    public var loops: Int = 0

    /// 原生尺寸模式的缩放倍率(1x = 原始像素大小)。
    public private(set) var zoomScale: CGFloat = 1.0

    public private(set) var movie: SVGAMovie?
    public private(set) var currentFrame: Int = 0
    public private(set) var isPlaying: Bool = false

    private var drawLayer: CALayer?
    private var contentLayers: [SVGAContentLayer] = []
    private var timer: Timer?
    private var loopCount: Int = 0
    /// applyResize 去重缓存:避免布局反复触发时重复设置图层(引发 CA 提交反馈)
    private var lastAppliedTransform: CGAffineTransform = .identity
    private var lastAppliedPosition: CGPoint = .zero

    /// 返回当前帧内容,供宿主读取(可选)。
    public var onFrameChanged: ((Int) -> Void)?

    public override var isFlipped: Bool { true }

    // MARK: - 生命周期

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimation()
        }
    }

    public override func layout() {
        super.layout()
        applyResize()
    }

    // MARK: - 加载与播放控制

    public func load(movie: SVGAMovie) {
        stopAnimation()
        self.movie = movie
        currentFrame = 0
        loopCount = 0
        rebuild()
    }

    private func rebuild() {
        guard let movie = movie else { return }
        let images = movie.images.compactMapValues { SVGAMovieRenderer.cgImage(from: $0) }
        let built = SVGALayerTree.build(movie: movie, images: images)
        drawLayer = built.drawLayer
        contentLayers = built.contentLayers
        // 图层已重建,失效去重缓存
        lastAppliedTransform = .identity
        lastAppliedPosition = .zero
        if let layer = layer {
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            layer.addSublayer(built.drawLayer)
        }
        applyResize()
        stepToFrame(0)
    }

    public func startAnimation() {
        guard let movie = movie, movie.frames > 1, movie.fps > 0 else { return }
        stopAnimation()
        isPlaying = true
        loopCount = 0
        // 定时器间隔直接用 1/fps:避免整数分频导致 24fps 被播成 30fps 等速度误差
        let interval = 1.0 / Double(movie.fps)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = interval * 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopAnimation() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }

    /// 跳到指定帧(不播放)。
    public func stepToFrame(_ frame: Int) {
        stepToFrame(frame, notify: true)
    }

    /// 内部步进:notify 为 false 时不触发 onFrameChanged,避免 UI 反馈循环。
    private func stepToFrame(_ frame: Int, notify: Bool) {
        guard let movie = movie, frame >= 0, frame < movie.frames else { return }
        currentFrame = frame
        CATransaction.setDisableActions(true)
        for layer in contentLayers {
            layer.stepToFrame(frame)
        }
        CATransaction.setDisableActions(false)
        if notify {
            onFrameChanged?(frame)
        }
    }

    private func tick() {
        guard let movie = movie else { return }
        // Timer 间隔已等于 1/fps,每次 tick 推进一帧
        currentFrame += 1
        if currentFrame >= movie.frames {
            currentFrame = 0
            loopCount += 1
            if loops > 0 && loopCount >= loops {
                stopAnimation()
                return
            }
        }
        stepToFrame(currentFrame)
    }

    // MARK: - 缩放控制

    /// 设置原生模式的缩放倍率(1x–5x),支持平滑过渡动画。
    public func setZoomScale(_ scale: CGFloat, animated: Bool = true) {
        let clamped = min(max(scale, 0.25), 8.0)
        zoomScale = clamped
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.35 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        applyResize()
        CATransaction.commit()
    }

    // MARK: - 图层交互

    /// 高亮指定 imageKey 的图层(蓝色边框);传 nil 清除高亮。
    public func setHighlightedLayer(imageKey: String?) {
        for layer in contentLayers {
            if let key = imageKey, layer.imageKey == key {
                layer.borderColor = NSColor.systemBlue.cgColor
                layer.borderWidth = 2
            } else {
                layer.borderColor = nil
                layer.borderWidth = 0
            }
        }
    }

    /// 设置用户手动隐藏的图层集合(立即生效,不触发帧回调)。
    public func setLayerHidden(_ hiddenKeys: Set<String>) {
        for layer in contentLayers {
            layer.isUserHidden = hiddenKeys.contains(layer.imageKey)
        }
        // 立即刷新当前帧,使显隐变化马上可见(无需等到下一帧);
        // notify: false 防止 stepToFrame 的回调引发 UI 反馈循环
        stepToFrame(currentFrame, notify: false)
    }

    // MARK: - 尺寸适配

    private func applyResize() {
        guard let drawLayer = drawLayer, let movie = movie,
              bounds.width > 0, bounds.height > 0,
              movie.videoSize.width > 0, movie.videoSize.height > 0 else { return }
        let video = movie.videoSize
        var transform: CGAffineTransform
        switch displayMode {
        case .fit:
            switch contentMode {
            case .scaleAspectFit:
                let s = min(bounds.width / video.width, bounds.height / video.height)
                transform = CGAffineTransform(scaleX: s, y: s)
            case .scaleAspectFill:
                let s = max(bounds.width / video.width, bounds.height / video.height)
                transform = CGAffineTransform(scaleX: s, y: s)
            case .stretch:
                transform = CGAffineTransform(scaleX: bounds.width / video.width,
                                              y: bounds.height / video.height)
            }
        case .native:
            // 原始分辨率 × zoomScale,围绕画布中心无损缩放
            transform = CGAffineTransform(scaleX: zoomScale, y: zoomScale)
        }
        let position = CGPoint(x: bounds.midX, y: bounds.midY)
        // 值未变化时跳过,避免每帧布局重复提交图层变更
        guard transform != lastAppliedTransform || position != lastAppliedPosition else { return }
        lastAppliedTransform = transform
        lastAppliedPosition = position
        drawLayer.setAffineTransform(transform)
        drawLayer.position = position
    }
}
