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
# Registry / installed navigation
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
# Version picker
# ──────────────────────────────────────────────────────────────────────────────

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

@testitem "version picker in RegistryState" tags = [:unit, :fast] begin
    using PkgTUI: RegistryState

    rs = RegistryState()
    @test rs.version_picker.show == false
    @test rs.version_picker.package_name == ""
end
