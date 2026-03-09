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
# Pkg backend
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
# Filter logic
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
# Registry search
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
# Conflict extraction
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
# Formatting utilities
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
