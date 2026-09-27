import AppKit
import IsaacPetCore


/// Loads the bundled card icons from the Cards folder. Icons are the in-game
/// HUD card sprites (14×18) so they stay pixel-crisp under nearest filtering.
@MainActor
final class CardImageCatalog {
    enum CardImageError: LocalizedError {
        case missingResource(TarotCard)
        case invalidImage(TarotCard)

        var errorDescription: String? {
            switch self {
            case let .missingResource(card): "找不到卡牌图标 \(card.iconResource).png。"
            case let .invalidImage(card): "无法解码卡牌图标 \(card.iconResource).png。"
            }
        }
    }

    private var cache: [String: SpriteFrame] = [:]

    func frame(for card: TarotCard, bundle: Bundle = .main) throws -> SpriteFrame {
        if let cached = cache[card.id] { return cached }
        guard let url = bundle.url(
            forResource: card.iconResource,
            withExtension: "png",
            subdirectory: "Cards"
        ) else {
            throw CardImageError.missingResource(card)
        }
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CardImageError.invalidImage(card)
        }
        let frame = SpriteFrame(cgImage: cgImage)
        cache[card.id] = frame
        return frame
    }
}
