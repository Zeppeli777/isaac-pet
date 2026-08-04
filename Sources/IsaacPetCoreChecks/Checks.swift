import CoreGraphics
import Foundation
import IsaacPetCore

@main
enum IsaacPetCoreChecks {
    @MainActor
    static func main() {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        check(AnimationCatalog.cellWidth * AnimationCatalog.columns == 1536, "atlas width contract")
        check(AnimationCatalog.cellHeight * AnimationCatalog.rows == 2288, "atlas height contract")
        check(AnimationCatalog.specs.count == AnimationID.allCases.count, "every animation has a spec")
        check(AnimationCatalog.spec(for: .walkRight).frameCount == 8, "walk frame count")
        check(AnimationCatalog.spec(for: .idle).frameCount == 7, "idle frame count")
        check(AnimationCatalog.verticalWalkingColumns == 4, "vertical walking columns")
        check(AnimationCatalog.verticalWalkingRows == 2, "vertical walking rows")
        check(AnimationCatalog.verticalWalkingSpecs.count == VerticalWalkingDirection.allCases.count, "vertical walking specifications")
        check(AnimationCatalog.verticalWalkingSpec(for: .down).row == 0, "down walking atlas row")
        check(AnimationCatalog.verticalWalkingSpec(for: .up).row == 1, "up walking atlas row")
        check(AnimationCatalog.verticalWalkingSpec(for: .down).frameCount == 4, "down walking frame count")
        check(AnimationCatalog.verticalWalkingSpec(for: .up).loops, "up walking loops")

        let looping = AnimationCatalog.spec(for: .walkRight)
        check(looping.frameIndex(elapsed: 0) == 0, "loop begins at frame zero")
        check(looping.frameIndex(elapsed: looping.duration) == 0, "loop wraps")
        let oneShot = AnimationCatalog.spec(for: .jump)
        check(oneShot.frameIndex(elapsed: oneShot.duration * 2) == oneShot.frameCount - 1, "one-shot clamps")

        check(Direction8.from(deltaX: 0, deltaY: 100) == .up, "up direction")
        check(Direction8.from(deltaX: 100, deltaY: 100) == .upRight, "up-right direction")
        check(Direction8.from(deltaX: 100, deltaY: 0) == .right, "right direction")
        check(Direction8.from(deltaX: 100, deltaY: -100) == .downRight, "down-right direction")
        check(Direction8.from(deltaX: 0, deltaY: -100) == .down, "down direction")
        check(Direction8.from(deltaX: -100, deltaY: -100) == .downLeft, "down-left direction")
        check(Direction8.from(deltaX: -100, deltaY: 0) == .left, "left direction")
        check(Direction8.from(deltaX: -100, deltaY: 100) == .upLeft, "up-left direction")
        check(Direction8.from(deltaX: 10, deltaY: 10) == nil, "pointer dead zone")

        let upCell = AnimationCatalog.atlasCell(for: .up)
        let rightCell = AnimationCatalog.atlasCell(for: .right)
        let downCell = AnimationCatalog.atlasCell(for: .down)
        let leftCell = AnimationCatalog.atlasCell(for: .left)
        check(upCell.row == 9 && upCell.column == 0, "up atlas cell")
        check(rightCell.row == 9 && rightCell.column == 4, "right atlas cell")
        check(downCell.row == 10 && downCell.column == 0, "down atlas cell")
        check(leftCell.row == 10 && leftCell.column == 4, "left atlas cell")
        check(AnimationCatalog.shootingColumn(for: .up) == 0, "up shooting pose")
        check(AnimationCatalog.shootingColumn(for: .right) == 1, "right shooting pose")
        check(AnimationCatalog.shootingColumn(for: .down) == 2, "down shooting pose")
        check(AnimationCatalog.shootingColumn(for: .left) == 3, "left shooting pose")
        check(AnimationCatalog.shootingColumn(for: .upRight) == 1, "diagonal shooting uses side pose")
        check(AnimationCatalog.shootingColumn(for: .downLeft) == 3, "mirrored diagonal shooting pose")

        check(PetState.dragging.priority > PetState.action(.jump).priority, "drag priority")
        check(PetState.dragging.priority > PetState.playing(.down, moving: true).priority, "play drag priority")
        check(PetState.playing(.down, moving: true).priority > PetState.action(.jump).priority, "play priority")
        check(PetState.action(.jump).priority > PetState.walking(.right).priority, "action priority")
        check(PetState.walking(.right).priority > PetState.tracking(.up).priority, "walking priority")
        check(PetState.tracking(.up).priority > PetState.idle.priority, "tracking priority")

        let screen = ScreenBounds(rect: CGRect(x: -100, y: 20, width: 1000, height: 700))
        let petSize = CGSize(width: 200, height: 220)
        check(
            screen.clampedOrigin(CGPoint(x: -500, y: 999), petSize: petSize) == CGPoint(x: -100, y: 24),
            "left screen clamp"
        )
        check(
            screen.clampedOrigin(CGPoint(x: 999, y: -50), petSize: petSize) == CGPoint(x: 700, y: 24),
            "right screen clamp"
        )
        let origin = screen.origin(horizontalPosition: 0.25, petSize: petSize)
        check(origin == CGPoint(x: 100, y: 24), "normalized position restore")
        check(abs(screen.horizontalPosition(for: origin, petSize: petSize) - 0.25) < 0.0001, "position persistence")
        check(
            screen.clampedFreeOrigin(CGPoint(x: -500, y: 999), petSize: petSize) == CGPoint(x: -96, y: 496),
            "free movement screen clamp"
        )

        check(PlayKey(rawValue: 13) == .moveUp, "W key mapping")
        check(PlayKey(rawValue: 123) == .shootLeft, "left arrow mapping")
        let diagonalMovement = PlayInput.movementVector(for: [.moveUp, .moveRight])
        check(abs(hypot(diagonalMovement.dx, diagonalMovement.dy) - 1) < 0.0001, "diagonal movement normalized")
        check(diagonalMovement.dx > 0 && diagonalMovement.dy > 0, "diagonal movement signs")
        check(PlayInput.movementVector(for: [.moveLeft, .moveRight]) == .zero, "opposite movement cancels")
        check(PlayInput.walkingDirection(for: CGVector(dx: 0, dy: 1)) == .up, "W uses up walking")
        check(PlayInput.walkingDirection(for: CGVector(dx: 0, dy: -1)) == .down, "S uses down walking")
        check(PlayInput.walkingDirection(for: CGVector(dx: -1, dy: 0)) == .left, "A keeps left walking")
        check(PlayInput.walkingDirection(for: CGVector(dx: 1, dy: 0)) == .right, "D keeps right walking")
        check(PlayInput.walkingDirection(for: CGVector(dx: 0.3, dy: 0.8)) == .up, "vertical dominant diagonal gait")
        check(PlayInput.walkingDirection(for: diagonalMovement) == .right, "equal diagonal keeps horizontal gait")
        check(PlayWalkingDirection.up.verticalDirection == .up, "up vertical atlas mapping")
        check(PlayWalkingDirection.down.verticalDirection == .down, "down vertical atlas mapping")
        check(PlayWalkingDirection.left.verticalDirection == nil, "horizontal has no vertical atlas mapping")
        check(PlayInput.firingDirection(for: [.shootUp, .shootRight]) == .upRight, "diagonal firing")
        check(PlayInput.firingDirection(for: [.shootUp, .shootDown]) == nil, "opposite firing cancels")
        let shotVector = PlayInput.unitVector(for: .downLeft)
        check(abs(hypot(shotVector.dx, shotVector.dy) - 1) < 0.0001, "shot vector normalized")

        check(PetSettings(scale: 0.8).scale == 0.75, "scale snaps down")
        check(PetSettings(scale: 1.12).scale == 1, "scale snaps to normal")
        check(PetSettings(horizontalPosition: 2).horizontalPosition == 1, "position upper clamp")
        check(PetSettings(horizontalPosition: -1).horizontalPosition == 0, "position lower clamp")

        if failures.isEmpty {
            print("IsaacPetCoreChecks: all checks passed")
        } else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
    }
}
