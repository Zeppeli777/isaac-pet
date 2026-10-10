import AppKit
import Foundation
import IsaacPetCore

enum PetAppearanceID: String, CaseIterable {
    case isaac
    case magdalene
    case cain
    case judas
    case blueBaby
    case eve
    case samson
    case azazel
    case lazarus
    case eden
    case theLost
    case lilith
    case keeper
    case apollyon
    case theForgotten
    case bethany
    case jacobEsau
}

struct PetAppearanceDefinition {
    let id: PetAppearanceID
    let displayName: String
    /// Short name used in conversation UI and the pet's persona prompt.
    let personaName: String
    let spriteSheetResource: String
    /// Helper atlases a role derives for itself. `nil` falls back to the Isaac ones.
    let shootingAtlasResource: String?
    let verticalWalkingResource: String?
    let raisingAtlasResource: String?
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
            personaName: "Isaac",
            spriteSheetResource: "spritesheet",
            shootingAtlasResource: nil,
            verticalWalkingResource: nil,
            raisingAtlasResource: nil,
            subdirectory: nil
        ),
        PetAppearanceDefinition(
            id: .magdalene,
            displayName: "Magdalene",
            personaName: "Magdalene",
            spriteSheetResource: "magdalene-spritesheet",
            shootingAtlasResource: "magdalene-shooting-atlas",
            verticalWalkingResource: "magdalene-walking-vertical-atlas",
            raisingAtlasResource: "magdalene-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .cain,
            displayName: "Cain",
            personaName: "Cain",
            spriteSheetResource: "cain-spritesheet",
            shootingAtlasResource: "cain-shooting-atlas",
            verticalWalkingResource: "cain-walking-vertical-atlas",
            raisingAtlasResource: "cain-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .judas,
            displayName: "Judas",
            personaName: "Judas",
            spriteSheetResource: "judas-spritesheet",
            shootingAtlasResource: "judas-shooting-atlas",
            verticalWalkingResource: "judas-walking-vertical-atlas",
            raisingAtlasResource: "judas-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .blueBaby,
            displayName: "Blue Baby（???）",
            personaName: "Blue Baby",
            spriteSheetResource: "bluebaby-spritesheet",
            shootingAtlasResource: "bluebaby-shooting-atlas",
            verticalWalkingResource: "bluebaby-walking-vertical-atlas",
            raisingAtlasResource: "bluebaby-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .eve,
            displayName: "Eve",
            personaName: "Eve",
            spriteSheetResource: "eve-spritesheet",
            shootingAtlasResource: "eve-shooting-atlas",
            verticalWalkingResource: "eve-walking-vertical-atlas",
            raisingAtlasResource: "eve-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .samson,
            displayName: "Samson",
            personaName: "Samson",
            spriteSheetResource: "samson-spritesheet",
            shootingAtlasResource: "samson-shooting-atlas",
            verticalWalkingResource: "samson-walking-vertical-atlas",
            raisingAtlasResource: "samson-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .azazel,
            displayName: "Azazel",
            personaName: "Azazel",
            spriteSheetResource: "azazel-spritesheet",
            shootingAtlasResource: "azazel-shooting-atlas",
            verticalWalkingResource: "azazel-walking-vertical-atlas",
            raisingAtlasResource: "azazel-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .lazarus,
            displayName: "Lazarus",
            personaName: "Lazarus",
            spriteSheetResource: "lazarus-spritesheet",
            shootingAtlasResource: "lazarus-shooting-atlas",
            verticalWalkingResource: "lazarus-walking-vertical-atlas",
            raisingAtlasResource: "lazarus-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .eden,
            displayName: "Eden",
            personaName: "Eden",
            spriteSheetResource: "eden-spritesheet",
            shootingAtlasResource: "eden-shooting-atlas",
            verticalWalkingResource: "eden-walking-vertical-atlas",
            raisingAtlasResource: "eden-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .theLost,
            displayName: "The Lost",
            personaName: "The Lost",
            spriteSheetResource: "thelost-spritesheet",
            shootingAtlasResource: "thelost-shooting-atlas",
            verticalWalkingResource: "thelost-walking-vertical-atlas",
            raisingAtlasResource: "thelost-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .lilith,
            displayName: "Lilith",
            personaName: "Lilith",
            spriteSheetResource: "lilith-spritesheet",
            shootingAtlasResource: "lilith-shooting-atlas",
            verticalWalkingResource: "lilith-walking-vertical-atlas",
            raisingAtlasResource: "lilith-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .keeper,
            displayName: "Keeper",
            personaName: "Keeper",
            spriteSheetResource: "keeper-spritesheet",
            shootingAtlasResource: "keeper-shooting-atlas",
            verticalWalkingResource: "keeper-walking-vertical-atlas",
            raisingAtlasResource: "keeper-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .apollyon,
            displayName: "Apollyon",
            personaName: "Apollyon",
            spriteSheetResource: "apollyon-spritesheet",
            shootingAtlasResource: "apollyon-shooting-atlas",
            verticalWalkingResource: "apollyon-walking-vertical-atlas",
            raisingAtlasResource: "apollyon-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .theForgotten,
            displayName: "The Forgotten",
            personaName: "The Forgotten",
            spriteSheetResource: "theforgotten-spritesheet",
            shootingAtlasResource: "theforgotten-shooting-atlas",
            verticalWalkingResource: "theforgotten-walking-vertical-atlas",
            raisingAtlasResource: "theforgotten-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .bethany,
            displayName: "Bethany",
            personaName: "Bethany",
            spriteSheetResource: "bethany-spritesheet",
            shootingAtlasResource: "bethany-shooting-atlas",
            verticalWalkingResource: "bethany-walking-vertical-atlas",
            raisingAtlasResource: "bethany-raising-atlas",
            subdirectory: "Agents"
        ),
        PetAppearanceDefinition(
            id: .jacobEsau,
            displayName: "Jacob & Esau",
            personaName: "Jacob & Esau",
            spriteSheetResource: "jacobesau-spritesheet",
            shootingAtlasResource: "jacobesau-shooting-atlas",
            verticalWalkingResource: "jacobesau-walking-vertical-atlas",
            raisingAtlasResource: "jacobesau-raising-atlas",
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
