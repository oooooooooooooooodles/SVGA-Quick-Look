//
//  PreviewViewController.swift
//  SVGA Quick Look Preview Extension
//
//  空格键快速预览(macOS 经典视图控制器式):以原生 NSView 实时播放 SVGA 动画。
//

import Cocoa
import QuartzCore
import QuickLookUI

class PreviewViewController: NSViewController, QLPreviewingController {

    private var playerView: SVGAPlayerView?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1).cgColor
    }

    /// 文件预览入口:解析并开始播放。
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let data = try Data(contentsOf: url)
                let movie = try SVGAMovieParser.parse(data: data)
                DispatchQueue.main.async {
                    self?.show(movie: movie)
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    handler(error)
                }
            }
        }
    }

    /// Spotlight 搜索项预览:不支持,直接返回错误。
    func preparePreviewOfSearchableItem(identifier: String,
                                        queryString: String?,
                                        completionHandler handler: @escaping (Error?) -> Void) {
        handler(NSError(domain: "SVGAQuickLook", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "不支持 Spotlight 搜索项预览"]))
    }

    private func show(movie: SVGAMovie) {
        let player = SVGAPlayerView(frame: view.bounds)
        player.autoresizingMask = [.width, .height]
        player.contentMode = .scaleAspectFit
        player.load(movie: movie)
        player.startAnimation()

        playerView?.removeFromSuperview()
        playerView = player
        view.addSubview(player)

        // 按画布比例给出合适的预览尺寸
        let maxDim: CGFloat = 720
        let scale = min(1, maxDim / max(movie.videoSize.width, movie.videoSize.height))
        let fitted = NSSize(width: max(200, movie.videoSize.width * scale),
                            height: max(200, movie.videoSize.height * scale))
        preferredContentSize = fitted
    }
}
