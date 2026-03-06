# ──────────────────────────────────────────────────────────────────────────────
# Profiling integration tests
#
# These tests exercise the load-time profiling pipeline using Tachikoma's
# TestBackend for headless rendering verification.
# ──────────────────────────────────────────────────────────────────────────────

@testsnippet BufReader begin
    """Read a single character from a Buffer at (x, y)."""
    function buf_char(buf, x, y)
        area = buf.area
        idx = (y - area.y) * area.width + (x - area.x) + 1
        return buf.content[idx].char
    end

    """Read an entire row from a Buffer as a String."""
    function buf_row(buf, y)
        area = buf.area
        return String([buf_char(buf, x, y) for x = area.x:(area.x+area.width-1)])
    end

    """Join all rows of a Buffer into a single string for searching."""
    function buf_text(buf)
        area = buf.area
        return join([buf_row(buf, y) for y = area.y:(area.y+area.height-1)], "\n")
    end
end

# ── Unit: _measure_load_times with stdlib packages ───────────────────────────

@testitem "_measure_load_times with stdlib" tags = [:profiling] begin
    import Pkg
    using PkgTUI: _measure_load_times

    # Use the current project directory so the subprocess can resolve packages.
    proj = Pkg.project()
    proj_dir = dirname(proj.path)

    # Time a stdlib package that is in the test project's manifest
    timings = _measure_load_times(["UUIDs"], proj_dir)
    @test length(timings) == 1
    name, secs = timings[1]
    @test name == "UUIDs"
    @test secs > 0.0   # positive load time

    # Time multiple packages from the test project deps in parallel
    # (only use packages that are in test/Project.toml to avoid sandbox issues)
    timings2 = _measure_load_times(["TOML", "UUIDs"], proj_dir)
    @test length(timings2) == 2
    for (n, t) in timings2
        @test n in ("TOML", "UUIDs")
        @test t > 0.0
    end
end

# ── Unit: run_precompile_profiling end-to-end ────────────────────────────────

@testitem "run_precompile_profiling" tags = [:profiling] begin
    import Pkg
    using PkgTUI: run_precompile_profiling

    proj = Pkg.project()
    proj_dir = dirname(proj.path)
    dep_names = collect(String, keys(proj.dependencies))

    @test !isempty(dep_names)

    timings = run_precompile_profiling(proj_dir, dep_names)
    @test !isempty(timings)

    # Results should be sorted descending by time
    times = [t for (_, t) in timings]
    @test issorted(times; rev = true)

    # At least some should have positive times (not all err = -1.0)
    positive_count = count(t -> t > 0.0, times)
    @test positive_count > 0
end

# ── Unit: _measure_load_times edge cases ─────────────────────────────────────

@testitem "_measure_load_times edge cases" tags = [:profiling, :fast] begin
    import Pkg
    using PkgTUI: _measure_load_times, run_precompile_profiling

    proj = Pkg.project()
    proj_dir = dirname(proj.path)

    # Empty list → empty result
    @test isempty(_measure_load_times(String[], proj_dir))
    @test isempty(run_precompile_profiling(proj_dir, String[]))

    # Nonexistent package → -1.0 error sentinel or filtered out
    timings = _measure_load_times(["__NoSuchPackage12345__"], proj_dir)
    if !isempty(timings)
        @test timings[1][2] == -1.0
    end
end

# ── Integration: TaskEvent flow through update! ─────────────────────────────

@testitem "profiling TaskEvent flow" tags = [:profiling, :integration] begin
    import Pkg
    using Tachikoma
    using PkgTUI: PkgTUIApp, PackageMetrics, run_precompile_profiling

    m = PkgTUIApp()
    m.metrics.metrics = [
        PackageMetrics(
            name = "Tachikoma",
            disk_size_bytes = Int64(5_000_000),
            is_direct = true,
        ),
        PackageMetrics(name = "Match", disk_size_bytes = Int64(100_000), is_direct = true),
        PackageMetrics(name = "TOML", disk_size_bytes = Int64(50_000), is_direct = true),
        PackageMetrics(
            name = "SomeIndirect",
            disk_size_bytes = Int64(10_000),
            is_direct = false,
        ),
    ]
    m.metrics.profiling = true

    # Get real timings
    proj = Pkg.project()
    proj_dir = dirname(proj.path)
    dep_names = collect(String, keys(proj.dependencies))
    timings = run_precompile_profiling(proj_dir, dep_names)

    # Simulate the :compile_profile TaskEvent
    Tachikoma.update!(m, Tachikoma.TaskEvent(:compile_profile, timings))

    @test m.metrics.profiling == false
    @test m.metrics.profile_progress == 1.0

    # Deps that ARE in timings should have non-zero compile_time_seconds
    timed_names = Set(name for (name, _) in timings)
    for mi in m.metrics.metrics
        if mi.name in timed_names
            @test mi.compile_time_seconds != 0.0
        end
    end

    # Deps NOT in timings should stay at 0.0
    for mi in m.metrics.metrics
        if !(mi.name in timed_names)
            @test mi.compile_time_seconds == 0.0
        end
    end
end

# ── Integration: TestBackend render verification ─────────────────────────────

@testitem "metrics view renders timings (TestBackend)" tags = [:profiling, :view] setup =
    [BufReader] begin
    using Tachikoma
    const T = Tachikoma
    using PkgTUI: PkgTUIApp, PackageMetrics, render_metrics_tab, format_time

    area = Rect(1, 1, 120, 30)

    # ── Test 1: render with valid timings — no "err" should appear ──
    m = PkgTUIApp()
    m.active_tab = 5
    m.metrics.metrics = [
        PackageMetrics(
            name = "FastPkg",
            disk_size_bytes = Int64(500_000),
            compile_time_seconds = 0.350,
            is_direct = true,
        ),
        PackageMetrics(
            name = "SlowPkg",
            disk_size_bytes = Int64(2_000_000),
            compile_time_seconds = 2.5,
            is_direct = true,
        ),
        PackageMetrics(
            name = "TinyPkg",
            disk_size_bytes = Int64(10_000),
            compile_time_seconds = 0.012,
            is_direct = false,
        ),
    ]

    buf = T.Buffer(area)
    render_metrics_tab(m, area, buf)
    full_text = buf_text(buf)

    @test occursin("350 ms", full_text)   # 0.350 s → 350 ms
    @test occursin("2500 ms", full_text)  # 2.5 s → 2500 ms
    @test occursin("12.0 ms", full_text)  # 0.012 s → 12.0 ms
    @test !occursin("err", full_text)     # no errors expected

    # ── Test 2: render with errored package — "err" SHOULD appear ──
    m2 = PkgTUIApp()
    m2.active_tab = 5
    m2.metrics.metrics = [
        PackageMetrics(
            name = "BrokenPkg",
            disk_size_bytes = Int64(100_000),
            compile_time_seconds = -1.0,
            is_direct = true,
        ),
        PackageMetrics(
            name = "GoodPkg",
            disk_size_bytes = Int64(200_000),
            compile_time_seconds = 0.1,
            is_direct = true,
        ),
    ]

    buf2 = T.Buffer(area)
    render_metrics_tab(m2, area, buf2)
    full_text2 = buf_text(buf2)

    @test occursin("err", full_text2)
    @test occursin("100 ms", full_text2)

    # ── Test 3: render with unmeasured packages — "—" should appear ──
    m3 = PkgTUIApp()
    m3.active_tab = 5
    m3.metrics.metrics = [
        PackageMetrics(
            name = "UntimedPkg",
            disk_size_bytes = Int64(300_000),
            compile_time_seconds = 0.0,
            is_direct = false,
        ),
    ]

    buf3 = T.Buffer(area)
    render_metrics_tab(m3, area, buf3)
    full_text3 = buf_text(buf3)

    @test occursin("—", full_text3)
end

# ── Integration: full profiling with TestBackend render ──────────────────────

@testitem "full profiling → render (TestBackend)" tags = [:profiling, :integration] begin
    import Pkg
    using Tachikoma
    const T = Tachikoma
    using PkgTUI:
        PkgTUIApp, PackageMetrics, run_precompile_profiling, render_metrics_tab, format_time

    proj = Pkg.project()
    proj_dir = dirname(proj.path)
    dep_names = collect(String, keys(proj.dependencies))

    # Run actual profiling
    timings = run_precompile_profiling(proj_dir, dep_names)
    @test !isempty(timings)

    # Build model with metrics for all deps
    m = PkgTUIApp()
    m.active_tab = 5
    for name in dep_names
        push!(
            m.metrics.metrics,
            PackageMetrics(name = name, disk_size_bytes = Int64(100_000), is_direct = true),
        )
    end

    # Apply timings the same way the :compile_profile handler does
    timing_map = Dict(name => secs for (name, secs) in timings)
    for mi in m.metrics.metrics
        mi.compile_time_seconds = get(timing_map, mi.name, 0.0)
    end

    # Verify we got real data
    err_count = count(mi -> mi.compile_time_seconds < 0.0, m.metrics.metrics)
    timed_count = count(mi -> mi.compile_time_seconds > 0.0, m.metrics.metrics)
    @test timed_count > 0

    # Render and check
    area = Rect(1, 1, 120, 30)
    buf = T.Buffer(area)
    render_metrics_tab(m, area, buf)

    @info "Profiling results" dep_names timings timed_count err_count
end

# ── Smoke: profiling from a temporary environment ───────────────────────────

@testitem "profiling in temp env with stdlib" tags = [:profiling] setup = [TempEnv] begin
    import Pkg
    using PkgTUI: _measure_load_times

    with_temp_env() do dir
        Pkg.add("TOML")

        timings = _measure_load_times(["TOML"], dir)
        @test length(timings) == 1
        name, secs = timings[1]
        @test name == "TOML"
        @test secs > 0.0
    end
end
