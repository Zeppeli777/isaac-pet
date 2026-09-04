using System.Windows.Input;

namespace IsaacPet.Windows.Core;

/// <summary>动画标识，与 macOS 版 IsaacPetCore 的 AnimationID 一一对应。</summary>
public enum AnimationID
{
    Idle,
    WalkRight,
    WalkLeft,
    Wave,
    Jump,
    Cry,
    Waiting,
    ThumbsUp,
    Observe,
}

public readonly record struct AnimationSpec(int Row, int FrameCount, double FrameDuration, bool Loops)
{
    public double Duration => FrameCount * FrameDuration;

    public int FrameIndex(double elapsed)
    {
        if (FrameCount <= 1) return 0;
        var raw = Math.Max(0, (int)(elapsed / FrameDuration));
        return Loops ? raw % FrameCount : Math.Min(raw, FrameCount - 1);
    }
}

/// <summary>
/// 8 方向（y 轴向上为正，与 macOS 坐标一致）。Windows 屏幕坐标 y 向下，
/// 调用方需要在换算鼠标位移时翻转 dy。
/// </summary>
public enum Direction8
{
    Up = 0,
    UpRight,
    Right,
    DownRight,
    Down,
    DownLeft,
    Left,
    UpLeft,
}

public static class Direction8Extensions
{
    public static Direction8? From(double deltaX, double deltaY, double deadZone = 40)
    {
        if (Math.Sqrt(deltaX * deltaX + deltaY * deltaY) < deadZone) return null;
        var degrees = Math.Atan2(deltaY, deltaX) * 180.0 / Math.PI;
        return degrees switch
        {
            >= -22.5 and < 22.5 => Direction8.Right,
            >= 22.5 and < 67.5 => Direction8.UpRight,
            >= 67.5 and < 112.5 => Direction8.Up,
            >= 112.5 and < 157.5 => Direction8.UpLeft,
            >= 157.5 or < -157.5 => Direction8.Left,
            >= -157.5 and < -112.5 => Direction8.DownLeft,
            >= -112.5 and < -67.5 => Direction8.Down,
            _ => Direction8.DownRight,
        };
    }
}

public enum WalkingDirection { Left, Right }

public enum VerticalWalkingDirection { Down = 0, Up }

public enum PlayWalkingDirection
{
    Left,
    Right,
    Down,
    Up,
}

public static class PlayWalkingDirectionExtensions
{
    public static VerticalWalkingDirection? VerticalDirection(this PlayWalkingDirection direction) =>
        direction switch
        {
            PlayWalkingDirection.Down => Core.VerticalWalkingDirection.Down,
            PlayWalkingDirection.Up => Core.VerticalWalkingDirection.Up,
            _ => null,
        };
}

/// <summary>游玩模式按键集合。Windows 端直接复用 WPF 的 Key 枚举。</summary>
public static class PlayKeys
{
    public static readonly Key MoveLeft = Key.A;
    public static readonly Key MoveDown = Key.S;
    public static readonly Key MoveRight = Key.D;
    public static readonly Key MoveUp = Key.W;
    public static readonly Key ShootLeft = Key.Left;
    public static readonly Key ShootRight = Key.Right;
    public static readonly Key ShootDown = Key.Down;
    public static readonly Key ShootUp = Key.Up;

    public static bool IsPlayKey(Key key) =>
        key is Key.A or Key.S or Key.D or Key.W or Key.Left or Key.Right or Key.Down or Key.Up or Key.Escape;
}

public static class PlayInput
{
    public static (double X, double Y) MovementVector(IReadOnlySet<Key> keys) =>
        Normalize(
            Axis(MoveNegative: PlayKeys.MoveLeft, MovePositive: PlayKeys.MoveRight, keys),
            Axis(PlayKeys.MoveDown, PlayKeys.MoveUp, keys));

    public static Direction8? FiringDirection(IReadOnlySet<Key> keys)
    {
        var x = Axis(PlayKeys.ShootLeft, PlayKeys.ShootRight, keys);
        var y = Axis(PlayKeys.ShootDown, PlayKeys.ShootUp, keys);
        if (x == 0 && y == 0) return null;
        return Direction8Extensions.From(x, y, deadZone: 0);
    }

    /// <summary>斜向输入时选一个步态：占优分量优先，平局沿用横向步态。</summary>
    public static PlayWalkingDirection? WalkingDirectionFor(double x, double y)
    {
        if (x == 0 && y == 0) return null;
        if (Math.Abs(y) > Math.Abs(x)) return y > 0 ? PlayWalkingDirection.Up : PlayWalkingDirection.Down;
        return x > 0 ? PlayWalkingDirection.Right : PlayWalkingDirection.Left;
    }

    public static (double X, double Y) UnitVector(Direction8 direction) => direction switch
    {
        Direction8.Up => (0, 1),
        Direction8.UpRight => Normalize(1, 1),
        Direction8.Right => (1, 0),
        Direction8.DownRight => Normalize(1, -1),
        Direction8.Down => (0, -1),
        Direction8.DownLeft => Normalize(-1, -1),
        Direction8.Left => (-1, 0),
        Direction8.UpLeft => Normalize(-1, 1),
        _ => (0, 0),
    };

    private static int Axis(Key MoveNegative, Key MovePositive, IReadOnlySet<Key> keys) =>
        (keys.Contains(MovePositive) ? 1 : 0) - (keys.Contains(MoveNegative) ? 1 : 0);

    private static (double X, double Y) Normalize(double x, double y)
    {
        var length = Math.Sqrt(x * x + y * y);
        return length > 0 ? (x / length, y / length) : (0, 0);
    }
}

/// <summary>桌宠状态机，优先级与 macOS 版一致。</summary>
public abstract record PetState
{
    public sealed record Idle : PetState;
    public sealed record Walking(WalkingDirection Direction) : PetState;
    public sealed record Tracking(Direction8 Direction) : PetState;
    public sealed record Action(AnimationID Animation) : PetState;
    public sealed record Playing(Direction8 Facing, bool Moving) : PetState;
    public sealed record Dragging : PetState;

    public int Priority => this switch
    {
        Idle => 0,
        Tracking => 1,
        Walking => 2,
        Action => 3,
        Playing => 4,
        Dragging => 5,
        _ => 0,
    };
}

public static class AnimationCatalog
{
    public const int CellWidth = 192;
    public const int CellHeight = 208;
    public const int Columns = 8;
    public const int Rows = 11;
    public const int VerticalWalkingColumns = 4;
    public const int VerticalWalkingRows = 2;

    public static readonly IReadOnlyDictionary<AnimationID, AnimationSpec> Specs =
        new Dictionary<AnimationID, AnimationSpec>
        {
            [AnimationID.Idle] = new(Row: 0, FrameCount: 7, FrameDuration: 0.18, Loops: true),
            [AnimationID.WalkRight] = new(Row: 1, FrameCount: 8, FrameDuration: 0.09, Loops: true),
            [AnimationID.WalkLeft] = new(Row: 2, FrameCount: 8, FrameDuration: 0.09, Loops: true),
            [AnimationID.Wave] = new(Row: 3, FrameCount: 4, FrameDuration: 0.13, Loops: false),
            [AnimationID.Jump] = new(Row: 4, FrameCount: 5, FrameDuration: 0.12, Loops: false),
            [AnimationID.Cry] = new(Row: 5, FrameCount: 8, FrameDuration: 0.14, Loops: false),
            [AnimationID.Waiting] = new(Row: 6, FrameCount: 6, FrameDuration: 0.16, Loops: false),
            [AnimationID.ThumbsUp] = new(Row: 7, FrameCount: 6, FrameDuration: 0.15, Loops: false),
            [AnimationID.Observe] = new(Row: 8, FrameCount: 6, FrameDuration: 0.15, Loops: false),
        };

    public static readonly IReadOnlyDictionary<VerticalWalkingDirection, AnimationSpec> VerticalWalkingSpecs =
        new Dictionary<VerticalWalkingDirection, AnimationSpec>
        {
            [VerticalWalkingDirection.Down] = new(Row: 0, FrameCount: 4, FrameDuration: 0.09, Loops: true),
            [VerticalWalkingDirection.Up] = new(Row: 1, FrameCount: 4, FrameDuration: 0.09, Loops: true),
        };

    public static AnimationSpec SpecFor(AnimationID animation) => Specs[animation];

    public static AnimationSpec VerticalWalkingSpecFor(VerticalWalkingDirection direction) =>
        VerticalWalkingSpecs[direction];

    public static (int Row, int Column) AtlasCell(Direction8 direction) => direction switch
    {
        Direction8.Up => (9, 0),
        Direction8.UpRight => (9, 2),
        Direction8.Right => (9, 4),
        Direction8.DownRight => (9, 6),
        Direction8.Down => (10, 0),
        Direction8.DownLeft => (10, 2),
        Direction8.Left => (10, 4),
        Direction8.UpLeft => (10, 6),
        _ => (10, 0),
    };

    public static int ShootingColumn(Direction8 direction) => direction switch
    {
        Direction8.Up => 0,
        Direction8.UpRight or Direction8.Right or Direction8.DownRight => 1,
        Direction8.Down => 2,
        _ => 3,
    };
}
