@testsnippet TempEnv begin
    import Pkg
    using UUIDs

    """Create a temporary environment for testing."""
    function with_temp_env(f)
        mktempdir() do dir
            old = Base.active_project()
            try
                Pkg.activate(dir)
                f(dir)
            finally
                if old !== nothing
                    Pkg.activate(old)
                end
            end
        end
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Model tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "Model construction" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, ProjectInfo, InstalledState, PackageRow

    # Default construction
    m = PkgTUIApp()
    @test m.quit == false
    @test m.tick == 0
    @test m.active_tab == 1
    @test length(m.tab_names) == 6
    @test m.show_help == false
    @test m.modal === nothing

    # Project info defaults
    pi = ProjectInfo()
    @test pi.name === nothing
    @test pi.is_package == false
    @test pi.dep_count == 0
    @test pi.is_workspace == false

    # Installed state defaults
    ist = InstalledState()
    @test isempty(ist.packages)
    @test isempty(ist.filtered)
    @test ist.selected == 1
    @test ist.show_indirect == true
    @test ist.adding == false
end

@testitem "PackageRow construction" tags = [:unit, :fast] begin
    using UUIDs
    using PkgTUI: PackageRow

    uuid = UUID("12345678-1234-1234-1234-123456789abc")
    row = PackageRow(name = "TestPkg", uuid = uuid, version = "1.2.3", is_direct_dep = true)
    @test row.name == "TestPkg"
    @test row.version == "1.2.3"
    @test row.is_direct_dep == true
    @test row.is_pinned == false
    @test isempty(row.dependencies)
end

# ──────────────────────────────────────────────────────────────────────────────
# Backend tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "fetch_project_info" tags = [:unit] setup = [TempEnv] begin
    using PkgTUI: fetch_project_info, ProjectInfo

    with_temp_env() do dir
        info = fetch_project_info()
        @test info isa ProjectInfo
        @test info.path !== nothing
    end
end

@testitem "fetch_installed in temp env" tags = [:unit] setup = [TempEnv] begin
    using PkgTUI: fetch_installed, PackageRow

    with_temp_env() do dir
        io = IOBuffer()
        packages = fetch_installed(io)
        @test packages isa Vector{PackageRow}
        # A fresh temp env should have few/no packages
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Filter logic tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "apply_filter! filters by name" tags = [:unit, :fast] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: InstalledState, PackageRow, apply_filter!

    st = InstalledState()
    st.packages = [
        PackageRow(name = "Alpha", uuid = UUID("11111111-0000-0000-0000-000000000001")),
        PackageRow(
            name = "Beta",
            uuid = UUID("11111111-0000-0000-0000-000000000002"),
            is_direct_dep = true,
        ),
        PackageRow(
            name = "AlphaExtra",
            uuid = UUID("11111111-0000-0000-0000-000000000003"),
        ),
    ]

    # No filter → all packages
    apply_filter!(st)
    @test length(st.filtered) == 3

    # Filter by "alpha"
    set_text!(st.filter_input, "alpha")
    apply_filter!(st)
    @test length(st.filtered) == 2
    @test all(p -> occursin("Alpha", p.name), st.filtered)

    # Hide indirect
    st.show_indirect = false
    set_text!(st.filter_input, "")
    apply_filter!(st)
    @test length(st.filtered) == 1
    @test st.filtered[1].name == "Beta"
end

# ──────────────────────────────────────────────────────────────────────────────
# Registry search tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "fuzzy_match" tags = [:unit, :fast] begin
    using PkgTUI: fuzzy_match

    @test fuzzy_match("dataframes", "df") == true
    @test fuzzy_match("dataframes", "data") == true
    @test fuzzy_match("dataframes", "xyz") == false
    @test fuzzy_match("abc", "abc") == true
    @test fuzzy_match("abc", "abcd") == false
end

@testitem "search_registry with mock data" tags = [:unit, :fast] begin
    using PkgTUI: RegistryPackage, search_registry

    index = [
        RegistryPackage(name = "DataFrames"),
        RegistryPackage(name = "CSV"),
        RegistryPackage(name = "Plots"),
        RegistryPackage(name = "DataStructures"),
        RegistryPackage(name = "HTTP"),
    ]

    # Exact match
    results = search_registry(index, "CSV")
    @test length(results) >= 1
    @test results[1].name == "CSV"

    # Prefix match
    results = search_registry(index, "Data")
    @test length(results) == 2
    @test all(r -> startswith(r.name, "Data"), results)

    # Empty query returns all (up to max)
    results = search_registry(index, "")
    @test length(results) == 5
end

# ──────────────────────────────────────────────────────────────────────────────
# Conflict extraction tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "extract_conflicts" tags = [:unit, :fast] begin
    using PkgTUI: UpdateInfo, ConflictInfo, extract_conflicts

    updates = [
        UpdateInfo(name = "A", current_version = "1.0", can_update = true),
        UpdateInfo(
            name = "B",
            current_version = "2.0",
            can_update = false,
            latest_available = "3.0",
            blocker = "C",
        ),
        UpdateInfo(
            name = "D",
            current_version = "1.5",
            can_update = false,
            latest_available = "2.0",
            blocker = "[compat]",
        ),
    ]

    conflicts = extract_conflicts(updates)
    @test length(conflicts) == 2
    @test conflicts[1].package == "B"
    @test conflicts[1].blocked_by == "C"
    @test conflicts[2].package == "D"
    @test conflicts[2].blocked_by == "[compat]"
end

# ──────────────────────────────────────────────────────────────────────────────
# Formatting tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "format_bytes" tags = [:unit, :fast] begin
    using PkgTUI: format_bytes

    @test format_bytes(Int64(500)) == "500 B"
    @test format_bytes(Int64(1024)) == "1.0 KB"
    @test format_bytes(Int64(1048576)) == "1.0 MB"
    @test format_bytes(Int64(1073741824)) == "1.0 GB"
end

@testitem "format_time" tags = [:unit, :fast] begin
    using PkgTUI: format_time

    @test format_time(0.0) == "—"
    @test format_time(0.5) == "500 ms"
    @test format_time(1.5) == "1500 ms"
    @test format_time(0.005) == "5.0 ms"
    @test format_time(0.0023) == "2.3 ms"
    @test format_time(0.00012) == "< 1 ms"
    @test format_time(-1.0) == "err"
end


# ──────────────────────────────────────────────────────────────────────────────
# View rendering tests (TestBackend)
# ──────────────────────────────────────────────────────────────────────────────

@testitem "render installed tab" tags = [:view] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, apply_filter!, render_installed_tab

    m = PkgTUIApp()
    m.installed.packages = [
        PackageRow(
            name = "Example",
            uuid = UUID("7876af07-990d-54b4-ab0e-23690620f79a"),
            version = "1.0.0",
            is_direct_dep = true,
        ),
        PackageRow(
            name = "HTTP",
            uuid = UUID("cd3eb016-35fb-5094-929b-558a96fad6f3"),
            version = "1.10.0",
            is_direct_dep = true,
        ),
    ]
    m.installed.loading = false
    apply_filter!(m.installed)

    # Verify rendering doesn't throw
    area = Rect(1, 1, 100, 30)
    buf = Tachikoma.Buffer(area)
    render_installed_tab(m, area, buf)
    @test true  # no-throw

    # Also test loading state
    m.installed.loading = true
    buf2 = Tachikoma.Buffer(area)
    render_installed_tab(m, area, buf2)
    @test true

    # Also test empty state
    m.installed.loading = false
    m.installed.packages = PackageRow[]
    apply_filter!(m.installed)
    buf3 = Tachikoma.Buffer(area)
    render_installed_tab(m, area, buf3)
    @test true
end

@testitem "render updates tab" tags = [:view] begin
    using Tachikoma
    using PkgTUI:
        PkgTUIApp,
        UpdateInfo,
        ConflictInfo,
        DryRunDiff,
        DryRunEntry,
        extract_conflicts,
        render_updates_tab,
        handle_updates_keys!

    m = PkgTUIApp()
    area = Rect(1, 1, 100, 30)

    # Empty updates
    buf = Tachikoma.Buffer(area)
    render_updates_tab(m, area, buf)
    @test true

    # With updates
    m.updates_state.updates = [
        UpdateInfo(
            name = "Foo",
            current_version = "1.0.0",
            latest_compatible = "2.0.0",
            can_update = true,
        ),
        UpdateInfo(
            name = "Bar",
            current_version = "0.5.0",
            latest_available = "1.0.0",
            can_update = false,
            blocker = "Baz",
        ),
    ]
    m.conflicts.conflicts = extract_conflicts(m.updates_state.updates)
    buf2 = Tachikoma.Buffer(area)
    render_updates_tab(m, area, buf2)
    @test true

    # Dry-run view
    m.updates_state.show_dry_run = true
    m.updates_state.dry_run_output = DryRunDiff(
        entries = [
            DryRunEntry(
                name = "Foo",
                kind = :upgraded,
                old_version = "1.0.0",
                new_version = "2.0.0",
            ),
            DryRunEntry(name = "NewPkg", kind = :added, new_version = "0.1.0"),
        ],
    )
    buf3 = Tachikoma.Buffer(area)
    render_updates_tab(m, area, buf3)
    @test true

    # Dry-run view with no changes
    m.updates_state.dry_run_output = DryRunDiff()
    buf4 = Tachikoma.Buffer(area)
    render_updates_tab(m, area, buf4)
    @test true

    # Dry-run view with error
    m.updates_state.dry_run_output = DryRunDiff(error = "something went wrong")
    buf5 = Tachikoma.Buffer(area)
    render_updates_tab(m, area, buf5)
    @test true

    # Dry-run section toggling
    m.updates_state.dry_run_output = DryRunDiff(
        entries = [
            DryRunEntry(
                name = "Foo",
                kind = :upgraded,
                old_version = "1.0.0",
                new_version = "2.0.0",
            ),
            DryRunEntry(
                name = "Bar",
                kind = :upgraded,
                old_version = "0.5.0",
                new_version = "1.0.0",
            ),
            DryRunEntry(name = "OldPkg", kind = :removed, old_version = "3.0.0"),
            DryRunEntry(name = "NewPkg", kind = :added, new_version = "0.1.0"),
        ],
    )
    m.updates_state.dry_run_sections = Dict{Symbol,Bool}()
    m.updates_state.dry_run_selected = 1
    m.updates_state.dry_run_scroll = 0

    # Collapse upgraded section via Enter
    handle_updates_keys!(m, KeyEvent(:enter))
    @test m.updates_state.dry_run_sections[:upgraded] == false

    # Navigate down and re-render
    handle_updates_keys!(m, KeyEvent(:down))
    buf6 = Tachikoma.Buffer(area)
    render_updates_tab(m, area, buf6)
    @test true
end

@testitem "render registry tab" tags = [:view] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, render_registry_tab

    m = PkgTUIApp()
    area = Rect(1, 1, 100, 30)

    # Loading state
    m.registry.index_loaded = false
    buf = Tachikoma.Buffer(area)
    render_registry_tab(m, area, buf)
    @test true

    # With results
    m.registry.index_loaded = true
    m.registry.results = [
        RegistryPackage(name = "TestPkg", latest_version = "1.0.0"),
        RegistryPackage(name = "AnotherPkg"),
    ]
    m.registry.selected = 1
    buf2 = Tachikoma.Buffer(area)
    render_registry_tab(m, area, buf2)
    @test true
end

@testitem "render dependencies tab" tags = [:view] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, render_dependencies_tab

    m = PkgTUIApp()
    area = Rect(1, 1, 100, 30)

    # Empty state (no packages)
    buf = Tachikoma.Buffer(area)
    render_dependencies_tab(m, area, buf)
    @test true

    # With packages (two-panel explorer)
    uuid_a = UUID("aaaaaaaa-0000-0000-0000-000000000001")
    uuid_b = UUID("bbbbbbbb-0000-0000-0000-000000000002")
    packages = [
        PackageRow(
            name = "A",
            uuid = uuid_a,
            version = "1.0",
            is_direct_dep = true,
            dependencies = [uuid_b],
        ),
        PackageRow(name = "B", uuid = uuid_b, version = "2.0", is_direct_dep = false),
    ]
    m.installed.packages = packages
    m.deps.graph_selected = 1
    buf2 = Tachikoma.Buffer(area)
    render_dependencies_tab(m, area, buf2)
    @test true
end

@testitem "render metrics tab" tags = [:view] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, PackageMetrics, render_metrics_tab

    m = PkgTUIApp()
    area = Rect(1, 1, 100, 30)

    # Empty state
    buf = Tachikoma.Buffer(area)
    render_metrics_tab(m, area, buf)
    @test true

    # With metrics data
    m.metrics.metrics = [
        PackageMetrics(
            name = "Big",
            disk_size_bytes = Int64(1048576),
            compile_time_seconds = 5.0,
            is_direct = true,
        ),
        PackageMetrics(
            name = "Small",
            disk_size_bytes = Int64(1024),
            compile_time_seconds = 0.5,
            is_direct = false,
        ),
    ]
    buf2 = Tachikoma.Buffer(area)
    render_metrics_tab(m, area, buf2)
    @test true

    # Profiling state
    m.metrics.profiling = true
    m.metrics.profile_progress = 0.5
    buf3 = Tachikoma.Buffer(area)
    render_metrics_tab(m, area, buf3)
    @test true
end

# ──────────────────────────────────────────────────────────────────────────────
# Key event handling tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "global key handling" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp

    m = PkgTUIApp()

    # Tab switching
    Tachikoma.update!(m, KeyEvent('2'))
    @test m.active_tab == 2

    Tachikoma.update!(m, KeyEvent('3'))
    @test m.active_tab == 3

    # Switch to tab 1 so the registry search input doesn't capture keys
    Tachikoma.update!(m, KeyEvent('1'))
    @test m.active_tab == 1

    # Help toggle
    @test m.show_help == false
    Tachikoma.update!(m, KeyEvent('?'))
    @test m.show_help == true
    Tachikoma.update!(m, KeyEvent('?'))
    @test m.show_help == false

    # Log toggle
    @test m.show_log == true
    Tachikoma.update!(m, KeyEvent('l'))
    @test m.show_log == false
    Tachikoma.update!(m, KeyEvent('l'))
    @test m.show_log == true

    # Quit
    @test m.quit == false
    Tachikoma.update!(m, KeyEvent('q'))
    @test m.quit == true

    # Environment switcher
    m2 = PkgTUIApp()
    @test m2.env_switching == false
    Tachikoma.update!(m2, KeyEvent('e'))
    @test m2.env_switching == true
end

@testitem "installed tab key handling" tags = [:event] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, apply_filter!

    m = PkgTUIApp()
    m.installed.packages = [
        PackageRow(
            name = "A",
            uuid = UUID("aaaaaaaa-0000-0000-0000-000000000001"),
            is_direct_dep = true,
            version = "1.0",
        ),
        PackageRow(
            name = "B",
            uuid = UUID("bbbbbbbb-0000-0000-0000-000000000002"),
            is_direct_dep = true,
            version = "2.0",
        ),
    ]
    apply_filter!(m.installed)
    m.active_tab = 1

    # Arrow navigation
    @test m.installed.selected == 1
    Tachikoma.update!(m, KeyEvent(:down))
    @test m.installed.selected == 2
    Tachikoma.update!(m, KeyEvent(:up))
    @test m.installed.selected == 1

    # Toggle indirect
    @test m.installed.show_indirect == true
    Tachikoma.update!(m, KeyEvent('t'))
    @test m.installed.show_indirect == false

    # Enter add mode
    @test m.installed.adding == false
    Tachikoma.update!(m, KeyEvent('a'))
    @test m.installed.adding == true
    Tachikoma.update!(m, KeyEvent(:escape))
    @test m.installed.adding == false
end

@testitem "update pinned package shows toast" tags = [:event] begin
    using Tachikoma
    using UUIDs
    using PkgTUI:
        PkgTUIApp,
        PackageRow,
        UpdateInfo,
        apply_filter!,
        handle_installed_keys!,
        handle_updates_keys!

    # ── Installed tab: 'u' on pinned package shows toast notification ──
    m = PkgTUIApp()
    m.installed.packages = [
        PackageRow(
            name = "PinnedPkg",
            uuid = UUID("aaaaaaaa-0000-0000-0000-000000000001"),
            is_direct_dep = true,
            version = "1.2.3",
            is_pinned = true,
        ),
        PackageRow(
            name = "FreePkg",
            uuid = UUID("bbbbbbbb-0000-0000-0000-000000000002"),
            is_direct_dep = true,
            version = "2.0.0",
            is_pinned = false,
        ),
    ]
    apply_filter!(m.installed)
    m.active_tab = 1
    m.installed.selected = 1  # PinnedPkg

    # Press 'u' on the pinned package
    handle_installed_keys!(m, KeyEvent('u'))

    # Should show a toast notification instead of a modal
    @test !isempty(m.toasts)
    @test occursin("pinned", m.toasts[end].message)
    @test m.toasts[end].style == :warning

    # Dismiss the toast
    empty!(m.toasts)

    # Press 'u' on a non-pinned package — should NOT show toast
    m.installed.selected = 2  # FreePkg
    handle_installed_keys!(m, KeyEvent('u'))
    @test isempty(m.toasts)  # no toast for non-pinned packages

    # ── Updates tab: 'u' on pinned package shows toast ──
    m2 = PkgTUIApp()
    m2.updates_state.updates =
        [UpdateInfo(name = "PinnedPkg", current_version = "1.2.3", can_update = true)]
    m2.installed.packages = [
        PackageRow(
            name = "PinnedPkg",
            uuid = UUID("aaaaaaaa-0000-0000-0000-000000000001"),
            is_direct_dep = true,
            version = "1.2.3",
            is_pinned = true,
        ),
    ]
    m2.updates_state.selected = 1

    handle_updates_keys!(m2, KeyEvent('u'))
    @test !isempty(m2.toasts)
    @test occursin("pinned", m2.toasts[end].message)
    @test m2.toasts[end].style == :warning
end

@testitem "updates tab conflicts focus" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, ConflictInfo, UpdateInfo, handle_updates_keys!

    m = PkgTUIApp()
    m.active_tab = 2

    # Add conflicts
    m.conflicts.conflicts = [
        ConflictInfo(package = "Foo", held_at = "1.0", latest = "2.0", blocked_by = "Bar"),
        ConflictInfo(package = "Baz", held_at = "0.5", latest = "1.0", blocked_by = "Qux"),
    ]
    m.updates_state.updates =
        [UpdateInfo(name = "Foo", current_version = "1.0", can_update = false)]

    # 'c' toggles focus to conflicts panel
    @test m.updates_state.conflicts_focused == false
    consumed = handle_updates_keys!(m, KeyEvent('c'))
    @test consumed == true
    @test m.updates_state.conflicts_focused == true

    # Arrow keys now navigate conflicts
    @test m.conflicts.selected == 1
    consumed = handle_updates_keys!(m, KeyEvent(:down))
    @test consumed == true
    @test m.conflicts.selected == 2

    # 'c' toggles back to updates
    consumed = handle_updates_keys!(m, KeyEvent('c'))
    @test consumed == true
    @test m.updates_state.conflicts_focused == false
end

@testitem "updates tab conflicts empty toast" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, handle_updates_keys!

    m = PkgTUIApp()
    m.active_tab = 2

    # No conflicts — 'c' should produce a toast
    @test isempty(m.conflicts.conflicts)
    consumed = handle_updates_keys!(m, KeyEvent('c'))
    @test consumed == true
    @test m.updates_state.conflicts_focused == false
    @test !isempty(m.toasts)
    @test occursin("No conflicts", m.toasts[end].message)
end

@testitem "graph view renders with packages" tags = [:view] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, render_dependencies_tab

    m = PkgTUIApp()
    area = Rect(1, 1, 80, 20)
    buf = Tachikoma.Buffer(area)

    uuid_a = UUID("aaaaaaaa-0000-0000-0000-000000000001")
    uuid_b = UUID("bbbbbbbb-0000-0000-0000-000000000002")
    m.installed.packages = [
        PackageRow(
            name = "PkgA",
            uuid = uuid_a,
            version = "1.0",
            is_direct_dep = true,
            dependencies = [uuid_b],
        ),
        PackageRow(name = "PkgB", uuid = uuid_b, version = "2.0", is_direct_dep = false),
    ]
    m.deps.graph_selected = 1

    render_dependencies_tab(m, area, buf)
    @test true
end

@testitem "get_selected_dep_name" tags = [:view] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, get_selected_dep_name

    m = PkgTUIApp()

    # No packages — returns nothing
    name = get_selected_dep_name(m.deps, m)
    @test name === nothing

    # With packages
    uuid_a = UUID("aaaaaaaa-0000-0000-0000-000000000001")
    m.installed.packages =
        [PackageRow(name = "GraphPkg", uuid = uuid_a, is_direct_dep = true)]
    m.deps.graph_selected = 1

    name = get_selected_dep_name(m.deps, m)
    @test name == "GraphPkg"
end

@testitem "help flag in @main" tags = [:basic] begin
    using PkgTUI

    # Capture --help output via a Pipe
    old_stdout = stdout
    rd, wr = redirect_stdout()
    ret = PkgTUI.main(["--help"])
    @test ret == 0
    redirect_stdout(old_stdout)
    close(wr)
    help_text = read(rd, String)
    close(rd)
    @test occursin("PkgTUI", help_text)
    @test occursin("--project", help_text)
    @test occursin("--help", help_text)
end

# ──────────────────────────────────────────────────────────────────────────────
# Registry search key navigation tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "registry Escape preserves query" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.registry_index =
        [RegistryPackage(name = "DataFrames"), RegistryPackage(name = "CSV")]

    # Focus the search input and type a query
    m.registry.search_input =
        TextInput(; label = "  Search: ", text = "Data", focused = true)
    @test m.registry.search_input.focused == true

    # Press Escape — should unfocus but keep text
    handle_registry_keys!(m, KeyEvent(:escape))
    @test m.registry.search_input.focused == false
    @test text(m.registry.search_input) == "Data"
end

@testitem "registry down-arrow moves to results" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results =
        [RegistryPackage(name = "DataFrames"), RegistryPackage(name = "CSV")]
    m.registry.selected = 1

    # Focus search and type
    m.registry.search_input =
        TextInput(; label = "  Search: ", text = "Data", focused = true)

    # Press down-arrow — should unfocus search and put cursor on results
    handle_registry_keys!(m, KeyEvent(:down))
    @test m.registry.search_input.focused == false
    @test text(m.registry.search_input) == "Data"
    @test m.registry.selected >= 1
end

@testitem "registry up-arrow from top refocuses search" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results =
        [RegistryPackage(name = "DataFrames"), RegistryPackage(name = "CSV")]
    m.registry.selected = 1

    # Search is unfocused, selected is at 1 (top)
    m.registry.search_input =
        TextInput(; label = "  Search: ", text = "Data", focused = false)

    # Press up at position 1 — should focus search input
    handle_registry_keys!(m, KeyEvent(:up))
    @test m.registry.search_input.focused == true
    @test text(m.registry.search_input) == "Data"
end

@testitem "installed filter Escape preserves text" tags = [:event] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, apply_filter!, handle_installed_keys!

    m = PkgTUIApp()
    m.active_tab = 1
    m.installed.packages = [
        PackageRow(
            name = "Alpha",
            uuid = UUID("aaaaaaaa-0000-0000-0000-000000000001"),
            is_direct_dep = true,
            version = "1.0",
        ),
    ]
    apply_filter!(m.installed)

    # Focus filter and type
    m.installed.filter_input =
        TextInput(; label = "  Filter: ", text = "alp", focused = true)

    # Press Escape — should unfocus but keep text
    handle_installed_keys!(m, KeyEvent(:escape))
    @test m.installed.filter_input.focused == false
    @test text(m.installed.filter_input) == "alp"
end

@testitem "installed up-arrow from top focuses filter" tags = [:event] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, apply_filter!, handle_installed_keys!

    m = PkgTUIApp()
    m.active_tab = 1
    m.installed.packages = [
        PackageRow(
            name = "A",
            uuid = UUID("aaaaaaaa-0000-0000-0000-000000000001"),
            is_direct_dep = true,
            version = "1.0",
        ),
        PackageRow(
            name = "B",
            uuid = UUID("bbbbbbbb-0000-0000-0000-000000000002"),
            is_direct_dep = true,
            version = "2.0",
        ),
    ]
    apply_filter!(m.installed)
    m.installed.selected = 1

    # Press up at position 1 — should focus filter input
    handle_installed_keys!(m, KeyEvent(:up))
    @test m.installed.filter_input.focused == true
end

# ──────────────────────────────────────────────────────────────────────────────
# Triage feature tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "TriageState construction" tags = [:unit, :fast] begin
    using PkgTUI: TriageState

    tr = TriageState()
    @test tr.show == false
    @test tr.package_name == ""
    @test tr.error_message == ""
    @test tr.pkg_log == ""
end

@testitem "analyze_error suggestions" tags = [:unit, :fast] begin
    using PkgTUI: analyze_error

    # Compat error
    suggestions =
        analyze_error("Error in add: Unsatisfiable requirements detected for JuMP", "JuMP")
    @test any(s -> occursin("Compatibility", s), suggestions)
    @test any(s -> occursin("retry", lowercase(s)) || occursin("Retry", s), suggestions)

    # Not found error
    suggestions = analyze_error("Error in add: Package does not exist", "FakePkg")
    @test any(s -> occursin("not found", s), suggestions)

    # Network error
    suggestions = analyze_error("Error in add: DNS resolution failed timeout", "SomePkg")
    @test any(s -> occursin("network", lowercase(s)), suggestions)

    # Unknown error (fallback)
    suggestions = analyze_error("Error in add: something weird happened", "Pkg")
    @test any(s -> occursin("unexpected", lowercase(s)), suggestions)
    @test any(s -> occursin("retry", lowercase(s)) || occursin("[r]", s), suggestions)
end

@testitem "build_triage_content! populates scroll pane" tags = [:unit] begin
    using Tachikoma
    using PkgTUI: TriageState, ProjectInfo, build_triage_content!

    tr = TriageState()
    tr.package_name = "FailPkg"
    tr.error_message = "Error in add: Unsatisfiable requirements detected for package FailPkg"
    tr.pkg_log = "some log output"

    pi = ProjectInfo(name = "TestProject", path = "/tmp/test/Project.toml", dep_count = 5)

    build_triage_content!(tr, pi)

    # Lines are now stored in _lines field (scroll pane uses render callback for h-scroll)
    lines = tr._lines
    @test length(lines) > 5
    # Extract text from styled spans for content checks
    combined = join([join(s.content for s in line) for line in lines], "\n")
    @test occursin("FailPkg", combined)
    @test occursin("Julia version", combined)
    @test occursin("TestProject", combined)
    @test occursin("Suggestions", combined)
    @test occursin("Compatibility", combined)
end

@testitem "triage conflict-centric visualization" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: _parse_resolver_log, _build_ver_bars

    # Use the real BilevelJuMP conflict example from the user's scenario
    resolver_log = """
    Unsatisfiable requirements detected for package JuMP [4076af6c]:
    JuMP [4076af6c] log:
    ├─possible versions are: 0.18.3 - 1.30.0 or uninstalled
    ├─restricted to versions 1.29.4 - 1 by SolarPosition [5b9d1343], leaving only versions: 1.29.4 - 1.30.0
    └─restricted by compatibility requirements with BilevelJuMP [485130c0] to versions: 0.21.0 - 0.21.10 — no versions left
      └─BilevelJuMP [485130c0] log:
        ├─possible versions are: 0.1.0 - 0.6.2 or uninstalled
        └─restricted to versions 0.4.0 by an explicit requirement, leaving only versions: 0.4.0
    SolarPosition [5b9d1343] log:
    ├─possible versions are: 0.4.2 or uninstalled
    └─is fixed to version 0.4.2
    """

    pkgs = _parse_resolver_log(resolver_log)
    @test length(pkgs) == 3

    # Verify the parser captured BilevelJuMP's constraint range on JuMP
    jump_pkg = findfirst(p -> p.name == "JuMP", pkgs)
    @test jump_pkg !== nothing
    jump = pkgs[jump_pkg]
    conflict_c = findfirst(c -> c.is_conflict, jump.constraints)
    @test conflict_c !== nothing
    @test jump.constraints[conflict_c].source == "BilevelJuMP"
    @test jump.constraints[conflict_c].ranges == [("0.21.0", "0.21.10")]

    lines = _build_ver_bars(pkgs, 40)
    combined = join([join(s.content for s in line) for line in lines], "\n")

    # Should show conflict section for JuMP (the actual conflicted dependency)
    @test occursin("Conflict", combined)
    @test occursin("JuMP", combined)
    @test occursin("Available", combined)

    # Both constraint sources should appear as bars on JuMP's chart
    @test occursin("SolarPosition", combined)
    @test occursin("BilevelJuMP", combined)
    @test occursin("Intersection", combined)

    # Conflict constraint (BilevelJuMP) should appear BEFORE non-conflict (SolarPosition)
    bilevel_pos = findfirst("BilevelJuMP", combined)
    solar_pos = findfirst("SolarPosition", combined)
    @test bilevel_pos !== nothing
    @test solar_pos !== nothing
    @test first(bilevel_pos) < first(solar_pos)

    # Should NOT show separate package sections for other packages
    # (no "SolarPosition" header with its own Available/fixed bars,
    #  no "BilevelJuMP" header with its own Available/explicit bars)
    @test !occursin("explicit", combined)
    @test !occursin("fixed", combined)

    # Count "Available" — should appear exactly once (for JuMP only)
    @test count("Available", combined) == 1
end

@testitem "triage nested tree parsing" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: _parse_resolver_log, _build_ver_bars

    # Realistic nested Pkg resolver output where packages are indented
    # within the tree structure (this is how Pkg actually formats errors).
    nested_log = """
    Unsatisfiable requirements detected for package SolarPosition [5b9d1343]:
     SolarPosition [5b9d1343] log:
       ├─possible versions are: 0.4.2 or uninstalled
       ├─restricted by compatibility requirements with JuMP [4076af6c] to versions: 0.4.2
       │ └─JuMP [4076af6c] log:
       │   ├─possible versions are: 0.18.3 - 1.30.0 or uninstalled
       │   ├─restricted by compatibility requirements with BilevelJuMP [485130c0] to versions: 0.21.0 - 0.21.10
       │   │ └─BilevelJuMP [485130c0] log:
       │   │   ├─possible versions are: 0.1.0 - 0.6.2 or uninstalled
       │   │   └─restricted to versions 0.4.0 by an explicit requirement, leaving only versions: 0.4.0
       │   └─restricted by compatibility requirements with SolarPosition [5b9d1343] to versions: 1.29.4 - 1.30.0 — no versions left
       └─SolarPosition [5b9d1343] is fixed to version 0.4.2
    """

    pkgs = _parse_resolver_log(nested_log)
    @test length(pkgs) == 3

    # Verify packages are correctly identified
    names = [p.name for p in pkgs]
    @test "SolarPosition" in names
    @test "JuMP" in names
    @test "BilevelJuMP" in names

    # JuMP should be the conflict target (it has is_conflict constraints)
    jump_pkg = findfirst(p -> p.name == "JuMP", pkgs)
    jump = pkgs[jump_pkg]
    @test any(c -> c.is_conflict, jump.constraints)

    # JuMP's constraints should be from BilevelJuMP (non-conflict narrowing)
    # and SolarPosition (conflict — no versions left)
    bilevel_c = findfirst(c -> c.source == "BilevelJuMP", jump.constraints)
    @test bilevel_c !== nothing
    @test first(jump.constraints[bilevel_c].ranges)[1] == "0.21.0"

    solar_c = findfirst(c -> c.source == "SolarPosition", jump.constraints)
    @test solar_c !== nothing
    @test jump.constraints[solar_c].is_conflict == true

    # SolarPosition should have the "fixed" constraint (NOT attributed to BilevelJuMP)
    sp_pkg = findfirst(p -> p.name == "SolarPosition", pkgs)
    sp = pkgs[sp_pkg]
    @test any(c -> c.source == "fixed", sp.constraints)
    @test !any(c -> c.is_conflict, sp.constraints)

    # BilevelJuMP should have the "explicit" constraint only
    bp_pkg = findfirst(p -> p.name == "BilevelJuMP", pkgs)
    bp = pkgs[bp_pkg]
    @test any(c -> c.source == "explicit", bp.constraints)
    @test !any(c -> c.is_conflict, bp.constraints)

    # Build bars — JuMP should be the conflict target
    lines = _build_ver_bars(pkgs, 45)
    combined = join([join(s.content for s in line) for line in lines], "\n")
    @test occursin("Conflict: JuMP", combined)
    @test occursin("BilevelJuMP", combined)
    @test occursin("SolarPosition", combined)

    # BilevelJuMP (first range min=0.21.0) should appear BEFORE SolarPosition (first range min=1.29.4)
    bilevel_pos = findfirst("BilevelJuMP", combined)
    solar_pos = findfirst("SolarPosition", combined)
    @test first(bilevel_pos) < first(solar_pos)
end

@testitem "triage multi-range constraints" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: _parse_resolver_log, _build_ver_bars, _parse_ver_ranges

    # _parse_ver_ranges should split comma-separated ranges
    ranges = _parse_ver_ranges("0.0.1 - 3.1.1, 9.33.0 - 9.7.0")
    @test length(ranges) == 2
    @test ranges[1] == ("0.0.1", "3.1.1")
    @test ranges[2] == ("9.33.0", "9.7.0")

    # Single range still works
    ranges2 = _parse_ver_ranges("1.0.0 - 2.0.0")
    @test length(ranges2) == 1
    @test ranges2[1] == ("1.0.0", "2.0.0")

    # Single version (no dash)
    ranges3 = _parse_ver_ranges("0.4.0")
    @test length(ranges3) == 1
    @test ranges3[1] == ("0.4.0", "0.4.0")

    # "or uninstalled" is stripped
    ranges4 = _parse_ver_ranges("11.0.0 - 11.14.0 or uninstalled")
    @test length(ranges4) == 1
    @test ranges4[1] == ("11.0.0", "11.14.0")

    # Multi-range with "or uninstalled"
    ranges5 = _parse_ver_ranges("0.0.1 - 3.1.1, 9.33.0 - 10.0.0 or uninstalled")
    @test length(ranges5) == 2
    @test ranges5[1] == ("0.0.1", "3.1.1")
    @test ranges5[2] == ("9.33.0", "10.0.0")

    # Real ModelingToolkit-like conflict with multi-range constraint
    resolver_log = """
    Unsatisfiable requirements detected for package ModelingToolkit [961ee093]:
    ModelingToolkit [961ee093] log:
    ├─possible versions are: 0.0.1 - 11.14.0 or uninstalled
    ├─restricted by compatibility requirements with SymbolicUtils [d1185830] to versions: 0.0.1 - 3.1.1, 9.33.0 - 9.7.0 — no versions left
    ├─restricted by compatibility requirements with SolarPosition [5b9d1343] to versions: 11.0.0 - 11.14.0 or uninstalled — no versions left
    └─restricted to versions 11.0.0 - 11.14.0 by an explicit requirement, leaving only versions: 11.0.0 - 11.14.0
    SymbolicUtils [d1185830] log:
    ├─possible versions are: 0.0.1 - 3.5.0 or uninstalled
    └─is fixed to version 3.5.0
    SolarPosition [5b9d1343] log:
    ├─possible versions are: 0.4.2 or uninstalled
    └─is fixed to version 0.4.2
    """

    pkgs = _parse_resolver_log(resolver_log)
    @test length(pkgs) == 3

    # ModelingToolkit is the conflict target
    mt = pkgs[findfirst(p -> p.name == "ModelingToolkit", pkgs)]
    @test any(c -> c.is_conflict, mt.constraints)

    # SymbolicUtils constraint should have TWO ranges (multi-range)
    su_c = findfirst(c -> c.source == "SymbolicUtils", mt.constraints)
    @test su_c !== nothing
    @test mt.constraints[su_c].is_conflict == true
    @test length(mt.constraints[su_c].ranges) == 2
    @test mt.constraints[su_c].ranges[1] == ("0.0.1", "3.1.1")
    @test mt.constraints[su_c].ranges[2] == ("9.33.0", "9.7.0")

    # SolarPosition constraint should have ONE range (with "or uninstalled" stripped)
    sp_c = findfirst(c -> c.source == "SolarPosition", mt.constraints)
    @test sp_c !== nothing
    @test mt.constraints[sp_c].is_conflict == true
    @test length(mt.constraints[sp_c].ranges) == 1
    @test mt.constraints[sp_c].ranges[1] == ("11.0.0", "11.14.0")

    # Build bars — should show both SymbolicUtils segments
    lines = _build_ver_bars(pkgs, 50)
    combined = join([join(s.content for s in line) for line in lines], "\n")
    @test occursin("Conflict: ModelingToolkit", combined)
    @test occursin("SymbolicUtils", combined)
    @test occursin("SolarPosition", combined)
    # Multi-range should show both ranges in the label
    @test occursin("0.0.1", combined)
    @test occursin("3.1.1", combined)
    @test occursin("9.33.0", combined)
    @test occursin("9.7.0", combined)
end

@testitem "triage no-conflict fallback" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: _parse_resolver_log, _build_ver_bars

    # A resolver log without cross-package conflicts (just version constraints)
    resolver_log = """
    SomePkg [abcdef12] log:
    ├─possible versions are: 1.0.0 - 3.0.0 or uninstalled
    └─restricted to versions 2.0.0 - 3.0.0 by an explicit requirement, leaving only versions: 2.0.0 - 3.0.0
    """

    pkgs = _parse_resolver_log(resolver_log)
    @test length(pkgs) == 1

    lines = _build_ver_bars(pkgs, 40)
    combined = join([join(s.content for s in line) for line in lines], "\n")

    # No conflict section — just a normal package section
    @test !occursin("Conflict", combined)
    @test occursin("SomePkg", combined)
    @test occursin("Available", combined)
    @test occursin("explicit", combined)
end

@testitem "triage leaving-only-versions parsing" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: _parse_resolver_log, _build_ver_bars, _parse_ver_ranges

    # Simulate JuMP-like resolver output where Pkg emits:
    #   "to versions: X or uninstalled, leaving only versions: uninstalled"
    # These lines should be detected as CONFLICTS (no remaining versions).
    resolver_log = """
    Unsatisfiable requirements detected for package OrdinaryDiffEqDifferentiation [4302a76b]:
    OrdinaryDiffEqDifferentiation [4302a76b] log:
    ├─possible versions are: 1.0.0 - 2.2.1 or uninstalled
    ├─restricted by compatibility requirements with SciMLOperators [c0aeaf25] to versions: 1.2.0 - 2.2.1 or uninstalled
    ├─restricted by compatibility requirements with DifferentiationInterface [a0c0ee7d] to versions: 1.0.0 - 1.4.0 or uninstalled, leaving only versions: 1.0.0 - 1.4.0 or uninstalled
    ├─restricted by compatibility requirements with SparseMatrixColorings [0a514795] to versions: 1.0.0 - 1.4.0 or uninstalled, leaving only versions: uninstalled
    └─restricted by compatibility requirements with SparseDiffTools [47a9eef4] to versions: 1.6.0 - 2.2.1 or uninstalled, leaving only versions: 1.10.0 - 2.2.1
    Reexport [189a3867] log:
    ├─possible versions are: 0.2.0 - 1.2.2 or uninstalled
    └─restricted by compatibility requirements with SolarPosition [5b9d1343] to versions: 1.0.0 - 1.2.2 or uninstalled
    """

    pkgs = _parse_resolver_log(resolver_log)
    @test length(pkgs) == 2

    # OrdinaryDiffEqDifferentiation is the conflict target
    odiff = pkgs[findfirst(p -> p.name == "OrdinaryDiffEqDifferentiation", pkgs)]
    @test odiff.possible_min == "1.0.0"
    @test odiff.possible_max == "2.2.1"

    # SciMLOperators: non-conflict, clean range without "leaving"
    sci_c = findfirst(c -> c.source == "SciMLOperators", odiff.constraints)
    @test sci_c !== nothing
    @test odiff.constraints[sci_c].is_conflict == false
    @test odiff.constraints[sci_c].ranges == [("1.2.0", "2.2.1")]

    # DifferentiationInterface: non-conflict, "leaving only versions: 1.0.0 - 1.4.0"
    di_c = findfirst(c -> c.source == "DifferentiationInterface", odiff.constraints)
    @test di_c !== nothing
    @test odiff.constraints[di_c].is_conflict == false
    @test odiff.constraints[di_c].ranges == [("1.0.0", "1.4.0")]

    # SparseMatrixColorings: CONFLICT — "leaving only versions: uninstalled"
    smc_c = findfirst(c -> c.source == "SparseMatrixColorings", odiff.constraints)
    @test smc_c !== nothing
    @test odiff.constraints[smc_c].is_conflict == true
    @test odiff.constraints[smc_c].ranges == [("1.0.0", "1.4.0")]

    # SparseDiffTools: non-conflict, "leaving only versions: 1.10.0 - 2.2.1"
    sdt_c = findfirst(c -> c.source == "SparseDiffTools", odiff.constraints)
    @test sdt_c !== nothing
    @test odiff.constraints[sdt_c].is_conflict == false
    @test odiff.constraints[sdt_c].ranges == [("1.6.0", "2.2.1")]

    # Reexport: non-conflict, simple constraint
    reexport = pkgs[findfirst(p -> p.name == "Reexport", pkgs)]
    @test !any(c -> c.is_conflict, reexport.constraints)

    # Build bars — OrdinaryDiffEqDifferentiation should have a conflict section
    lines = _build_ver_bars(pkgs, 50)
    combined = join([join(s.content for s in line) for line in lines], "\n")
    @test occursin("Conflict: OrdinaryDiffEqDifferentiation", combined)
    @test occursin("SparseMatrixColorings", combined)
    @test occursin("DifferentiationInterface", combined)
    @test occursin("SciMLOperators", combined)
    @test occursin("Intersection", combined)
    # Range labels should be clean version numbers — no "leaving" text
    @test !occursin("leaving", combined)

    # _parse_ver_ranges safety net: handles "leaving only versions" even if
    # passed directly (e.g., from a future unmatched regex pattern)
    r = _parse_ver_ranges(
        "1.0.0 - 1.4.0 or uninstalled, leaving only versions: uninstalled",
    )
    @test r == [("1.0.0", "1.4.0")]
    r2 = _parse_ver_ranges(
        "1.6.0 - 2.2.1 or uninstalled, leaving only versions: 1.10.0 - 2.2.1",
    )
    @test r2 == [("1.6.0", "2.2.1")]
end

@testitem "triage key handling" tags = [:event] begin
    using Tachikoma
    using PkgTUI:
        PkgTUIApp, TriageState, ProjectInfo, build_triage_content!, handle_triage_keys!

    m = PkgTUIApp()
    m.triage.show = true
    m.triage.package_name = "TestPkg"
    m.triage.error_message = "Error in add: some error"
    build_triage_content!(m.triage, m.project_info)

    # Scroll down
    initial_offset = m.triage.scroll_pane.offset
    handle_triage_keys!(m, KeyEvent(:down))
    @test m.triage.scroll_pane.offset == initial_offset + 1

    # Scroll up
    handle_triage_keys!(m, KeyEvent(:up))
    @test m.triage.scroll_pane.offset == initial_offset

    # Page down
    handle_triage_keys!(m, KeyEvent(:pagedown))
    @test m.triage.scroll_pane.offset == initial_offset + 10

    # Escape closes triage
    handle_triage_keys!(m, KeyEvent(:escape))
    @test m.triage.show == false
end

@testitem "triage overlay renders" tags = [:view] begin
    using Tachikoma
    using PkgTUI:
        PkgTUIApp, TriageState, ProjectInfo, build_triage_content!, render_triage_overlay

    m = PkgTUIApp()
    m.triage.show = true
    m.triage.package_name = "FailPkg"
    m.triage.error_message = "Error in add: Unsatisfiable requirements"
    build_triage_content!(m.triage, m.project_info)

    area = Rect(1, 1, 100, 40)
    buf = Tachikoma.Buffer(area)

    # Should not throw
    render_triage_overlay(m, area, buf)
    @test true
end

@testitem "registry t key opens triage for failed package" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results = [
        RegistryPackage(name = "FailPkg", latest_version = "1.0.0"),
        RegistryPackage(name = "GoodPkg", latest_version = "2.0.0"),
    ]
    m.registry.selected = 1

    # Mark FailPkg as failed
    push!(m.registry.failed_names, "FailPkg")
    m.triage.package_name = "FailPkg"
    m.triage.error_message = "Error in add: something failed"

    # Press 't' — should open triage for FailPkg
    consumed = handle_registry_keys!(m, KeyEvent('t'))
    @test consumed == true
    @test m.triage.show == true
    @test m.triage.package_name == "FailPkg"
end

@testitem "registry t key ignored for non-failed package" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results = [RegistryPackage(name = "GoodPkg", latest_version = "2.0.0")]
    m.registry.selected = 1

    # Press 't' on a non-failed package — should not open triage
    consumed = handle_registry_keys!(m, KeyEvent('t'))
    @test m.triage.show == false
end

@testitem "VersionPickerState defaults" tags = [:unit, :fast] begin
    using PkgTUI: VersionPickerState

    vp = VersionPickerState()
    @test vp.show == false
    @test vp.package_name == ""
    @test isempty(vp.versions)
    @test vp.selected == 1
    @test vp.scroll_offset == 0
end

@testitem "version picker key v opens picker" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results = [RegistryPackage(name = "JSON", latest_version = "1.0.0")]
    m.registry.selected = 1

    # Press 'v' — should open version picker
    consumed = handle_registry_keys!(m, KeyEvent('v'))
    @test consumed == true
    @test m.registry.version_picker.show == true
    @test m.registry.version_picker.package_name == "JSON"
end

@testitem "version picker navigation" tags = [:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, handle_version_picker_keys!

    m = PkgTUIApp()
    vp = m.registry.version_picker
    vp.show = true
    vp.package_name = "TestPkg"
    vp.versions = ["2.0.0", "1.5.0", "1.0.0"]
    vp.selected = 1

    # Down arrow
    handle_version_picker_keys!(m, KeyEvent(:down))
    @test vp.selected == 2

    # Down again
    handle_version_picker_keys!(m, KeyEvent(:down))
    @test vp.selected == 3

    # Down at bottom — stays at 3
    handle_version_picker_keys!(m, KeyEvent(:down))
    @test vp.selected == 3

    # Up
    handle_version_picker_keys!(m, KeyEvent(:up))
    @test vp.selected == 2

    # Escape closes
    handle_version_picker_keys!(m, KeyEvent(:escape))
    @test vp.show == false
end

@testitem "render version picker overlay" tags = [:view] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, render_version_picker

    m = PkgTUIApp()
    m.registry.version_picker.show = true
    m.registry.version_picker.package_name = "JSON"
    m.registry.version_picker.versions = ["1.0.0", "0.21.0", "0.20.0"]
    m.registry.version_picker.selected = 1

    area = Rect(1, 1, 80, 30)
    buf = Tachikoma.Buffer(area)
    render_version_picker(m, area, buf)
    @test true  # no crash
end

@testitem "version picker in RegistryState" tags = [:unit, :fast] begin
    using PkgTUI: RegistryState

    rs = RegistryState()
    @test rs.version_picker.show == false
    @test rs.version_picker.package_name == ""
end

# ──────────────────────────────────────────────────────────────────────────────
# Compat picker — range computation
# ──────────────────────────────────────────────────────────────────────────────

@testitem "CompatPickerState defaults" tags = [:unit, :fast] begin
    using PkgTUI: CompatPickerState

    cp = CompatPickerState()
    @test cp.show == false
    @test cp.package_name == ""
    @test cp.current_compat == ""
    @test isempty(cp.versions)
    @test isempty(cp.matching)
    @test cp.parse_error == false
    @test cp.loading == false
    @test cp.scroll_offset == 0
end

@testitem "compat range — caret operator (^)" tags = [:unit, :fast] begin
    using PkgTUI: _format_compat_ranges

    # From the Julia compat docs table
    @test _format_compat_ranges("^1.2.3") == "[1.2.3, 2.0.0)"
    @test _format_compat_ranges("^1.2") == "[1.2.0, 2.0.0)"
    @test _format_compat_ranges("^1") == "[1.0.0, 2.0.0)"
    @test _format_compat_ranges("^0.2.3") == "[0.2.3, 0.3.0)"
    @test _format_compat_ranges("^0.0.3") == "[0.0.3, 0.0.4)"
    @test _format_compat_ranges("^0.0") == "[0.0.0, 0.1.0)"
    @test _format_compat_ranges("^0") == "[0.0.0, 1.0.0)"

    # Bare version numbers use caret semantics
    @test _format_compat_ranges("1.2.3") == "[1.2.3, 2.0.0)"
    @test _format_compat_ranges("1.2") == "[1.2.0, 2.0.0)"
    @test _format_compat_ranges("1") == "[1.0.0, 2.0.0)"
    @test _format_compat_ranges("0.2.3") == "[0.2.3, 0.3.0)"
    @test _format_compat_ranges("0.0.3") == "[0.0.3, 0.0.4)"
    @test _format_compat_ranges("0.0") == "[0.0.0, 0.1.0)"
    @test _format_compat_ranges("0") == "[0.0.0, 1.0.0)"
end

@testitem "compat range — tilde operator (~)" tags = [:unit, :fast] begin
    using PkgTUI: _format_compat_ranges

    # ~X.Y.Z: only patch changes allowed
    @test _format_compat_ranges("~1.2.3") == "[1.2.3, 1.3.0)"
    @test _format_compat_ranges("~0.2.3") == "[0.2.3, 0.3.0)"
    @test _format_compat_ranges("~0.0.3") == "[0.0.3, 0.1.0)"

    # ~X.Y: minor and patch changes allowed
    @test _format_compat_ranges("~1.2") == "[1.2.0, 2.0.0)"
    @test _format_compat_ranges("~0.2") == "[0.2.0, 1.0.0)"

    # ~X: minor and patch changes allowed
    @test _format_compat_ranges("~1") == "[1.0.0, 2.0.0)"
    @test _format_compat_ranges("~0") == "[0.0.0, 1.0.0)"
end

@testitem "compat range — equality operator (=)" tags = [:unit, :fast] begin
    using PkgTUI: _format_compat_ranges

    @test _format_compat_ranges("=1.2.3") == "{1.2.3}"
    @test _format_compat_ranges("=0.10.1") == "{0.10.1}"
end

@testitem "compat range — inequality operators" tags = [:unit, :fast] begin
    using PkgTUI: _format_compat_ranges

    @test _format_compat_ranges(">= 1.2.3") == "[1.2.3, ∞)"
    @test _format_compat_ranges(">= 1.2") == "[1.2.0, ∞)"
    @test _format_compat_ranges(">= 0") == "[0.0.0, ∞)"
    @test _format_compat_ranges("≥ 1.2.3") == "[1.2.3, ∞)"

    @test _format_compat_ranges("> 1.0.0") == "(1.0.0, ∞)"

    @test _format_compat_ranges("< 2.0.0") == "[0.0.0, 2.0.0)"
    @test _format_compat_ranges("<= 2.0.0") == "[0.0.0, 2.0.0]"
    @test _format_compat_ranges("≤ 2.0.0") == "[0.0.0, 2.0.0]"
end

@testitem "compat range — comma-separated union" tags = [:unit, :fast] begin
    using PkgTUI: _format_compat_ranges

    # Contiguous ranges (shown as two intervals)
    @test _format_compat_ranges("1.2, 2") == "[1.2.0, 2.0.0) ∪ [2.0.0, 3.0.0)"

    # Non-contiguous ranges with leading-zero semantics
    @test _format_compat_ranges("0.2, 1") == "[0.2.0, 0.3.0) ∪ [1.0.0, 2.0.0)"

    # Exact version set
    @test _format_compat_ranges("=0.10.1, =0.10.3") == "{0.10.1} ∪ {0.10.3}"

    # Three-way union
    @test _format_compat_ranges("1, 2, 3") ==
          "[1.0.0, 2.0.0) ∪ [2.0.0, 3.0.0) ∪ [3.0.0, 4.0.0)"
end

@testitem "compat range — edge cases" tags = [:unit, :fast] begin
    using PkgTUI: _format_compat_ranges

    # Empty / whitespace
    @test _format_compat_ranges("") == ""
    @test _format_compat_ranges("   ") == ""

    # Invalid specs return ""
    @test _format_compat_ranges("not_a_version") == ""
    @test _format_compat_ranges("1.2.3.4.5") == ""
end

@testitem "compat range — _filter_by_compat" tags = [:unit, :fast] begin
    using PkgTUI: _filter_by_compat

    versions = ["2.1.0", "2.0.0", "1.9.0", "1.0.0", "0.9.0", "0.2.0"]

    # Empty spec returns all versions, no error
    matching, err = _filter_by_compat(versions, "")
    @test matching == versions
    @test err == false

    # Caret spec
    matching, err = _filter_by_compat(versions, "^1")
    @test "1.9.0" in matching
    @test "1.0.0" in matching
    @test !("2.0.0" in matching)
    @test !("0.9.0" in matching)
    @test err == false

    # Leading-zero spec
    matching, err = _filter_by_compat(versions, "^0.2")
    @test "0.2.0" in matching
    @test !("0.9.0" in matching)
    @test err == false

    # Union spec
    matching, err = _filter_by_compat(versions, "0.2, 1")
    @test "0.2.0" in matching
    @test "1.0.0" in matching
    @test "1.9.0" in matching
    @test !("0.9.0" in matching)
    @test !("2.0.0" in matching)
    @test err == false

    # Invalid spec → empty result, parse_error = true
    matching, err = _filter_by_compat(versions, "not_valid")
    @test isempty(matching)
    @test err == true
end

@testitem "compat range — _update_compat_matching!" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: CompatPickerState, _update_compat_matching!

    cp = CompatPickerState()
    cp.versions = ["2.0.0", "1.5.0", "1.0.0", "0.9.0"]
    cp.input = TextInput(; label = " Compat: ", text = "^1", focused = true)

    _update_compat_matching!(cp)
    @test "1.5.0" in cp.matching
    @test "1.0.0" in cp.matching
    @test !("2.0.0" in cp.matching)
    @test !("0.9.0" in cp.matching)
    @test cp.parse_error == false
    @test cp.scroll_offset == 0

    # Invalid spec sets parse_error
    cp.input = TextInput(; label = " Compat: ", text = "???", focused = true)
    _update_compat_matching!(cp)
    @test cp.parse_error == true
    @test isempty(cp.matching)
end

@testitem "compat range — redundancy detection" tags = [:unit, :fast] begin
    using PkgTUI: _redundant_ranges

    # "1" covers [1.0.0, 2.0.0); "1.5" covers [1.5.0, 2.0.0) ⊆ that → "1.5" is redundant
    @test _redundant_ranges("1, 1.5") == ["1.5"]

    # Symmetric: "1.5, 1" — same redundancy
    @test _redundant_ranges("1.5, 1") == ["1.5"]

    # "^0.2" covers [0.2.0, 0.3.0); "^0.2.3" covers [0.2.3, 0.3.0) ⊆ that → redundant
    @test _redundant_ranges("^0.2, ^0.2.3") == ["^0.2.3"]

    # "^1" covers [1.0.0, 2.0.0); "~1.2" covers [1.2.0, 1.3.0) ⊆ that → "~1.2" is redundant
    @test _redundant_ranges("^1, ~1.2") == ["~1.2"]

    # ">= 1" covers [1.0.0, ∞); "^1.5" covers [1.5.0, 2.0.0) ⊆ that → "^1.5" is redundant
    @test _redundant_ranges(">= 1, ^1.5") == ["^1.5"]

    # ">= 1" covers [1.0.0, ∞); "2" covers [2.0.0, 3.0.0) ⊆ that → redundant
    @test _redundant_ranges(">= 1, 2") == ["2"]

    # Non-redundant: "1" covers [1.0.0, 2.0.0) and "2" covers [2.0.0, 3.0.0) — disjoint
    @test _redundant_ranges("1, 2") == String[]

    # Non-redundant: "0.2" covers [0.2.0, 0.3.0) and "1" covers [1.0.0, 2.0.0) — disjoint
    @test _redundant_ranges("0.2, 1") == String[]

    # Single token — no redundancy possible
    @test _redundant_ranges("^1") == String[]
    @test _redundant_ranges("1.2.3") == String[]

    # Empty / whitespace
    @test _redundant_ranges("") == String[]
    @test _redundant_ranges("   ") == String[]

    # Multiple redundant tokens: "^1" covers both "~1.2" and "1.5"
    result = _redundant_ranges("^1, ~1.2, 1.5")
    @test "~1.2" in result
    @test "1.5" in result
    @test !("^1" in result)

    # Equality: "=1.5.0" is a point interval [1.5.0, 1.5.1); "^1" covers it → redundant
    @test _redundant_ranges("^1, =1.5.0") == ["=1.5.0"]
end
