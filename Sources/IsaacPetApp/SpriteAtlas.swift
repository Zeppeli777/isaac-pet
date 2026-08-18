import AppKit
import IsaacPetCore

@MainActor
final class SpriteFrame {
    let cgImage: CGImage
    let image: NSImage
    let width: Int
    let height: Int
    private let bitmap: NSBitmapImageRep

    init(cgImage: CGImage) {
        self.cgImage = cgImage
        width = cgImage.width
        height = cgImage.height
        image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        bitmap = NSBitmapImageRep(cgImage: cgImage)
    }

    func isOpaque(at point: NSPoint, in bounds: NSRect, threshold: CGFloat = 0.08) -> Bool {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return false }
        let x = min(width - 1, max(0, Int(point.x / bounds.width * CGFloat(width))))
        let topY = min(height - 1, max(0, Int(point.y / bounds.height * CGFloat(height))))
        let bitmapY = height - 1 - topY
        return (bitmap.colorAt(x: x, y: bitmapY)?.alphaComponent ?? 0) > threshold
    }
}

@MainActor
final class SpriteAtlas {
    enum AtlasError: LocalizedError {
        case missingResource(String)
        case invalidImage
        case missingTearResource
        case invalidTearImage
        case missingShootingResource
        case invalidShootingImage
        case invalidShootingDimensions(Int, Int)
        case missingVerticalWalkingResource
        case invalidVerticalWalkingImage
        case invalidVerticalWalkingDimensions(Int, Int)
        case invalidDimensions(Int, Int)
        case cropFailed(Int, Int)
        case shootingCropFailed(Int)
        case verticalWalkingCropFailed(Int, Int)

        var errorDescription: String? {
            switch self {
            case let .missingResource(name): "找不到 \(name).webp。"
            case .invalidImage: "无法解码 Isaac 动画图集。"
            case .missingTearResource: "找不到 IsaacTear.png。"
            case .invalidTearImage: "无法解码 Isaac 泪弹素材。"
            case .missingShootingResource: "找不到 shooting-atlas.webp。"
            case .invalidShootingImage: "无法解码 Isaac 射击姿态。"
            case let .invalidShootingDimensions(width, height): "射击姿态尺寸错误：\(width)×\(height)。"
            case .missingVerticalWalkingResource: "找不到 walking-vertical-atlas.webp。"
            case .invalidVerticalWalkingImage: "无法解码 Isaac 上下行走姿态。"
            case let .invalidVerticalWalkingDimensions(width, height): "上下行走姿态尺寸错误：\(width)×\(height)。"
            case let .invalidDimensions(width, height): "动画图集尺寸错误：\(width)×\(height)。"
            case let .cropFailed(row, column): "无法读取动画单元格 \(row),\(column)。"
            case let .shootingCropFailed(column): "无法读取射击姿态 \(column)。"
            case let .verticalWalkingCropFailed(row, column): "无法读取上下行走姿态 \(row),\(column)。"
            }
        }
    }

    private struct Cell: Hashable {
        let row: Int
        let column: Int
    }

    private let source: CGImage
    private let shootingSource: CGImage
    private let verticalWalkingSource: CGImage
    private let bundle: Bundle
    private var cache: [Cell: SpriteFrame] = [:]
    private var shootingCache: [Int: SpriteFrame] = [:]
    private var verticalWalkingCache: [Cell: SpriteFrame] = [:]
    private var cachedTear: SpriteFrame?

    init(
        bundle: Bundle = .main,
        spriteSheetResource: String = "spritesheet",
        spriteSheetSubdirectory: String? = nil
    ) throws {
        guard let url = bundle.url(
            forResource: spriteSheetResource,
            withExtension: "webp",
            subdirectory: spriteSheetSubdirectory
        ) else {
            throw AtlasError.missingResource(spriteSheetResource)
        }
        guard let image = NSImage(contentsOf: url),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AtlasError.invalidImage
        }
        let expectedWidth = AnimationCatalog.cellWidth * AnimationCatalog.columns
        let expectedHeight = AnimationCatalog.cellHeight * AnimationCatalog.rows
        guard source.width == expectedWidth, source.height == expectedHeight else {
            throw AtlasError.invalidDimensions(source.width, source.height)
        }
        guard let shootingURL = bundle.url(forResource: "shooting-atlas", withExtension: "webp") else {
            throw AtlasError.missingShootingResource
        }
        guard let shootingImage = NSImage(contentsOf: shootingURL),
              let shootingSource = shootingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AtlasError.invalidShootingImage
        }
        let expectedShootingWidth = AnimationCatalog.cellWidth * 4
        guard shootingSource.width == expectedShootingWidth,
              shootingSource.height == AnimationCatalog.cellHeight else {
            throw AtlasError.invalidShootingDimensions(shootingSource.width, shootingSource.height)
        }
        guard let verticalWalkingURL = bundle.url(forResource: "walking-vertical-atlas", withExtension: "webp") else {
            throw AtlasError.missingVerticalWalkingResource
        }
        guard let verticalWalkingImage = NSImage(contentsOf: verticalWalkingURL),
              let verticalWalkingSource = verticalWalkingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AtlasError.invalidVerticalWalkingImage
        }
        let expectedVerticalWalkingWidth = AnimationCatalog.cellWidth * AnimationCatalog.verticalWalkingColumns
        let expectedVerticalWalkingHeight = AnimationCatalog.cellHeight * AnimationCatalog.verticalWalkingRows
        guard verticalWalkingSource.width == expectedVerticalWalkingWidth,
              verticalWalkingSource.height == expectedVerticalWalkingHeight else {
            throw AtlasError.invalidVerticalWalkingDimensions(verticalWalkingSource.width, verticalWalkingSource.height)
        }
        self.source = source
        self.shootingSource = shootingSource
        self.verticalWalkingSource = verticalWalkingSource
        self.bundle = bundle
    }

    func frame(animation: AnimationID, index: Int) throws -> SpriteFrame {
        let spec = AnimationCatalog.spec(for: animation)
        return try frame(row: spec.row, column: min(max(index, 0), spec.frameCount - 1))
    }

    func frame(direction: Direction8) throws -> SpriteFrame {
        let cell = AnimationCatalog.atlasCell(for: direction)
        return try frame(row: cell.row, column: cell.column)
    }

    func frame(shooting direction: Direction8) throws -> SpriteFrame {
        let column = AnimationCatalog.shootingColumn(for: direction)
        if let cached = shootingCache[column] { return cached }
        let rect = CGRect(
            x: column * AnimationCatalog.cellWidth,
            y: 0,
            width: AnimationCatalog.cellWidth,
            height: AnimationCatalog.cellHeight
        )
        guard let crop = shootingSource.cropping(to: rect) else {
            throw AtlasError.shootingCropFailed(column)
        }
        let frame = SpriteFrame(cgImage: crop)
        shootingCache[column] = frame
        return frame
    }

    func frame(verticalWalking direction: VerticalWalkingDirection, index: Int) throws -> SpriteFrame {
        let spec = AnimationCatalog.verticalWalkingSpec(for: direction)
        let column = min(max(index, 0), spec.frameCount - 1)
        let cell = Cell(row: spec.row, column: column)
        if let cached = verticalWalkingCache[cell] { return cached }
        let rect = CGRect(
            x: column * AnimationCatalog.cellWidth,
            y: spec.row * AnimationCatalog.cellHeight,
            width: AnimationCatalog.cellWidth,
            height: AnimationCatalog.cellHeight
        )
        guard let crop = verticalWalkingSource.cropping(to: rect) else {
            throw AtlasError.verticalWalkingCropFailed(spec.row, column)
        }
        let frame = SpriteFrame(cgImage: crop)
        verticalWalkingCache[cell] = frame
        return frame
    }

    func tearFrame() throws -> SpriteFrame {
        if let cachedTear { return cachedTear }
        guard let url = bundle.url(forResource: "IsaacTear", withExtension: "png") else {
            throw AtlasError.missingTearResource
        }
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AtlasError.invalidTearImage
        }
        let frame = SpriteFrame(cgImage: cgImage)
        cachedTear = frame
        return frame
    }

    private func frame(row: Int, column: Int) throws -> SpriteFrame {
        let cell = Cell(row: row, column: column)
        if let cached = cache[cell] { return cached }

        let rect = AnimationCatalog.sourceRect(row: row, column: column)
        guard let crop = source.cropping(to: rect) else {
            throw AtlasError.cropFailed(row, column)
        }
        let frame = SpriteFrame(cgImage: crop)
        cache[cell] = frame
        return frame
    }
}
