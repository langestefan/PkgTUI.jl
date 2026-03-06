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

@testitem "Model construction" tags=[:unit, :fast] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, ProjectInfo, InstalledState, PackageRow

    # Default construction
    m = PkgTUIApp()
    @test m.quit == false
    @test m.tick == 0
    @test m.active_tab == 1
    @test length(m.tab_names) == 5
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

@testitem "PackageRow construction" tags=[:unit, :fast] begin
    using UUIDs
    using PkgTUI: PackageRow

    uuid = UUID("12345678-1234-1234-1234-123456789abc")
    row = PackageRow(
        name="TestPkg",
        uuid=uuid,
        version="1.2.3",
        is_direct_dep=true,
    )
    @test row.name == "TestPkg"
    @test row.version == "1.2.3"
    @test row.is_direct_dep == true
    @test row.is_pinned == false
    @test isempty(row.dependencies)
end

# ──────────────────────────────────────────────────────────────────────────────
# Backend tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "fetch_project_info" tags=[:unit] setup=[TempEnv] begin
    using PkgTUI: fetch_project_info, ProjectInfo

    with_temp_env() do dir
        info = fetch_project_info()
        @test info isa ProjectInfo
        @test info.path !== nothing
    end
end

@testitem "fetch_installed in temp env" tags=[:unit] setup=[TempEnv] begin
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

@testitem "apply_filter! filters by name" tags=[:unit, :fast] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: InstalledState, PackageRow, apply_filter!

    st = InstalledState()
    st.packages = [
        PackageRow(name="Alpha", uuid=UUID("11111111-0000-0000-0000-000000000001")),
        PackageRow(name="Beta", uuid=UUID("11111111-0000-0000-0000-000000000002"), is_direct_dep=true),
        PackageRow(name="AlphaExtra", uuid=UUID("11111111-0000-0000-0000-000000000003")),
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

@testitem "fuzzy_match" tags=[:unit, :fast] begin
    using PkgTUI: fuzzy_match

    @test fuzzy_match("dataframes", "df") == true
    @test fuzzy_match("dataframes", "data") == true
    @test fuzzy_match("dataframes", "xyz") == false
    @test fuzzy_match("abc", "abc") == true
    @test fuzzy_match("abc", "abcd") == false
end

@testitem "search_registry with mock data" tags=[:unit, :fast] begin
    using PkgTUI: RegistryPackage, search_registry

    index = [
        RegistryPackage(name="DataFrames"),
        RegistryPackage(name="CSV"),
        RegistryPackage(name="Plots"),
        RegistryPackage(name="DataStructures"),
        RegistryPackage(name="HTTP"),
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

@testitem "extract_conflicts" tags=[:unit, :fast] begin
    using PkgTUI: UpdateInfo, ConflictInfo, extract_conflicts

    updates = [
        UpdateInfo(name="A", current_version="1.0", can_update=true),
        UpdateInfo(name="B", current_version="2.0", can_update=false,
                   latest_available="3.0", blocker="C"),
        UpdateInfo(name="D", current_version="1.5", can_update=false,
                   latest_available="2.0", blocker="[compat]"),
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

@testitem "format_bytes" tags=[:unit, :fast] begin
    using PkgTUI: format_bytes

    @test format_bytes(Int64(500)) == "500 B"
    @test format_bytes(Int64(1024)) == "1.0 KB"
    @test format_bytes(Int64(1048576)) == "1.0 MB"
    @test format_bytes(Int64(1073741824)) == "1.0 GB"
end

@testitem "format_time" tags=[:unit, :fast] begin
    using PkgTUI: format_time

    @test format_time(0.0) == "—"
    @test format_time(0.5) == "500 ms"
    @test format_time(1.5) == "1500 ms"
    @test format_time(0.005) == "5.0 ms"
    @test format_time(0.0023) == "2.3 ms"
    @test format_time(0.00012) == "0.12 ms"
end

# ──────────────────────────────────────────────────────────────────────────────
# Dependency tree tests
# ──────────────────────────────────────────────────────────────────────────────

@testitem "build_dependency_tree" tags=[:unit, :fast] begin
    using UUIDs
    using PkgTUI: PackageRow, build_dependency_tree

    uuid_a = UUID("aaaaaaaa-0000-0000-0000-000000000001")
    uuid_b = UUID("bbbbbbbb-0000-0000-0000-000000000002")
    uuid_c = UUID("cccccccc-0000-0000-0000-000000000003")

    packages = [
        PackageRow(name="A", uuid=uuid_a, version="1.0", is_direct_dep=true,
                   dependencies=[uuid_b]),
        PackageRow(name="B", uuid=uuid_b, version="2.0", is_direct_dep=false,
                   dependencies=[uuid_c]),
        PackageRow(name="C", uuid=uuid_c, version="3.0", is_direct_dep=false),
    ]

    root = build_dependency_tree(packages)
    @test root.label == "Dependencies"
    @test length(root.children) == 1  # Only A is direct
    @test root.children[1].label == "A v1.0"
    @test length(root.children[1].children) == 1  # B
    @test root.children[1].children[1].label == "B v2.0"
end

# ──────────────────────────────────────────────────────────────────────────────
# View rendering tests (TestBackend)
# ──────────────────────────────────────────────────────────────────────────────

@testitem "render installed tab" tags=[:view] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, apply_filter!, render_installed_tab

    m = PkgTUIApp()
    m.installed.packages = [
        PackageRow(name="Example", uuid=UUID("7876af07-990d-54b4-ab0e-23690620f79a"),
                   version="1.0.0", is_direct_dep=true),
        PackageRow(name="HTTP", uuid=UUID("cd3eb016-35fb-5094-929b-558a96fad6f3"),
                   version="1.10.0", is_direct_dep=true),
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

@testitem "render updates tab" tags=[:view] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, UpdateInfo, ConflictInfo, extract_conflicts, render_updates_tab

    m = PkgTUIApp()
    area = Rect(1, 1, 100, 30)

    # Empty updates
    buf = Tachikoma.Buffer(area)
    render_updates_tab(m, area, buf)
    @test true

    # With updates
    m.updates_state.updates = [
        UpdateInfo(name="Foo", current_version="1.0.0", latest_compatible="2.0.0", can_update=true),
        UpdateInfo(name="Bar", current_version="0.5.0", latest_available="1.0.0", can_update=false, blocker="Baz"),
    ]
    m.conflicts.conflicts = extract_conflicts(m.updates_state.updates)
    buf2 = Tachikoma.Buffer(area)
    render_updates_tab(m, area, buf2)
    @test true

    # Dry-run view
    m.updates_state.show_dry_run = true
    m.updates_state.dry_run_output = "Update preview output"
    buf3 = Tachikoma.Buffer(area)
    render_updates_tab(m, area, buf3)
    @test true
end

@testitem "render registry tab" tags=[:view] begin
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
        RegistryPackage(name="TestPkg", latest_version="1.0.0"),
        RegistryPackage(name="AnotherPkg"),
    ]
    m.registry.selected = 1
    buf2 = Tachikoma.Buffer(area)
    render_registry_tab(m, area, buf2)
    @test true
end

@testitem "render dependencies tab" tags=[:view] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, GraphNode, GraphEdge,
                  build_dependency_tree, render_dependencies_tab

    m = PkgTUIApp()
    area = Rect(1, 1, 100, 30)

    # Empty state
    m.deps.loading = false
    buf = Tachikoma.Buffer(area)
    render_dependencies_tab(m, area, buf)
    @test true

    # With tree
    uuid_a = UUID("aaaaaaaa-0000-0000-0000-000000000001")
    uuid_b = UUID("bbbbbbbb-0000-0000-0000-000000000002")
    packages = [
        PackageRow(name="A", uuid=uuid_a, version="1.0", is_direct_dep=true,
                   dependencies=[uuid_b]),
        PackageRow(name="B", uuid=uuid_b, version="2.0", is_direct_dep=false),
    ]
    root = build_dependency_tree(packages)
    m.deps.tree_root = root
    m.deps.tree_view = TreeView(root; block=Block())
    buf2 = Tachikoma.Buffer(area)
    render_dependencies_tab(m, area, buf2)
    @test true

    # Graph mode
    m.deps.show_graph = true
    m.deps.graph_nodes = [
        GraphNode(name="A", uuid=uuid_a, x=30.0, y=15.0, is_direct=true),
        GraphNode(name="B", uuid=uuid_b, x=60.0, y=15.0, is_direct=false),
    ]
    m.deps.graph_edges = [GraphEdge(from=uuid_a, to=uuid_b)]
    buf3 = Tachikoma.Buffer(area)
    render_dependencies_tab(m, area, buf3)
    @test true
end

@testitem "render metrics tab" tags=[:view] begin
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
        PackageMetrics(name="Big", disk_size_bytes=Int64(1048576), compile_time_seconds=5.0, is_direct=true),
        PackageMetrics(name="Small", disk_size_bytes=Int64(1024), compile_time_seconds=0.5, is_direct=false),
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

@testitem "global key handling" tags=[:event] begin
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
end

@testitem "installed tab key handling" tags=[:event] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, apply_filter!

    m = PkgTUIApp()
    m.installed.packages = [
        PackageRow(name="A", uuid=UUID("aaaaaaaa-0000-0000-0000-000000000001"),
                   is_direct_dep=true, version="1.0"),
        PackageRow(name="B", uuid=UUID("bbbbbbbb-0000-0000-0000-000000000002"),
                   is_direct_dep=true, version="2.0"),
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

@testitem "updates tab conflicts focus" tags=[:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, ConflictInfo, UpdateInfo, handle_updates_keys!

    m = PkgTUIApp()
    m.active_tab = 2

    # Add conflicts
    m.conflicts.conflicts = [
        ConflictInfo(package="Foo", held_at="1.0", latest="2.0", blocked_by="Bar"),
        ConflictInfo(package="Baz", held_at="0.5", latest="1.0", blocked_by="Qux"),
    ]
    m.updates_state.updates = [
        UpdateInfo(name="Foo", current_version="1.0", can_update=false),
    ]

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

@testitem "draw_line! does not error" tags=[:view] begin
    using Tachikoma
    using PkgTUI: draw_line!

    area = Rect(1, 1, 40, 20)
    buf = Tachikoma.Buffer(area)

    # Horizontal-ish line
    draw_line!(buf, 5, 5, 20, 7, area, tstyle(:text_dim))
    @test true

    # Vertical-ish line
    draw_line!(buf, 10, 2, 12, 15, area, tstyle(:text_dim))
    @test true

    # Diagonal line
    draw_line!(buf, 1, 1, 10, 10, area, tstyle(:text_dim))
    @test true

    # Zero-length line
    draw_line!(buf, 5, 5, 5, 5, area, tstyle(:text_dim))
    @test true
end

@testitem "get_selected_dep_name tree mode" tags=[:view] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, GraphNode, get_selected_dep_name

    m = PkgTUIApp()

    # Tree mode with TreeView
    root = TreeNode("Dependencies", [
        TreeNode("MyPkg v1.2.3"),
        TreeNode("Other v0.5.0"),
    ])
    m.deps.tree_view = TreeView(root; block=Block())
    m.deps.tree_view.selected = 2  # "MyPkg v1.2.3"
    m.deps.show_graph = false

    name = get_selected_dep_name(m.deps, m)
    @test name == "MyPkg"

    # Graph mode
    uuid_a = UUID("aaaaaaaa-0000-0000-0000-000000000001")
    m.deps.show_graph = true
    m.deps.graph_nodes = [GraphNode(name="GraphPkg", uuid=uuid_a, is_direct=true)]
    m.deps.selected_node = uuid_a

    name = get_selected_dep_name(m.deps, m)
    @test name == "GraphPkg"
end

@testitem "help flag in @main" tags=[:basic] begin
    using PkgTUI

    # Capture --help output via a Pipe
    rd, wr = redirect_stdout()
    ret = PkgTUI.main(["--help"])
    @test ret == 0
    redirect_stdout()
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

@testitem "registry Escape preserves query" tags=[:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.registry_index = [
        RegistryPackage(name="DataFrames"),
        RegistryPackage(name="CSV"),
    ]

    # Focus the search input and type a query
    m.registry.search_input = TextInput(; label="  Search: ", text="Data", focused=true)
    @test m.registry.search_input.focused == true

    # Press Escape — should unfocus but keep text
    handle_registry_keys!(m, KeyEvent(:escape))
    @test m.registry.search_input.focused == false
    @test text(m.registry.search_input) == "Data"
end

@testitem "registry down-arrow moves to results" tags=[:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results = [
        RegistryPackage(name="DataFrames"),
        RegistryPackage(name="CSV"),
    ]
    m.registry.selected = 1

    # Focus search and type
    m.registry.search_input = TextInput(; label="  Search: ", text="Data", focused=true)

    # Press down-arrow — should unfocus search and put cursor on results
    handle_registry_keys!(m, KeyEvent(:down))
    @test m.registry.search_input.focused == false
    @test text(m.registry.search_input) == "Data"
    @test m.registry.selected >= 1
end

@testitem "registry up-arrow from top refocuses search" tags=[:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results = [
        RegistryPackage(name="DataFrames"),
        RegistryPackage(name="CSV"),
    ]
    m.registry.selected = 1

    # Search is unfocused, selected is at 1 (top)
    m.registry.search_input = TextInput(; label="  Search: ", text="Data", focused=false)

    # Press up at position 1 — should focus search input
    handle_registry_keys!(m, KeyEvent(:up))
    @test m.registry.search_input.focused == true
    @test text(m.registry.search_input) == "Data"
end

@testitem "installed filter Escape preserves text" tags=[:event] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, apply_filter!, handle_installed_keys!

    m = PkgTUIApp()
    m.active_tab = 1
    m.installed.packages = [
        PackageRow(name="Alpha", uuid=UUID("aaaaaaaa-0000-0000-0000-000000000001"),
                   is_direct_dep=true, version="1.0"),
    ]
    apply_filter!(m.installed)

    # Focus filter and type
    m.installed.filter_input = TextInput(; label="  Filter: ", text="alp", focused=true)

    # Press Escape — should unfocus but keep text
    handle_installed_keys!(m, KeyEvent(:escape))
    @test m.installed.filter_input.focused == false
    @test text(m.installed.filter_input) == "alp"
end

@testitem "installed up-arrow from top focuses filter" tags=[:event] begin
    using Tachikoma
    using UUIDs
    using PkgTUI: PkgTUIApp, PackageRow, apply_filter!, handle_installed_keys!

    m = PkgTUIApp()
    m.active_tab = 1
    m.installed.packages = [
        PackageRow(name="A", uuid=UUID("aaaaaaaa-0000-0000-0000-000000000001"),
                   is_direct_dep=true, version="1.0"),
        PackageRow(name="B", uuid=UUID("bbbbbbbb-0000-0000-0000-000000000002"),
                   is_direct_dep=true, version="2.0"),
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

@testitem "TriageState construction" tags=[:unit, :fast] begin
    using PkgTUI: TriageState

    tr = TriageState()
    @test tr.show == false
    @test tr.package_name == ""
    @test tr.error_message == ""
    @test tr.pkg_log == ""
end

@testitem "analyze_error suggestions" tags=[:unit, :fast] begin
    using PkgTUI: analyze_error

    # Compat error
    suggestions = analyze_error("Error in add: Unsatisfiable requirements detected for JuMP", "JuMP")
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

@testitem "build_triage_content! populates scroll pane" tags=[:unit] begin
    using Tachikoma
    using PkgTUI: TriageState, ProjectInfo, build_triage_content!

    tr = TriageState()
    tr.package_name = "FailPkg"
    tr.error_message = "Error in add: Unsatisfiable requirements detected for package FailPkg"
    tr.pkg_log = "some log output"

    pi = ProjectInfo(
        name="TestProject",
        path="/tmp/test/Project.toml",
        dep_count=5,
    )

    build_triage_content!(tr, pi)

    # Scroll pane should have content
    lines = tr.scroll_pane.content
    @test length(lines) > 5
    # Should contain package name, error, diagnostics, suggestions
    combined = join(lines, "\n")
    @test occursin("FailPkg", combined)
    @test occursin("Unsatisfiable", combined)
    @test occursin("Julia version", combined)
    @test occursin("TestProject", combined)
    @test occursin("Suggestions", combined)
    @test occursin("Compatibility", combined)
end

@testitem "triage key handling" tags=[:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, TriageState, ProjectInfo, build_triage_content!,
                  handle_triage_keys!

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

@testitem "triage overlay renders" tags=[:view] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, TriageState, ProjectInfo, build_triage_content!,
                  render_triage_overlay

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

@testitem "registry t key opens triage for failed package" tags=[:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results = [
        RegistryPackage(name="FailPkg", latest_version="1.0.0"),
        RegistryPackage(name="GoodPkg", latest_version="2.0.0"),
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

@testitem "registry t key ignored for non-failed package" tags=[:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results = [
        RegistryPackage(name="GoodPkg", latest_version="2.0.0"),
    ]
    m.registry.selected = 1

    # Press 't' on a non-failed package — should not open triage
    consumed = handle_registry_keys!(m, KeyEvent('t'))
    @test m.triage.show == false
end

@testitem "VersionPickerState defaults" tags=[:unit, :fast] begin
    using PkgTUI: VersionPickerState

    vp = VersionPickerState()
    @test vp.show == false
    @test vp.package_name == ""
    @test isempty(vp.versions)
    @test vp.selected == 1
    @test vp.scroll_offset == 0
end

@testitem "version picker key v opens picker" tags=[:event] begin
    using Tachikoma
    using PkgTUI: PkgTUIApp, RegistryPackage, handle_registry_keys!

    m = PkgTUIApp()
    m.active_tab = 3
    m.registry.index_loaded = true
    m.registry.results = [
        RegistryPackage(name="JSON", latest_version="1.0.0"),
    ]
    m.registry.selected = 1

    # Press 'v' — should open version picker
    consumed = handle_registry_keys!(m, KeyEvent('v'))
    @test consumed == true
    @test m.registry.version_picker.show == true
    @test m.registry.version_picker.package_name == "JSON"
end

@testitem "version picker navigation" tags=[:event] begin
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

@testitem "render version picker overlay" tags=[:view] begin
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

@testitem "version picker in RegistryState" tags=[:unit, :fast] begin
    using PkgTUI: RegistryState

    rs = RegistryState()
    @test rs.version_picker.show == false
    @test rs.version_picker.package_name == ""
end
