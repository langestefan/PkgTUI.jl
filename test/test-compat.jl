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
