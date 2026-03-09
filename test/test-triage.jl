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

    # Lines are stored in _lines field
    lines = tr._lines
    @test length(lines) > 5
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

    # Real BilevelJuMP conflict example
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

    jump_pkg = findfirst(p -> p.name == "JuMP", pkgs)
    @test jump_pkg !== nothing
    jump = pkgs[jump_pkg]
    conflict_c = findfirst(c -> c.is_conflict, jump.constraints)
    @test conflict_c !== nothing
    @test jump.constraints[conflict_c].source == "BilevelJuMP"
    @test jump.constraints[conflict_c].ranges == [("0.21.0", "0.21.10")]

    lines = _build_ver_bars(pkgs, 40)
    combined = join([join(s.content for s in line) for line in lines], "\n")

    @test occursin("Conflict", combined)
    @test occursin("JuMP", combined)
    @test occursin("Available", combined)
    @test occursin("SolarPosition", combined)
    @test occursin("BilevelJuMP", combined)
    @test occursin("Intersection", combined)

    # Conflict constraint (BilevelJuMP) should appear BEFORE non-conflict (SolarPosition)
    bilevel_pos = findfirst("BilevelJuMP", combined)
    solar_pos = findfirst("SolarPosition", combined)
    @test bilevel_pos !== nothing
    @test solar_pos !== nothing
    @test first(bilevel_pos) < first(solar_pos)

    @test !occursin("explicit", combined)
    @test !occursin("fixed", combined)
    @test count("Available", combined) == 1
end

@testitem "triage nested tree parsing" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: _parse_resolver_log, _build_ver_bars

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

    names = [p.name for p in pkgs]
    @test "SolarPosition" in names
    @test "JuMP" in names
    @test "BilevelJuMP" in names

    jump_pkg = findfirst(p -> p.name == "JuMP", pkgs)
    jump = pkgs[jump_pkg]
    @test any(c -> c.is_conflict, jump.constraints)

    bilevel_c = findfirst(c -> c.source == "BilevelJuMP", jump.constraints)
    @test bilevel_c !== nothing
    @test first(jump.constraints[bilevel_c].ranges)[1] == "0.21.0"

    solar_c = findfirst(c -> c.source == "SolarPosition", jump.constraints)
    @test solar_c !== nothing
    @test jump.constraints[solar_c].is_conflict == true

    sp_pkg = findfirst(p -> p.name == "SolarPosition", pkgs)
    sp = pkgs[sp_pkg]
    @test any(c -> c.source == "fixed", sp.constraints)
    @test !any(c -> c.is_conflict, sp.constraints)

    bp_pkg = findfirst(p -> p.name == "BilevelJuMP", pkgs)
    bp = pkgs[bp_pkg]
    @test any(c -> c.source == "explicit", bp.constraints)
    @test !any(c -> c.is_conflict, bp.constraints)

    lines = _build_ver_bars(pkgs, 45)
    combined = join([join(s.content for s in line) for line in lines], "\n")
    @test occursin("Conflict: JuMP", combined)
    @test occursin("BilevelJuMP", combined)
    @test occursin("SolarPosition", combined)

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

    mt = pkgs[findfirst(p -> p.name == "ModelingToolkit", pkgs)]
    @test any(c -> c.is_conflict, mt.constraints)

    su_c = findfirst(c -> c.source == "SymbolicUtils", mt.constraints)
    @test su_c !== nothing
    @test mt.constraints[su_c].is_conflict == true
    @test length(mt.constraints[su_c].ranges) == 2
    @test mt.constraints[su_c].ranges[1] == ("0.0.1", "3.1.1")
    @test mt.constraints[su_c].ranges[2] == ("9.33.0", "9.7.0")

    sp_c = findfirst(c -> c.source == "SolarPosition", mt.constraints)
    @test sp_c !== nothing
    @test mt.constraints[sp_c].is_conflict == true
    @test length(mt.constraints[sp_c].ranges) == 1
    @test mt.constraints[sp_c].ranges[1] == ("11.0.0", "11.14.0")

    lines = _build_ver_bars(pkgs, 50)
    combined = join([join(s.content for s in line) for line in lines], "\n")
    @test occursin("Conflict: ModelingToolkit", combined)
    @test occursin("SymbolicUtils", combined)
    @test occursin("SolarPosition", combined)
    @test occursin("0.0.1", combined)
    @test occursin("3.1.1", combined)
    @test occursin("9.33.0", combined)
    @test occursin("9.7.0", combined)
end

@testitem "triage no-conflict fallback" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: _parse_resolver_log, _build_ver_bars

    resolver_log = """
    SomePkg [abcdef12] log:
    ├─possible versions are: 1.0.0 - 3.0.0 or uninstalled
    └─restricted to versions 2.0.0 - 3.0.0 by an explicit requirement, leaving only versions: 2.0.0 - 3.0.0
    """

    pkgs = _parse_resolver_log(resolver_log)
    @test length(pkgs) == 1

    lines = _build_ver_bars(pkgs, 40)
    combined = join([join(s.content for s in line) for line in lines], "\n")

    @test !occursin("Conflict", combined)
    @test occursin("SomePkg", combined)
    @test occursin("Available", combined)
    @test occursin("explicit", combined)
end

@testitem "triage leaving-only-versions parsing" tags = [:unit, :fast] begin
    using Tachikoma
    using PkgTUI: _parse_resolver_log, _build_ver_bars, _parse_ver_ranges

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

    odiff = pkgs[findfirst(p -> p.name == "OrdinaryDiffEqDifferentiation", pkgs)]
    @test odiff.possible_min == "1.0.0"
    @test odiff.possible_max == "2.2.1"

    sci_c = findfirst(c -> c.source == "SciMLOperators", odiff.constraints)
    @test sci_c !== nothing
    @test odiff.constraints[sci_c].is_conflict == false
    @test odiff.constraints[sci_c].ranges == [("1.2.0", "2.2.1")]

    di_c = findfirst(c -> c.source == "DifferentiationInterface", odiff.constraints)
    @test di_c !== nothing
    @test odiff.constraints[di_c].is_conflict == false
    @test odiff.constraints[di_c].ranges == [("1.0.0", "1.4.0")]

    smc_c = findfirst(c -> c.source == "SparseMatrixColorings", odiff.constraints)
    @test smc_c !== nothing
    @test odiff.constraints[smc_c].is_conflict == true
    @test odiff.constraints[smc_c].ranges == [("1.0.0", "1.4.0")]

    sdt_c = findfirst(c -> c.source == "SparseDiffTools", odiff.constraints)
    @test sdt_c !== nothing
    @test odiff.constraints[sdt_c].is_conflict == false
    @test odiff.constraints[sdt_c].ranges == [("1.6.0", "2.2.1")]

    reexport = pkgs[findfirst(p -> p.name == "Reexport", pkgs)]
    @test !any(c -> c.is_conflict, reexport.constraints)

    lines = _build_ver_bars(pkgs, 50)
    combined = join([join(s.content for s in line) for line in lines], "\n")
    @test occursin("Conflict: OrdinaryDiffEqDifferentiation", combined)
    @test occursin("SparseMatrixColorings", combined)
    @test occursin("DifferentiationInterface", combined)
    @test occursin("SciMLOperators", combined)
    @test occursin("Intersection", combined)
    @test !occursin("leaving", combined)

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
