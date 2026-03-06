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
    @test format_time(0.5) == "500ms"
    @test format_time(1.5) == "1.5s"
    @test format_time(90.0) == "1m 30.0s"
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
