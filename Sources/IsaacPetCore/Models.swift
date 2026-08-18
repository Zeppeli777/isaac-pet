import CoreGraphics
import Foundation

public enum AnimationID: String, CaseIterable, Sendable {
    case idle
    case walkRight
    case walkLeft
    case wave
    case jump
    case cry
    case waiting
    case thumbsUp
    case observe
}

public struct AnimationSpec: Equatable, Sendable {
    public let row: Int
    public let frameCount: Int
    public let frameDuration: TimeInterval
    public let loops: Bool

    public init(row: Int, frameCount: Int, frameDuration: TimeInterval, loops: Bool) {
        self.row = row
        self.frameCount = frameCount
        self.frameDuration = frameDuration
        self.loops = loops
    }

    public var duration: TimeInterval {
        Double(frameCount) * frameDuration
    }

    public func frameIndex(elapsed: TimeInterval) -> Int {
        guard frameCount > 1 else { return 0 }
        let raw = max(0, Int(elapsed / frameDuration))
        return loops ? raw % frameCount : min(raw, frameCount - 1)
    }
}

public enum Direction8: Int, CaseIterable, Sendable {
    case up
    case upRight
    case right
    case downRight
    case down
    case downLeft
    case left
    case upLeft

    public static func from(deltaX: CGFloat, deltaY: CGFloat, deadZone: CGFloat = 40) -> Direction8? {
        guard hypot(deltaX, deltaY) >= deadZone else { return nil }
        let degrees = atan2(deltaY, deltaX) * 180 / .pi

        switch degrees {
        case -22.5..<22.5: return .right
        case 22.5..<67.5: return .upRight
        case 67.5..<112.5: return .up
        case 112.5..<157.5: return .upLeft
        case 157.5...180, -180..<(-157.5): return .left
        case -157.5..<(-112.5): return .downLeft
        case -112.5..<(-67.5): return .down
        default: return .downRight
        }
    }
}

public enum WalkingDirection: Sendable {
    case left
    case right
}

public enum VerticalWalkingDirection: Int, CaseIterable, Sendable {
    case down
    case up
}

public enum PlayWalkingDirection: Equatable, Sendable {
    case left
    case right
    case down
    case up

    public var verticalDirection: VerticalWalkingDirection? {
        switch self {
        case .down: return .down
        case .up: return .up
        case .left, .right: return nil
        }
    }
}

public enum PlayKey: UInt16, CaseIterable, Hashable, Sendable {
    case moveLeft = 0
    case moveDown = 1
    case moveRight = 2
    case moveUp = 13
    case shootLeft = 123
    case shootRight = 124
    case shootDown = 125
    case shootUp = 126
    case escape = 53
}

public enum PlayInput {
    public static func movementVector(for keys: Set<PlayKey>) -> CGVector {
        normalizedVector(
            x: axis(negative: .moveLeft, positive: .moveRight, keys: keys),
            y: axis(negative: .moveDown, positive: .moveUp, keys: keys)
        )
    }

    public static func firingDirection(for keys: Set<PlayKey>) -> Direction8? {
        let x = axis(negative: .shootLeft, positive: .shootRight, keys: keys)
        let y = axis(negative: .shootDown, positive: .shootUp, keys: keys)
        guard x != 0 || y != 0 else { return nil }
        return Direction8.from(deltaX: x, deltaY: y, deadZone: 0)
    }

    /// Choose one gait for a diagonal input. The dominant component wins; ties keep the
    /// familiar horizontal gait while Isaac still travels diagonally at normalized speed.
    public static func walkingDirection(for movement: CGVector) -> PlayWalkingDirection? {
        guard movement != .zero else { return nil }
        if abs(movement.dy) > abs(movement.dx) {
            return movement.dy > 0 ? .up : .down
        }
        return movement.dx > 0 ? .right : .left
    }

    public static func unitVector(for direction: Direction8) -> CGVector {
        switch direction {
        case .up: return CGVector(dx: 0, dy: 1)
        case .upRight: return normalizedVector(x: 1, y: 1)
        case .right: return CGVector(dx: 1, dy: 0)
        case .downRight: return normalizedVector(x: 1, y: -1)
        case .down: return CGVector(dx: 0, dy: -1)
        case .downLeft: return normalizedVector(x: -1, y: -1)
        case .left: return CGVector(dx: -1, dy: 0)
        case .upLeft: return normalizedVector(x: -1, y: 1)
        }
    }

    private static func axis(negative: PlayKey, positive: PlayKey, keys: Set<PlayKey>) -> CGFloat {
        (keys.contains(positive) ? 1 : 0) - (keys.contains(negative) ? 1 : 0)
    }

    private static func normalizedVector(x: CGFloat, y: CGFloat) -> CGVector {
        let length = hypot(x, y)
        guard length > 0 else { return .zero }
        return CGVector(dx: x / length, dy: y / length)
    }
}

public enum PetState: Equatable, Sendable {
    case idle
    case walking(WalkingDirection)
    case tracking(Direction8)
    case action(AnimationID)
    case playing(Direction8, moving: Bool)
    case dragging

    public var priority: Int {
        switch self {
        case .idle: 0
        case .tracking: 1
        case .walking: 2
        case .action: 3
        case .playing: 4
        case .dragging: 5
        }
    }
}

public enum AnimationCatalog {
    public static let cellWidth = 192
    public static let cellHeight = 208
    public static let columns = 8
    public static let rows = 11
    public static let verticalWalkingColumns = 4
    public static let verticalWalkingRows = 2

    public static let specs: [AnimationID: AnimationSpec] = [
        .idle: AnimationSpec(row: 0, frameCount: 7, frameDuration: 0.18, loops: true),
        .walkRight: AnimationSpec(row: 1, frameCount: 8, frameDuration: 0.09, loops: true),
        .walkLeft: AnimationSpec(row: 2, frameCount: 8, frameDuration: 0.09, loops: true),
        .wave: AnimationSpec(row: 3, frameCount: 4, frameDuration: 0.13, loops: false),
        .jump: AnimationSpec(row: 4, frameCount: 5, frameDuration: 0.12, loops: false),
        .cry: AnimationSpec(row: 5, frameCount: 8, frameDuration: 0.14, loops: false),
        .waiting: AnimationSpec(row: 6, frameCount: 6, frameDuration: 0.16, loops: false),
        .thumbsUp: AnimationSpec(row: 7, frameCount: 6, frameDuration: 0.15, loops: false),
        .observe: AnimationSpec(row: 8, frameCount: 6, frameDuration: 0.15, loops: false),
    ]

    public static let verticalWalkingSpecs: [VerticalWalkingDirection: AnimationSpec] = [
        .down: AnimationSpec(row: 0, frameCount: 4, frameDuration: 0.09, loops: true),
        .up: AnimationSpec(row: 1, frameCount: 4, frameDuration: 0.09, loops: true),
    ]

    public static func spec(for animation: AnimationID) -> AnimationSpec {
        guard let spec = specs[animation] else {
            preconditionFailure("Missing animation specification for \(animation.rawValue)")
        }
        return spec
    }

    public static func verticalWalkingSpec(for direction: VerticalWalkingDirection) -> AnimationSpec {
        guard let spec = verticalWalkingSpecs[direction] else {
            preconditionFailure("Missing vertical walking specification for \(direction)")
        }
        return spec
    }

    public static func atlasCell(for direction: Direction8) -> (row: Int, column: Int) {
        switch direction {
        case .up: return (9, 0)
        case .upRight: return (9, 2)
        case .right: return (9, 4)
        case .downRight: return (9, 6)
        case .down: return (10, 0)
        case .downLeft: return (10, 2)
        case .left: return (10, 4)
        case .upLeft: return (10, 6)
        }
    }

    public static func shootingColumn(for direction: Direction8) -> Int {
        switch direction {
        case .up: return 0
        case .upRight, .right, .downRight: return 1
        case .down: return 2
        case .downLeft, .left, .upLeft: return 3
        }
    }

    public static func sourceRect(row: Int, column: Int) -> CGRect {
        CGRect(
            x: column * cellWidth,
            y: row * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
    }
}

public struct PetSettings: Equatable, Sendable {
    public var scale: CGFloat
    public var roamingEnabled: Bool
    public var screenIdentifier: String?
    public var horizontalPosition: CGFloat

    public init(
        scale: CGFloat = 1,
        roamingEnabled: Bool = true,
        screenIdentifier: String? = nil,
        horizontalPosition: CGFloat = 0.82
    ) {
        self.scale = Self.validScale(scale)
        self.roamingEnabled = roamingEnabled
        self.screenIdentifier = screenIdentifier
        self.horizontalPosition = min(max(horizontalPosition, 0), 1)
    }

    public static func validScale(_ value: CGFloat) -> CGFloat {
        let choices: [CGFloat] = [0.75, 1, 1.25]
        return choices.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1
    }
}

public enum SpeechBubblePolicy {
    public static let maximumCharacters = 80

    public static func normalized(_ rawValue: String) -> String? {
        let collapsed = rawValue
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maximumCharacters else { return collapsed }
        return String(collapsed.prefix(maximumCharacters - 1)) + "…"
    }

    public static func displayDuration(for message: String) -> TimeInterval {
        min(max(3 + Double(message.count) * 0.055, 3), 8)
    }
}

public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var dueAt: Date?
    public var completedAt: Date?
    public var remindedAt: Date?
    public var externalSource: TodoExternalSource?

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        dueAt: Date? = nil,
        completedAt: Date? = nil,
        remindedAt: Date? = nil,
        externalSource: TodoExternalSource? = nil
    ) {
        self.id = id
        self.title = TodoPolicy.normalizedTitle(title) ?? ""
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.remindedAt = remindedAt
        self.externalSource = externalSource
    }

    public var isCompleted: Bool { completedAt != nil }
}

public struct TodoExternalSource: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case appleReminders
        case notion
    }

    public let kind: Kind
    public let itemIdentifier: String
    public var containerIdentifier: String?
    public var containerTitle: String?
    public var lastSyncedAt: Date

    public init(
        kind: Kind,
        itemIdentifier: String,
        containerIdentifier: String? = nil,
        containerTitle: String? = nil,
        lastSyncedAt: Date = Date()
    ) {
        self.kind = kind
        self.itemIdentifier = itemIdentifier
        self.containerIdentifier = containerIdentifier
        self.containerTitle = containerTitle
        self.lastSyncedAt = lastSyncedAt
    }
}

public struct ExternalTodoRecord: Equatable, Sendable {
    public let source: TodoExternalSource
    public let title: String
    public let dueAt: Date?
    public let completedAt: Date?

    public init(
        source: TodoExternalSource,
        title: String,
        dueAt: Date?,
        completedAt: Date?
    ) {
        self.source = source
        self.title = title
        self.dueAt = dueAt
        self.completedAt = completedAt
    }
}

public struct TodoImportSummary: Equatable, Sendable {
    public let inserted: Int
    public let updated: Int
    public let skipped: Int

    public init(inserted: Int, updated: Int, skipped: Int) {
        self.inserted = inserted
        self.updated = updated
        self.skipped = skipped
    }
}

public enum TodoPolicy {
    public static let maximumTitleCharacters = 120

    public static func normalizedTitle(_ rawValue: String) -> String? {
        let collapsed = rawValue
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maximumTitleCharacters else { return collapsed }
        return String(collapsed.prefix(maximumTitleCharacters - 1)) + "…"
    }

    public static func sorted(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            switch (lhs.dueAt, rhs.dueAt) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    public static func pending(_ items: [TodoItem]) -> [TodoItem] {
        sorted(items.filter { !$0.isCompleted })
    }

    public static func nextPending(in items: [TodoItem]) -> TodoItem? {
        pending(items).first
    }

    public static func dueForDelivery(in items: [TodoItem], at date: Date) -> [TodoItem] {
        sorted(items.filter { item in
            !item.isCompleted
                && item.remindedAt == nil
                && item.dueAt.map { $0 <= date } == true
        })
    }

    public static func merging(
        _ records: [ExternalTodoRecord],
        into items: [TodoItem],
        now: Date = Date()
    ) -> (items: [TodoItem], summary: TodoImportSummary) {
        var mergedItems = items
        var inserted = 0
        var updated = 0
        var skipped = 0

        for record in records {
            guard let title = normalizedTitle(record.title), !record.source.itemIdentifier.isEmpty else {
                skipped += 1
                continue
            }
            if let index = mergedItems.firstIndex(where: {
                $0.externalSource?.kind == record.source.kind
                    && $0.externalSource?.itemIdentifier == record.source.itemIdentifier
            }) {
                var item = mergedItems[index]
                let oldDueAt = item.dueAt
                let wasCompleted = item.isCompleted
                item.title = title
                item.dueAt = record.dueAt
                item.completedAt = record.completedAt
                var source = record.source
                source.lastSyncedAt = now
                item.externalSource = source
                // A reopened source task must be eligible for a new delivery even when
                // its deadline did not change. The same rule applies when its deadline
                // moves, so the pending notification can be scheduled for the new time.
                if record.completedAt == nil, wasCompleted || oldDueAt != record.dueAt {
                    item.remindedAt = nil
                }
                mergedItems[index] = item
                updated += 1
            } else {
                var source = record.source
                source.lastSyncedAt = now
                mergedItems.append(TodoItem(
                    title: title,
                    createdAt: now,
                    dueAt: record.dueAt,
                    completedAt: record.completedAt,
                    externalSource: source
                ))
                inserted += 1
            }
        }

        return (
            sorted(mergedItems),
            TodoImportSummary(inserted: inserted, updated: updated, skipped: skipped)
        )
    }
}

public enum TodoFileCodec {
    public static func encode(_ items: [TodoItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(TodoPolicy.sorted(items))
    }

    public static func decode(_ data: Data) throws -> [TodoItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return TodoPolicy.sorted(try decoder.decode([TodoItem].self, from: data))
    }
}

public struct ScreenBounds: Equatable, Sendable {
    public let rect: CGRect

    public init(rect: CGRect) {
        self.rect = rect
    }

    public func clampedOrigin(_ origin: CGPoint, petSize: CGSize, bottomPadding: CGFloat = 4) -> CGPoint {
        let maxX = max(rect.minX, rect.maxX - petSize.width)
        return CGPoint(
            x: min(max(origin.x, rect.minX), maxX),
            y: rect.minY + bottomPadding
        )
    }

    public func clampedFreeOrigin(_ origin: CGPoint, petSize: CGSize, padding: CGFloat = 4) -> CGPoint {
        let minX = rect.minX + padding
        let maxX = max(minX, rect.maxX - petSize.width - padding)
        let minY = rect.minY + padding
        let maxY = max(minY, rect.maxY - petSize.height - padding)
        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    public func origin(horizontalPosition: CGFloat, petSize: CGSize, bottomPadding: CGFloat = 4) -> CGPoint {
        let availableWidth = max(0, rect.width - petSize.width)
        return CGPoint(
            x: rect.minX + availableWidth * min(max(horizontalPosition, 0), 1),
            y: rect.minY + bottomPadding
        )
    }

    public func horizontalPosition(for origin: CGPoint, petSize: CGSize) -> CGFloat {
        let availableWidth = rect.width - petSize.width
        guard availableWidth > 0 else { return 0 }
        return min(max((origin.x - rect.minX) / availableWidth, 0), 1)
    }
}
