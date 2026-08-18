import AppKit
import Foundation
import IsaacPetCore

enum PetAppearanceID: String, CaseIterable {
    case isaac
    case magdalene
    case judas

    init?(roleID: AgentRoleID) {
        switch roleID {
        case .isaac: self = .isaac
        case .magdalene: self = .magdalene
        case .judas: self = .judas
        case .cain: return nil
        }
    }
}

struct PetAppearanceDefinition {
    let id: PetAppearanceID
    let displayName: String
    let spriteSheetResource: String
    let subdirectory: String?
}

enum PetAppearanceAvailability: Equatable {
    case available
    case missing
    case invalidDimensions(width: Int, height: Int)
    case undecodable

    var isAvailable: Bool {
        self == .available
    }

    var unavailableReason: String {
        switch self {
        case .available: return ""
        case .missing: return "角色图集尚未安装；生成并通过 QA 后会自动启用。"
        case let .invalidDimensions(width, height): return "角色图集尺寸错误：\(width)×\(height)，应为 1536×2288。"
        case .undecodable: return "角色图集无法解码。"
        }
    }
}

enum PetAppearanceCatalog {
    static let definitions: [PetAppearanceDefinition] = [
        PetAppearanceDefinition(
            id: .isaac,
            displayName: "Isaac（默认）",
            spriteSheetResource: "spritesheet",
            subdirectory: nil
        ),
        PetAppearanceDefinition(
            id: .magdalene,
            displayName: "Magdalene",
            spriteSheetResource: "magdalene-spritesheet",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .judas,
            displayName: "Judas",
            spriteSheetResource: "judas-spritesheet",
            subdirectory: "Agents"
        ),
    ]

    static func definition(for id: PetAppearanceID) -> PetAppearanceDefinition {
        definitions.first(where: { $0.id == id })!
    }

    static func availability(
        _ id: PetAppearanceID,
        bundle: Bundle = .main
    ) -> PetAppearanceAvailability {
        let definition = definition(for: id)
        guard let url = bundle.url(
            forResource: definition.spriteSheetResource,
            withExtension: "webp",
            subdirectory: definition.subdirectory
        ) else { return .missing }
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .undecodable
        }
        let expectedWidth = AnimationCatalog.cellWidth * AnimationCatalog.columns
        let expectedHeight = AnimationCatalog.cellHeight * AnimationCatalog.rows
        guard cgImage.width == expectedWidth, cgImage.height == expectedHeight else {
            return .invalidDimensions(width: cgImage.width, height: cgImage.height)
        }
        return .available
    }

    static func isAvailable(_ id: PetAppearanceID, bundle: Bundle = .main) -> Bool {
        availability(id, bundle: bundle).isAvailable
    }
}

enum AgentPortraitCatalog {
    static func image(for roleID: AgentRoleID, bundle: Bundle = .main) -> NSImage? {
        switch roleID {
        case .magdalene:
            guard let url = bundle.url(
                forResource: "magdalene-portrait",
                withExtension: "png",
                subdirectory: "Agents"
            ) else { return nil }
            return NSImage(contentsOf: url)
        case .isaac, .cain, .judas:
            return nil
        }
    }
}
