using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using IsaacPet.Windows.Core;
using IsaacPet.Windows.Platform;
using IsaacPet.Windows.Settings;
using IsaacPet.Windows.Sprites;
using IsaacPet.Windows.Ui;
using IsaacPet.Windows.Ui.Pixel;
using Point = System.Windows.Point;
using Size = System.Windows.Size;

namespace IsaacPet.Windows.Pet;

/// <summary>
/// 桌宠行为控制器：30fps 主循环、走动/注视/动作状态机、游玩模式、
/// 点击穿透、拖拽、Todo 提醒。移植自 macOS 版 PetController。
/// </summary>
public sealed class PetController
{
    private static readonly Size BaseSize = new(AnimationCatalog.CellWidth, AnimationCatalog.CellHeight);
    private const double ShootingPoseDuration = 0.11;
    private const double WalkSpeed = 80;      // DIP / 秒
    private const double PlaySpeed = 180;     // DIP / 秒
    private const double TearSpeed = 330;
    private const int MaxProjectiles = 16;
    private const int MaxDrops = 48;

    private readonly PetWindow _window;
    private readonly SettingsStore _settingsStore;
    private readonly SpeechBubbleWindow _speechBubble = new();
    private readonly EmoteBubbleWindow _emoteBubble = new();
    private readonly TodoStore _todoStore;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly DispatcherTimer _timer;
    private readonly SpriteFrame _tearFrame;
    private readonly SpriteFrame _tearDropFrame;

    private SpriteAtlas _atlas;
    private PetSettings _settings;
    private PetAppearanceID _activeAppearance;
    private PetAppearanceID _preferredAppearance;

    private PetState _state = new PetState.Idle();
    private double _stateStartedAt;
    private double? _actionEndsAt;
    private double? _targetX;
    private double _nextRoamAt;
    private double _lastTick;
    private string _currentFrameKey = "";
    private double? _hoveredSince;
    private double _lastWaitingAt;
    private bool _isDragging;
    private bool _isPlayMode;
    private readonly HashSet<Key> _pressedPlayKeys = new();
    private Direction8 _playFacing = Direction8.Down;
    private PlayWalkingDirection? _playWalkingDirection;
    private double _nextShotAt;
    private Direction8? _shootingPoseDirection;
    private double _shootingPoseEndsAt;
    private readonly List<TearProjectile> _projectiles = [];
    private readonly List<TearDrop> _drops = [];
    private double _nextTodoCheckAt;

    public PetSettings CurrentSettings => _settings;
    public bool IsPlayMode => _isPlayMode;
    public TodoStore TodoStore => _todoStore;
    public SettingsStore SettingsStore => _settingsStore;
    public PetAppearanceID PreferredAppearance => _preferredAppearance;

    public event Action? TodosChanged;

    /// <summary>专注时段结束时触发；宿主用它发托盘气泡（macOS 版走系统通知）。</summary>
    public event Action<string>? FocusCompleted;

    public PetController(SettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
        _settings = settingsStore.Load();
        _preferredAppearance = PetAppearanceCatalog.Parse(settingsStore.ActiveAppearance);
        _activeAppearance = _preferredAppearance;

        _atlas = LoadAtlasFor(_preferredAppearance) ?? SpriteAtlas.Load();
        if (_activeAppearance != PetAppearanceID.Isaac && !PetAppearanceCatalog.Availability(_activeAppearance).IsAvailable)
        {
            _activeAppearance = PetAppearanceID.Isaac;
            _preferredAppearance = PetAppearanceID.Isaac;
            settingsStore.ActiveAppearance = PetAppearanceCatalog.RawValue(PetAppearanceID.Isaac);
        }
        _tearFrame = _atlas.TearFrame();
        _tearDropFrame = _atlas.TearDropFrame();

        var size = ScaledSize();
        _window = new PetWindow(size.Width, size.Height);
        _todoStore = new TodoStore();

        var now = Now();
        _lastTick = now;
        _stateStartedAt = now;
        _nextRoamAt = now + Random.Shared.NextDouble() * 6 + 4;
        _nextTodoCheckAt = now + 0.75;

        HookWindowEvents();
        RestorePlacement();
        ShowIdleFrame();
        _window.Show();
        ShowSpeech("嗨！ :)");
        RestoreFocusSession();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.0 / 30) };
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
    }

    private static SpriteAtlas? LoadAtlasFor(PetAppearanceID appearance)
    {
        var definition = PetAppearanceCatalog.DefinitionFor(appearance);
        try
        {
            return SpriteAtlas.Load(
                definition.SpriteSheetName,
                definition.Subdirectory,
                definition.ShootingAtlasName,
                definition.VerticalWalkingName);
        }
        catch (Exception)
        {
            if (appearance == PetAppearanceID.Isaac) throw; // 基础图集缺失是致命错误
            return null;
        }
    }

    private double Now() => _clock.Elapsed.TotalSeconds;

    private Size ScaledSize() => new(BaseSize.Width * _settings.Scale, BaseSize.Height * _settings.Scale);

    // ---------- 主循环 ----------

    private void Tick()
    {
        var now = Now();
        var delta = Math.Clamp(now - _lastTick, 0, 0.1);
        _lastTick = now;

        if (_isPlayMode)
        {
            UpdateProjectiles(delta, now);
            if (!_isDragging) UpdatePlayMode(delta, now);
            Render(now);
            UpdateMousePassThrough();
        }
        else if (_isDragging)
        {
            Render(now);
            UpdateMousePassThrough();
        }
        else
        {
            if (_actionEndsAt is { } actionEnds && now >= actionEnds)
            {
                _actionEndsAt = null;
                TransitionTo(new PetState.Idle(), now);
                ScheduleNextRoam(now);
            }

            if (_actionEndsAt == null && _targetX is { } targetX)
            {
                UpdateWalking(targetX, delta, now);
            }
            else if (_actionEndsAt == null)
            {
                UpdateAttention(now);
                if (_settings.RoamingEnabled && now >= _nextRoamAt) BeginRoaming(now);
            }

            Render(now);
            UpdateMousePassThrough();
        }

        CheckDueTodos(now);
        UpdateSpeechBubbleAnchor();
    }

    private void UpdateWalking(double targetX, double delta, double now)
    {
        var originX = _window.Left;
        var distance = targetX - originX;
        var step = WalkSpeed * delta;
        if (Math.Abs(distance) <= step)
        {
            _window.Left = targetX;
            _targetX = null;
            TransitionTo(new PetState.Idle(), now);
            PersistPlacement();
            ScheduleNextRoam(now);
            return;
        }

        var direction = distance > 0 ? WalkingDirection.Right : WalkingDirection.Left;
        if (_state is not PetState.Walking w || w.Direction != direction)
        {
            TransitionTo(new PetState.Walking(direction), now);
        }
        _window.Left = originX + (distance > 0 ? step : -step);
    }

    private void UpdatePlayMode(double delta, double now)
    {
        var (mx, my) = PlayInput.MovementVector(_pressedPlayKeys);
        var isMoving = mx != 0 || my != 0;
        _playWalkingDirection = PlayInput.WalkingDirectionFor(mx, my);
        if (isMoving)
        {
            // 玩法向量 y 向上；WPF 的 Top 向下，向上移动即减小 Top。
            var proposedLeft = _window.Left + mx * PlaySpeed * delta;
            var proposedTop = _window.Top - my * PlaySpeed * delta;
            var screen = CurrentScreen();
            if (screen != null)
            {
                var (left, top) = screen.WorkingArea.ClampedFreeOrigin(
                    proposedLeft, proposedTop, _window.Width, _window.Height);
                _window.Left = left;
                _window.Top = top;
            }
            if (Direction8Extensions.From(mx, my, deadZone: 0) is { } direction)
            {
                _playFacing = direction;
            }
        }

        if (PlayInput.FiringDirection(_pressedPlayKeys) is { } firingDirection)
        {
            _playFacing = firingDirection;
            if (now >= _nextShotAt)
            {
                SpawnTear(firingDirection, now);
                _nextShotAt = now + 0.22;
            }
        }

        TransitionTo(new PetState.Playing(_playFacing, isMoving), now);
    }

    private void SpawnTear(Direction8 direction, double now)
    {
        _shootingPoseDirection = direction;
        _shootingPoseEndsAt = now + ShootingPoseDuration;
        _currentFrameKey = "";
        if (_projectiles.Count >= MaxProjectiles)
        {
            _projectiles[0].Remove();
            _projectiles.RemoveAt(0);
        }
        var (ux, uy) = PlayInput.UnitVector(direction);
        var centerX = _window.Left + _window.Width / 2 + ux * 26 * _settings.Scale;
        var centerY = _window.Top + _window.Height / 2 - uy * 26 * _settings.Scale;
        var size = _tearFrame.PixelWidth * _settings.Scale;
        _projectiles.Add(new TearProjectile(
            _tearFrame,
            centerX,
            centerY,
            ux * TearSpeed * _settings.Scale,
            -uy * TearSpeed * _settings.Scale, // 泪弹 y 速度在屏幕上取反（y 向下）
            size,
            _settings.Scale,
            behindPet: direction == Direction8.Up,
            petHwnd: _window.Hwnd));
    }

    private void UpdateProjectiles(double delta, double now)
    {
        foreach (var projectile in _projectiles) projectile.Update(delta);
        var bursts = new List<(double X, double Y)>();
        for (var i = _projectiles.Count - 1; i >= 0; i--)
        {
            var projectile = _projectiles[i];
            var centerX = projectile.Window.Left + projectile.Window.Width / 2;
            var centerY = projectile.Window.Top + projectile.Window.Height / 2;
            var onAnyScreen = AllScreens().Any(s => s.WorkingArea.Contains(centerX, centerY));
            if (projectile.Landed) bursts.Add((centerX, centerY));
            if (projectile.Landed || !onAnyScreen)
            {
                projectile.Remove();
                _projectiles.RemoveAt(i);
            }
        }
        foreach (var (x, y) in bursts) SpawnTearBurst(x, y);
        UpdateDrops(delta);
    }

    /// <summary>飞完射程的泪弹爆成几颗小水滴，而不是直接消失。</summary>
    private void SpawnTearBurst(double centerX, double centerY)
    {
        if (_drops.Count >= MaxDrops) return;
        for (var index = 0; index < 4; index++)
        {
            var angle = Math.PI * 2 * index / 4 + Random.Shared.NextDouble() * 0.7;
            var speed = (70 + Random.Shared.NextDouble() * 60) * _settings.Scale;
            _drops.Add(new TearDrop(
                _tearDropFrame,
                centerX,
                centerY,
                Math.Cos(angle) * speed,
                -Math.Abs(Math.Sin(angle)) * speed, // 屏幕 y 向下：爆开的水滴先向上
                _tearDropFrame.PixelWidth * _settings.Scale,
                _settings.Scale));
        }
    }

    private void UpdateDrops(double delta)
    {
        for (var i = _drops.Count - 1; i >= 0; i--)
        {
            if (_drops[i].Update(delta))
            {
                _drops[i].Remove();
                _drops.RemoveAt(i);
            }
        }
    }

    private void RemoveAllProjectiles()
    {
        foreach (var projectile in _projectiles) projectile.Remove();
        _projectiles.Clear();
        foreach (var drop in _drops) drop.Remove();
        _drops.Clear();
    }

    private void UpdateAttention(double now)
    {
        var (cursorPx, cursorPy) = Win32.CursorPosition();
        var cursorScale = _window.PixelsPerDip;
        var cursorDipX = cursorPx / cursorScale;
        var cursorDipY = cursorPy / cursorScale;
        var centerX = _window.Left + _window.Width / 2;
        var centerY = _window.Top + _window.Height / 2;
        var deltaX = cursorDipX - centerX;
        var deltaY = centerY - cursorDipY; // 翻转为 y 向上，与图集方向一致
        var distance = Math.Sqrt(deltaX * deltaX + deltaY * deltaY);
        var sameScreen = ScreenContaining(cursorDipX, cursorDipY)?.Identifier == CurrentScreen()?.Identifier;

        if (sameScreen && distance <= 400
            && Direction8Extensions.From(deltaX, deltaY) is { } direction)
        {
            if (_state is not PetState.Tracking t || t.Direction != direction)
            {
                TransitionTo(new PetState.Tracking(direction), now);
            }
        }
        else if (_state.Priority <= new PetState.Tracking(Direction8.Up).Priority && _state is not PetState.Idle)
        {
            TransitionTo(new PetState.Idle(), now);
        }

        if (CursorOverVisiblePixel() is true)
        {
            _hoveredSince ??= now;
            if (now - _hoveredSince.Value > 1.3 && now - _lastWaitingAt > 8 && _actionEndsAt == null)
            {
                _lastWaitingAt = now;
                Perform(AnimationID.Waiting, now);
            }
        }
        else
        {
            _hoveredSince = null;
        }
    }

    private void BeginRoaming(double now)
    {
        var screen = CurrentScreen();
        if (screen == null) return;
        var area = screen.WorkingArea;
        var minimum = area.MinX;
        var maximum = Math.Max(minimum, area.MaxX - _window.Width);
        if (maximum - minimum <= 40) return;

        var candidate = minimum + Random.Shared.NextDouble() * (maximum - minimum);
        if (Math.Abs(candidate - _window.Left) < 120)
        {
            candidate = _window.Left < area.MidX ? maximum : minimum;
        }
        _targetX = candidate;
        var direction = candidate >= _window.Left ? WalkingDirection.Right : WalkingDirection.Left;
        TransitionTo(new PetState.Walking(direction), now);
    }

    private void ScheduleNextRoam(double now) => _nextRoamAt = now + Random.Shared.NextDouble() * 6 + 4;

    private void TransitionTo(PetState newState, double now)
    {
        if (_state.Equals(newState)) return;
        _state = newState;
        _stateStartedAt = now;
        _currentFrameKey = "";
    }

    public void Perform(AnimationID animation) => Perform(animation, Now());

    private void Perform(AnimationID animation, double now)
    {
        _targetX = null;
        TransitionTo(new PetState.Action(animation), now);
        _actionEndsAt = now + AnimationCatalog.SpecFor(animation).Duration;
    }

    // ---------- 渲染 ----------

    private void Render(double now)
    {
        switch (_state)
        {
            case PetState.Tracking tracking:
            {
                var key = $"direction-{(int)tracking.Direction}";
                if (_currentFrameKey == key) return;
                SetFrame(_atlas.Frame(tracking.Direction));
                _currentFrameKey = key;
                break;
            }
            case PetState.Walking walking:
                RenderAnimation(walking.Direction == WalkingDirection.Right ? AnimationID.WalkRight : AnimationID.WalkLeft, now);
                break;
            case PetState.Action action:
                RenderAnimation(action.Animation, now);
                break;
            case PetState.Playing playing:
            {
                if (_shootingPoseDirection is { } poseDirection && now < _shootingPoseEndsAt)
                {
                    var key = $"shooting-{AnimationCatalog.ShootingColumn(poseDirection)}";
                    if (_currentFrameKey == key) return;
                    SetFrame(_atlas.ShootingFrame(poseDirection));
                    _currentFrameKey = key;
                }
                else if (playing.Moving && _playWalkingDirection is { } walkingDirection)
                {
                    switch (walkingDirection)
                    {
                        case PlayWalkingDirection.Left:
                            RenderAnimation(AnimationID.WalkLeft, now);
                            break;
                        case PlayWalkingDirection.Right:
                            RenderAnimation(AnimationID.WalkRight, now);
                            break;
                        case PlayWalkingDirection.Down:
                        case PlayWalkingDirection.Up:
                            RenderVerticalWalking(walkingDirection.VerticalDirection()!.Value, now);
                            break;
                    }
                }
                else
                {
                    var key = $"play-direction-{(int)playing.Facing}";
                    if (_currentFrameKey == key) return;
                    SetFrame(_atlas.Frame(playing.Facing));
                    _currentFrameKey = key;
                }
                break;
            }
            case PetState.Idle:
            case PetState.Dragging:
                RenderAnimation(AnimationID.Idle, now);
                break;
        }
    }

    private void RenderAnimation(AnimationID animation, double now)
    {
        var spec = AnimationCatalog.SpecFor(animation);
        var frameIndex = spec.FrameIndex(now - _stateStartedAt);
        var key = $"{animation}-{frameIndex}";
        if (_currentFrameKey == key) return;
        SetFrame(_atlas.Frame(animation, frameIndex));
        _currentFrameKey = key;
    }

    private void RenderVerticalWalking(VerticalWalkingDirection direction, double now)
    {
        var spec = AnimationCatalog.VerticalWalkingSpecFor(direction);
        var frameIndex = spec.FrameIndex(now - _stateStartedAt);
        var key = $"vertical-walk-{(int)direction}-{frameIndex}";
        if (_currentFrameKey == key) return;
        SetFrame(_atlas.VerticalWalkingFrame(direction, frameIndex));
        _currentFrameKey = key;
    }

    private void ShowIdleFrame()
    {
        SetFrame(_atlas.Frame(AnimationID.Idle, 0));
        _currentFrameKey = $"{AnimationID.Idle}-0";
    }

    // ---------- 鼠标穿透与点击 ----------

    private SpriteFrame? _currentSpriteFrame;

    /// <summary>更新当前帧，同时记录帧引用用于逐像素命中测试。</summary>
    private void SetFrame(SpriteFrame frame)
    {
        _currentSpriteFrame = frame;
        _window.SetFrame(frame);
    }

    private bool? CursorOverVisiblePixel()
    {
        var local = _window.CursorLocalPosition();
        if (local == null) return false;
        var frame = _currentSpriteFrame;
        if (frame == null) return false;
        return frame.IsOpaqueAt(local.Value.X, local.Value.Y, _window.Width, _window.Height);
    }

    private void UpdateMousePassThrough()
    {
        if (_isDragging)
        {
            _window.SetClickThrough(false);
            return;
        }
        _window.SetClickThrough(CursorOverVisiblePixel() == false);
    }

    private void HookWindowEvents()
    {
        _window.MouseLeftButtonDown += OnMouseLeftButtonDown;
        _window.MouseLeftButtonUp += OnMouseLeftButtonUp;
        _window.MouseMove += OnMouseMove;
        _window.MouseRightButtonUp += OnMouseRightButtonUp;
        _window.KeyDown += OnKeyDown;
        _window.KeyUp += OnKeyUp;
        _window.LostFocus += (_, _) =>
        {
            if (!_isPlayMode) return;
            _pressedPlayKeys.Clear();
            _playWalkingDirection = null;
            TransitionTo(new PetState.Playing(_playFacing, Moving: false), Now());
        };
    }

    private Point _mouseDownScreenDip;
    private Point _mouseDownWindowOrigin;
    private bool _singleClickPending;
    private DispatcherTimer? _singleClickTimer;

    private Point CursorScreenDip()
    {
        var (px, py) = Win32.CursorPosition();
        var scale = _window.PixelsPerDip;
        return new Point(px / scale, py / scale);
    }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _singleClickTimer?.Stop();
        _singleClickPending = false;
        _mouseDownScreenDip = CursorScreenDip();
        _mouseDownWindowOrigin = new Point(_window.Left, _window.Top);
        _window.CaptureMouse();

        if (e.ClickCount >= 2)
        {
            if (_isPlayMode) FocusPlayControls(); else Perform(AnimationID.Jump);
        }
    }

    private void OnMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        _window.ReleaseMouseCapture();
        if (_isDragging)
        {
            _isDragging = false;
            var now = Now();
            if (_isPlayMode)
            {
                ClampPlayToVisibleScreen();
                TransitionTo(new PetState.Playing(_playFacing, Moving: false), now);
                FocusPlayControls();
            }
            else
            {
                ClampToVisibleScreen();
                TransitionTo(new PetState.Idle(), now);
                ScheduleNextRoam(now);
            }
            return;
        }
        if (e.ClickCount >= 2) return; // 双击已在 Down 处理
        if (_isPlayMode)
        {
            FocusPlayControls();
            return;
        }
        // 延迟 220ms 触发单击，给双击留出取消窗口（对应 macOS 的 cancelPreviousPerformRequests）。
        _singleClickPending = true;
        _singleClickTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(220) };
        _singleClickTimer.Tick += (_, _) =>
        {
            _singleClickTimer?.Stop();
            if (_singleClickPending)
            {
                _singleClickPending = false;
                Perform(AnimationID.Wave);
            }
        };
        _singleClickTimer.Start();
    }

    private void OnMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;
        var location = CursorScreenDip();
        var delta = location - _mouseDownScreenDip;
        if (!_isDragging && delta.Length >= 3)
        {
            _isDragging = true;
            _singleClickPending = false;
            _singleClickTimer?.Stop();
            _pressedPlayKeys.Clear();
            _playWalkingDirection = null;
            _targetX = null;
            _actionEndsAt = null;
            TransitionTo(new PetState.Dragging(), Now());
            _window.SetClickThrough(false);
        }
        if (_isDragging)
        {
            _window.Left = _mouseDownWindowOrigin.X + delta.X;
            _window.Top = _mouseDownWindowOrigin.Y + delta.Y;
        }
    }

    private void OnMouseRightButtonUp(object sender, MouseButtonEventArgs e)
    {
        ContextMenuRequested?.Invoke();
    }

    public event Action? ContextMenuRequested;

    private void OnKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (!_isPlayMode || !PlayKeys.IsPlayKey(e.Key)) return;
        if (e.Key == Key.Escape)
        {
            ExitPlayMode();
            e.Handled = true;
            return;
        }
        if (e.IsRepeat) { e.Handled = true; return; }
        if (_pressedPlayKeys.Add(e.Key)
            && e.Key is Key.Up or Key.Right or Key.Down or Key.Left)
        {
            var now = Now();
            if (PlayInput.FiringDirection(_pressedPlayKeys) is { } direction)
            {
                _playFacing = direction;
                SpawnTear(direction, now);
                _nextShotAt = now + 0.22;
                TransitionTo(new PetState.Playing(direction, Moving: false), now);
            }
        }
        e.Handled = true;
    }

    private void OnKeyUp(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (!_isPlayMode || !PlayKeys.IsPlayKey(e.Key)) return;
        _pressedPlayKeys.Remove(e.Key);
        e.Handled = true;
    }

    // ---------- 屏幕与位置 ----------

    private List<ScreenInfo> AllScreens() => ScreenInfo.All();

    private ScreenInfo? ScreenContaining(double dipX, double dipY) =>
        AllScreens().FirstOrDefault(s => s.WorkingArea.Contains(dipX, dipY));

    private ScreenInfo? CurrentScreen()
    {
        var screens = AllScreens();
        var centerX = _window.Left + _window.Width / 2;
        var centerY = _window.Top + _window.Height / 2;
        return screens.FirstOrDefault(s => s.WorkingArea.Contains(centerX, centerY))
            ?? screens.FirstOrDefault(s => s.WorkingArea.Contains(_window.Left, _window.Top))
            ?? screens.FirstOrDefault();
    }

    private void RestorePlacement()
    {
        var screens = AllScreens();
        var screen = screens.FirstOrDefault(s => s.Identifier == _settings.ScreenIdentifier)
            ?? screens.FirstOrDefault(s => s.IsPrimary)
            ?? screens[0];
        var (left, top) = screen.WorkingArea.Origin(_settings.HorizontalPosition, _window.Width, _window.Height);
        _window.Left = left;
        _window.Top = top;
    }

    private void PersistPlacement()
    {
        var screen = CurrentScreen();
        if (screen == null) return;
        _settings.ScreenIdentifier = screen.Identifier;
        _settings.HorizontalPosition = screen.WorkingArea.HorizontalPositionFor(_window.Left, _window.Width);
        _settingsStore.Save(_settings);
    }

    private void ClampToVisibleScreen()
    {
        var screen = CurrentScreen() ?? AllScreens()[0];
        var (left, top) = screen.WorkingArea.ClampedOrigin(_window.Left, _window.Top, _window.Width, _window.Height);
        _window.Left = left;
        _window.Top = top;
        PersistPlacement();
    }

    private void ClampPlayToVisibleScreen()
    {
        var screen = CurrentScreen() ?? AllScreens()[0];
        var (left, top) = screen.WorkingArea.ClampedFreeOrigin(_window.Left, _window.Top, _window.Width, _window.Height);
        _window.Left = left;
        _window.Top = top;
        PersistPlacement();
    }

    /// <summary>屏幕配置变化（分辨率/多屏插拔）时调用。</summary>
    public void HandleScreenConfigurationChange()
    {
        if (_isPlayMode) ClampPlayToVisibleScreen(); else ClampToVisibleScreen();
    }

    // ---------- 气泡 ----------

    public void ShowSpeech(string message)
    {
        if (_isPlayMode) return;
        _emoteBubble.Hide(); // 表情气泡和说话气泡悬浮在同一位置，说话时先收起表情。
        var screen = CurrentScreen();
        if (screen == null) return;
        _speechBubble.ShowMessage(message, PetFrameDip(), screen.WorkingArea);
    }

    private Rect PetFrameDip() => new(_window.Left, _window.Top, _window.Width, _window.Height);

    private void UpdateSpeechBubbleAnchor()
    {
        var screen = CurrentScreen();
        if (screen == null) return;
        _speechBubble.UpdateAnchor(PetFrameDip(), screen.WorkingArea);
        _emoteBubble.UpdateAnchor(PetFrameDip(), screen.WorkingArea);
    }

    // ---------- 专注计时 ----------

    private CancellationTokenSource? _focusCts;
    private DateTimeOffset? _focusDeadline;

    public bool FocusRunning => _focusCts != null;

    public void StartFocusTimer()
    {
        if (_isPlayMode || FocusRunning) return;
        _targetX = null;
        PresentFocusComposer();
    }

    public void CancelFocusTimer() => _focusCts?.Cancel();

    public string FocusRemainingText()
    {
        if (_focusDeadline is not { } deadline) return FocusSessionPolicy.ClockText(0);
        return FocusSessionPolicy.ClockText(FocusSessionPolicy.RemainingSeconds(deadline, DateTimeOffset.Now));
    }

    private void PresentFocusComposer()
    {
        var targetBox = PixelStyle.CreateField("要专注做什么？（可留空，最多 80 字）");
        var durationBox = new System.Windows.Controls.ComboBox
        {
            ItemsSource = new[] { "15 分钟", "25 分钟", "45 分钟" },
            SelectedIndex = 1,
            Width = 160,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
        };
        var testSeconds = Environment.GetEnvironmentVariable("ISAAC_FOCUS_DURATION_SECONDS");
        if (testSeconds != null)
        {
            durationBox.Items.Add($"测试时长（{FocusSessionPolicy.DurationText(FocusSessionPolicy.DurationFromSeconds(testSeconds))}）");
            durationBox.SelectedIndex = durationBox.Items.Count - 1;
        }

        var window = new PixelWindow("专注计时", resizable: false)
        {
            Width = 480,
            SizeToContent = SizeToContent.Height,
            ResizeMode = ResizeMode.NoResize,
        };
        var root = new System.Windows.Controls.StackPanel();
        root.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "计时完全在本机运行。结束后会弹窗提醒；也可以随时在菜单里取消。",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 10),
        });
        root.Children.Add(new System.Windows.Controls.TextBlock { Text = "专注目标" });
        root.Children.Add(targetBox);
        root.Children.Add(new System.Windows.Controls.TextBlock { Text = "时长", Margin = new Thickness(0, 8, 0, 0) });
        root.Children.Add(durationBox);
        var started = false;
        var buttons = new System.Windows.Controls.StackPanel
        {
            Orientation = System.Windows.Controls.Orientation.Horizontal,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Right,
            Margin = new Thickness(0, 12, 0, 0),
        };
        var startButton = new PixelButton { Content = "开始专注", IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        var cancelButton = new PixelButton { Content = "取消", IsCancel = true };
        startButton.Click += (_, _) => { started = true; window.Close(); };
        buttons.Children.Add(startButton);
        buttons.Children.Add(cancelButton);
        root.Children.Add(buttons);
        window.SetContent(root);
        window.ShowDialog();

        if (!started) return;
        TimeSpan duration;
        if (durationBox.SelectedIndex is >= 0 and <= 2)
        {
            duration = TimeSpan.FromMinutes(new[] { 15, 25, 45 }[durationBox.SelectedIndex]);
        }
        else
        {
            duration = testSeconds != null
                ? FocusSessionPolicy.DurationFromSeconds(testSeconds)
                : FocusSessionPolicy.DefaultDuration;
        }
        StartFocusSession(NormalizedFocusTarget(targetBox.Text), duration);
    }

    private static string? NormalizedFocusTarget(string? rawValue)
    {
        var value = rawValue?.Trim();
        if (string.IsNullOrEmpty(value)) return null;
        return value[..Math.Min(value.Length, 80)];
    }

    private void StartFocusSession(string? target, TimeSpan duration)
    {
        if (_isPlayMode || FocusRunning) return;
        var safeDuration = duration > FocusSessionPolicy.MaximumDuration ? FocusSessionPolicy.MaximumDuration : duration;
        if (safeDuration < TimeSpan.FromSeconds(1)) safeDuration = TimeSpan.FromSeconds(1);
        var deadline = DateTimeOffset.Now + safeDuration;
        _focusDeadline = deadline;
        _settingsStore.FocusDeadline = deadline;
        _settingsStore.FocusTarget = target;
        Perform(AnimationID.Observe);
        ShowSpeech($"专注开始！{FocusSessionPolicy.DurationText(safeDuration)}后见。");
        BeginFocusCountdown(deadline, target);
    }

    private async void BeginFocusCountdown(DateTimeOffset deadline, string? target)
    {
        _focusCts = new CancellationTokenSource();
        var token = _focusCts.Token;
        try
        {
            var remaining = deadline - DateTimeOffset.Now;
            if (remaining > TimeSpan.Zero) await Task.Delay(remaining, token);
            ClearFocusSession();
            PresentFocusCompletion(target);
            ThumbsUp();
            ShowSpeech("专注完成！起来休息一下吧。");
        }
        catch (OperationCanceledException)
        {
            ClearFocusSession();
            ShowSpeech("专注计时已取消。");
        }
        catch (Exception error)
        {
            ClearFocusSession();
            ShowSpeech($"专注计时失败：{error.Message}");
        }
    }

    private void ClearFocusSession()
    {
        _focusCts = null;
        _focusDeadline = null;
        _settingsStore.FocusDeadline = null;
        _settingsStore.FocusTarget = null;
    }

    private void RestoreFocusSession()
    {
        if (_settingsStore.FocusDeadline is not { } deadline) return;
        if (deadline <= DateTimeOffset.Now)
        {
            ClearFocusSession();
            ShowSpeech("刚才的专注时段已经结束啦。");
            return;
        }
        ShowSpeech("已恢复专注计时。");
        BeginFocusCountdown(deadline, _settingsStore.FocusTarget);
    }

    private void PresentFocusCompletion(string? target)
    {
        var subject = target == null ? "" : $"\n\n目标：{target}";
        FocusCompleted?.Invoke("专注结束：起来休息一下吧。");
        PixelDialog.ShowMessage(
            "专注完成",
            $"起来休息一下，再决定下一步。{subject}\n托盘气泡会同时提醒，桌面气泡始终有效。");
    }

    // ---------- Todo 提醒 ----------

    private void CheckDueTodos(double now)
    {
        if (now < _nextTodoCheckAt) return;
        _nextTodoCheckAt = now + 0.75;
        if (_isPlayMode) return;

        var dueItems = TodoPolicy.DueForDelivery(_todoStore.Items, DateTimeOffset.Now);
        if (dueItems.Count == 0) return;
        _todoStore.MarkRemindersDelivered(dueItems.Select(i => i.Id).ToHashSet());
        TodosChanged?.Invoke();
        Perform(AnimationID.Observe);
        if (dueItems.Count == 1)
        {
            ShowSpeech($"提醒：{dueItems[0].Title}");
        }
        else
        {
            ShowSpeech($"有 {dueItems.Count} 个 Todo 到时间了！");
        }
        DueTodosDelivered?.Invoke(dueItems);
    }

    /// <summary>系统层（托盘气泡）通知入口。</summary>
    public event Action<IReadOnlyList<TodoItem>>? DueTodosDelivered;

    // ---------- 菜单动作（供 PetMenu 调用） ----------

    public void TogglePlayMode()
    {
        if (_isPlayMode) ExitPlayMode(); else EnterPlayMode();
    }

    private void EnterPlayMode()
    {
        if (_isPlayMode) return;
        _isPlayMode = true;
        _speechBubble.HideBubble();
        _emoteBubble.Hide();
        _targetX = null;
        _actionEndsAt = null;
        _hoveredSince = null;
        _pressedPlayKeys.Clear();
        _playWalkingDirection = null;
        _nextShotAt = 0;
        _shootingPoseDirection = null;
        _shootingPoseEndsAt = 0;
        TransitionTo(new PetState.Playing(_playFacing, Moving: false), Now());
        FocusPlayControls();
    }

    public void ExitPlayMode()
    {
        if (!_isPlayMode) return;
        _isPlayMode = false;
        _pressedPlayKeys.Clear();
        _playWalkingDirection = null;
        _shootingPoseDirection = null;
        _shootingPoseEndsAt = 0;
        RemoveAllProjectiles();
        ClampToVisibleScreen();
        TransitionTo(new PetState.Idle(), Now());
        ScheduleNextRoam(Now());
        Win32.SetNoActivate(_window.Hwnd, true);
    }

    private void FocusPlayControls()
    {
        if (!_isPlayMode) return;
        Win32.SetNoActivate(_window.Hwnd, false);
        _window.Focusable = true;
        _window.Activate();
        _window.Focus();
        Keyboard.Focus(_window);
    }

    public void ToggleRoaming()
    {
        if (_isPlayMode) return;
        _settings.RoamingEnabled = !_settings.RoamingEnabled;
        _targetX = null;
        TransitionTo(new PetState.Idle(), Now());
        ScheduleNextRoam(Now());
        _settingsStore.Save(_settings);
    }

    public void Wave() => Perform(AnimationID.Wave);
    public void Jump() => Perform(AnimationID.Jump);
    public void Cry() => Perform(AnimationID.Cry);
    public void ThumbsUp() => Perform(AnimationID.ThumbsUp);
    public void Observe() => Perform(AnimationID.Observe);

    public void SayRandomPhrase()
    {
        Perform(AnimationID.Observe);
        ShowSpeech(PetSpeechLibrary.RandomPhrase());
    }

    public void ShowRandomEmote()
    {
        if (_isPlayMode) return;
        var emote = EmoteIDExtensions.RandomEmote();
        Perform(emote.CompanionAnimation());
        _emoteBubble.Hide();
        var screen = CurrentScreen();
        if (screen == null) return;
        _emoteBubble.Show(_atlas.EmoteFrame(emote), PetFrameDip(), screen.WorkingArea, _settings.Scale);
    }

    public void ShowCustomSpeech(string rawText) => ShowSpeech(rawText);

    public void ChangeScale(double scale)
    {
        var oldLeft = _window.Left;
        var oldWidth = _window.Width;
        var oldBottom = _window.Top + _window.Height;
        _settings.Scale = PetSettings.ValidScale(scale);
        var size = ScaledSize();
        _window.Width = size.Width;
        _window.Height = size.Height;
        // 与 macOS 版一致：水平方向以中心对齐，竖直方向保持底边不动。
        _window.Left = oldLeft + oldWidth / 2 - size.Width / 2;
        _window.Top = oldBottom - size.Height;
        if (_isPlayMode) ClampPlayToVisibleScreen(); else ClampToVisibleScreen();
        _settingsStore.Save(_settings);
    }

    public bool ToggleLaunchAtLogin()
    {
        var enable = !StartupRegistration.IsEnabled;
        StartupRegistration.SetEnabled(enable);
        return enable;
    }

    public void ReturnToMainScreen()
    {
        var screens = AllScreens();
        var primary = screens.FirstOrDefault(s => s.IsPrimary) ?? screens[0];
        _settings.ScreenIdentifier = primary.Identifier;
        _settings.HorizontalPosition = 0.82;
        var (left, top) = primary.WorkingArea.Origin(0.82, _window.Width, _window.Height);
        _window.Left = left;
        _window.Top = top;
        _settingsStore.Save(_settings);
    }

    public bool ActivateAppearance(PetAppearanceID appearance, bool announce = true, bool persistUserSelection = true)
    {
        if (appearance == _activeAppearance)
        {
            if (persistUserSelection)
            {
                _preferredAppearance = appearance;
                _settingsStore.ActiveAppearance = PetAppearanceCatalog.RawValue(appearance);
            }
            return true;
        }
        var availability = PetAppearanceCatalog.Availability(appearance);
        if (!availability.IsAvailable)
        {
            if (announce)
            {
                ShowSpeech($"{PetAppearanceCatalog.DefinitionFor(appearance).DisplayName}：{availability.UnavailableReason}");
            }
            return false;
        }
        var definition = PetAppearanceCatalog.DefinitionFor(appearance);
        try
        {
            _atlas = SpriteAtlas.Load(
                definition.SpriteSheetName,
                definition.Subdirectory,
                definition.ShootingAtlasName,
                definition.VerticalWalkingName);
        }
        catch (Exception error)
        {
            if (announce) ShowSpeech($"无法加载角色图集：{error.Message}");
            return false;
        }
        _activeAppearance = appearance;
        if (persistUserSelection)
        {
            _preferredAppearance = appearance;
            _settingsStore.ActiveAppearance = PetAppearanceCatalog.RawValue(appearance);
        }
        _currentFrameKey = "";
        ShowIdleFrame();
        if (announce) ShowSpeech($"已切换为 {definition.DisplayName}。");
        return true;
    }

    public void NotifyTodosChanged() => TodosChanged?.Invoke();

    public void Stop()
    {
        _timer.Stop();
        RemoveAllProjectiles();
        _emoteBubble.Hide();
        _speechBubble.HideBubble();
        _speechBubble.Close();
        _window.Close();
    }
}
