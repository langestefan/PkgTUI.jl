"""
    PrecompileTools workload for PkgTUI.

Exercises all major view rendering and key-handling code paths during
precompilation so that native code is cached, drastically reducing
time-to-first-execution (TTFX).
"""

using PrecompileTools

@compile_workload begin
    # ── Construct a headless Frame ──────────────────────────────────────────
    _rect = Rect(1, 1, 120, 40)
    _buf = Buffer(_rect)
    _frame = Frame(
        _buf,
        _rect,
        Tachikoma.GraphicsRegion[],
        Tuple{Int,Int,Matrix{Tachikoma.ColorRGB}}[],
    )

    # ── Create model with some synthetic data ───────────────────────────────
    _m = PkgTUIApp()

    # Populate with a few fake packages so table rendering is exercised
    _fake_uuid = Base.UUID("00000000-0000-0000-0000-000000000001")
    _fake_pkgs = [
        PackageRow(
            name = "FakePackage",
            uuid = _fake_uuid,
            version = "1.2.3",
            is_direct_dep = true,
        ),
        PackageRow(
            name = "TransitiveDep",
            uuid = Base.UUID("00000000-0000-0000-0000-000000000002"),
            version = "0.5.0",
            is_direct_dep = false,
        ),
    ]
    _m.installed.packages = _fake_pkgs
    _m.installed.filtered = _fake_pkgs
    _m.installed.loading = false

    # Fake project info
    _m.project_info = ProjectInfo(name = "PrecompileEnv", dep_count = 2, is_package = true)

    # Fake updates
    _fake_updates = [
        UpdateInfo(
            name = "FakePackage",
            current_version = "1.2.3",
            latest_compatible = "1.3.0",
            can_update = true,
        ),
    ]
    _m.updates_state.updates = _fake_updates

    # Fake conflicts
    _m.conflicts.conflicts = [
        ConflictInfo(
            package = "FakePackage",
            held_at = "1.2.3",
            latest = "2.0.0",
            blocked_by = "OtherPkg",
        ),
    ]

    # Fake metrics
    _m.metrics.metrics = [
        PackageMetrics(
            name = "FakePackage",
            disk_size_bytes = 1_000_000,
            compile_time_seconds = 1.5,
            is_direct = true,
        ),
    ]

    # Fake registry data
    _m.registry.registry_index =
        [RegistryPackage(name = "FakePackage", latest_version = "1.3.0")]
    _m.registry.results = _m.registry.registry_index
    _m.registry.index_loaded = true

    push_line!(_m.log_pane, "Precompile workload log entry")

    # ── Exercise all 6 tab renders ──────────────────────────────────────────
    for tab = 1:6
        _m.active_tab = tab
        _buf2 = Buffer(_rect)
        _f2 = Frame(
            _buf2,
            _rect,
            Tachikoma.GraphicsRegion[],
            Tuple{Int,Int,Matrix{Tachikoma.ColorRGB}}[],
        )
        Tachikoma.view(_m, _f2)
    end

    # ── Exercise overlay renders ────────────────────────────────────────────
    _m.active_tab = 1

    # Help overlay
    _m.show_help = true
    _buf3 = Buffer(_rect)
    _f3 = Frame(
        _buf3,
        _rect,
        Tachikoma.GraphicsRegion[],
        Tuple{Int,Int,Matrix{Tachikoma.ColorRGB}}[],
    )
    Tachikoma.view(_m, _f3)
    _m.show_help = false

    # Toast
    push_toast!(_m, "Test toast"; style = :success, icon = "✓", hint = "[t] test")
    _buf4 = Buffer(_rect)
    _f4 = Frame(
        _buf4,
        _rect,
        Tachikoma.GraphicsRegion[],
        Tuple{Int,Int,Matrix{Tachikoma.ColorRGB}}[],
    )
    Tachikoma.view(_m, _f4)
    dismiss_toast!(_m)

    # Modal
    _m.modal = Modal(
        title = "Confirm",
        message = "Test modal",
        confirm_label = "OK",
        cancel_label = "Cancel",
    )
    _buf5 = Buffer(_rect)
    _f5 = Frame(
        _buf5,
        _rect,
        Tachikoma.GraphicsRegion[],
        Tuple{Int,Int,Matrix{Tachikoma.ColorRGB}}[],
    )
    Tachikoma.view(_m, _f5)
    _m.modal = nothing

    # ── Exercise key event handlers ─────────────────────────────────────────
    # These compile the update! dispatch paths without side effects

    # Navigation keys
    for tab = 1:6
        _m.active_tab = tab
        Tachikoma.update!(_m, KeyEvent(:up))
        Tachikoma.update!(_m, KeyEvent(:down))
    end

    # Tab switching
    _m.active_tab = 1
    _m.quit = false
    Tachikoma.update!(_m, KeyEvent(:char, '2'))
    _m.quit = false
    Tachikoma.update!(_m, KeyEvent(:char, '1'))
    _m.quit = false

    # Help toggle
    Tachikoma.update!(_m, KeyEvent(:char, '?'))
    _m.show_help && Tachikoma.update!(_m, KeyEvent(:escape))
    _m.quit = false

    # Modal keys
    _m.modal = Modal(
        title = "Test",
        message = "Test",
        confirm_label = "OK",
        cancel_label = "Cancel",
    )
    _m.modal_action = nothing
    _m.modal_target = nothing
    Tachikoma.update!(_m, KeyEvent(:left))
    Tachikoma.update!(_m, KeyEvent(:right))
    Tachikoma.update!(_m, KeyEvent(:escape))
    _m.quit = false

    # Toast key handling
    push_toast!(_m, "Test"; style = :text)
    Tachikoma.update!(_m, KeyEvent(:escape))
    _m.quit = false

    # TaskEvent handling — exercise the update! dispatch for task results
    Tachikoma.update!(_m, TaskEvent(:fetch_project, _m.project_info))
    Tachikoma.update!(_m, TaskEvent(:fetch_installed, _fake_pkgs))
    _m.quit = false

    # ── Exercise the Tachikoma terminal pipeline headlessly ────────────
    # Precompiles with_terminal, draw!, flush!, dispatch_event!,
    # AppOverlay, and buffer diffing — internal Tachikoma code paths that
    # otherwise require ~4s of JIT on first call.
    # We call with_terminal + draw! directly instead of app() because
    # app() calls init!() which spawns background tasks & repeating
    # timers that hang the precompilation process.
    _m2 = PkgTUIApp()
    _m2.installed.packages = _fake_pkgs
    _m2.installed.filtered = _fake_pkgs
    _m2.installed.loading = false
    _m2.project_info = ProjectInfo(name = "PrecompileEnv", dep_count = 2, is_package = true)
    # Suppress "stty: Inappropriate ioctl" warnings: Tachikoma's with_terminal
    # eagerly evaluates _tty_size("/dev/null") which shells out to `stty size`.
    _prev_stderr = stderr
    redirect_stderr(devnull)
    Tachikoma.with_terminal(;
        tty_out = "/dev/null",
        tty_size = (rows = 40, cols = 120),
    ) do _t
        _overlay = Tachikoma.AppOverlay()

        # First draw — exercises Frame construction, view, flush!, ANSI output
        Tachikoma.draw!(_t) do _f
            Tachikoma.view(_m2, _f)
            Tachikoma.render_overlay!(_overlay, _f)
        end

        # Second draw with different tab — exercises buffer diffing (changed cells)
        _m2.active_tab = 2
        Tachikoma.draw!(_t) do _f
            Tachikoma.view(_m2, _f)
        end

        # Exercise dispatch_event! (compiles the full event→update! pipeline)
        Tachikoma.dispatch_event!(_t, _overlay, _m2, KeyEvent(:down), true)
        _m2.quit = false
        Tachikoma.dispatch_event!(_t, _overlay, _m2, KeyEvent(:up), true)
        _m2.quit = false

        # Exercise TaskQueue drain (used every frame in app loop)
        _tq = TaskQueue()
        spawn_task!(_tq, :_precompile_test) do
            42
        end
        Tachikoma.drain_tasks!(_tq) do _tevt
            Tachikoma.dispatch_event!(_t, _overlay, _m2, _tevt, true)
        end
        close(_tq.channel)
        _m2.quit = false
    end
    redirect_stderr(_prev_stderr)
end
