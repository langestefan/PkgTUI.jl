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
