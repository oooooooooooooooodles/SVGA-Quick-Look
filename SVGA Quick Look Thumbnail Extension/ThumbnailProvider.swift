//
//  ThumbnailProvider.swift
//  SVGA Quick Look Thumbnail Extension
//
//  为 .svga 文件提供 Finder 缩略图。
//
//  关键点(踩坑总结):
//  - QLThumbnailReply(contextSize:) 的绘制上下文实际像素尺寸 = contextSize × request.scale;
//    因此图像必须按 maximumSize × scale 的矩形绘制,否则只覆盖画布一角(缩略图不撑满)。
//  - QL 缩略图上下文的图像绘制是翻转的,需先做 y 轴补偿,否则缩略图上下颠倒。
//

import Cocoa
import QuickLookThumbnailing

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let fileURL = request.fileURL

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: fileURL)
                let movie = try SVGAMovieParser.parse(data: data)
                let frame = SVGAMovieRenderer.thumbnailFrame(for: movie)

                // 按 backing scale 渲染像素图,并填满整个缩略图框(裁切溢出)
                let scale = max(1.0, request.scale)
                let pixelSize = CGSize(width: request.maximumSize.width * scale,
                                       height: request.maximumSize.height * scale)
                guard let image = SVGAMovieRenderer.renderFrame(movie: movie,
                                                                frame: frame,
                                                                size: pixelSize,
                                                                contentMode: .fill) else {
                    handler(nil, NSError(domain: "SVGAQuickLook", code: 1,
                                         userInfo: [NSLocalizedDescriptionKey: "无法渲染缩略图"]))
                    return
                }

                let reply = QLThumbnailReply(contextSize: request.maximumSize) { context -> Bool in
                    // 上下文实际为 maximumSize × scale 像素;QL 图像绘制带翻转,统一 y 轴补偿
                    context.saveGState()
                    context.translateBy(x: 0, y: pixelSize.height)
                    context.scaleBy(x: 1, y: -1)
                    context.draw(image, in: CGRect(origin: .zero, size: pixelSize))
                    context.restoreGState()
                    return true
                }
                handler(reply, nil)
            } catch {
                handler(nil, error)
            }
        }
    }
}
