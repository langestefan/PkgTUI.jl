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

    area = Rect(1, 1, 100, 30)
    buf = Tachikoma.Buffer(area)
    render_installed_tab(m, area, buf)
    @test true  # no-throw

    # Loading state
    m.installed.loading = true
    buf2 = Tachikoma.Buffer(area)
    render_installed_tab(m, area, buf2)
    @test true

    # Empty state
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

    # Empty state
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

    render_triage_overlay(m, area, buf)
    @test true
end
