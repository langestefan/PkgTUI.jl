"""
    Model definitions for the PkgTUI application.

Contains the main `PkgTUIApp` model struct and all supporting data types
used across views.
"""

using Tachikoma
using UUIDs

# ── Data types returned by the Pkg backend ────────────────────────────────────

"""Row in the installed packages table."""
@kwdef mutable struct PackageRow
    name::String
    uuid::UUID
    version::Union{String, Nothing} = nothing
    is_direct_dep::Bool = false
    is_pinned::Bool = false
    is_tracking_path::Bool = false
    is_tracking_repo::Bool = false
    is_tracking_registry::Bool = false
    source::Union{String, Nothing} = nothing
    dependencies::Vector{UUID} = UUID[]
end

"""Information about an available update."""
@kwdef mutable struct UpdateInfo
    name::String
    current_version::String
    latest_compatible::Union{String, Nothing} = nothing
    latest_available::Union{String, Nothing} = nothing
    blocker::Union{String, Nothing} = nothing
    can_update::Bool = true   # ⌃ = true, ⌅ = false
end

"""A package found in the registry search."""
@kwdef mutable struct RegistryPackage
    name::String
    uuid::Union{UUID, Nothing} = nothing
    latest_version::Union{String, Nothing} = nothing
    repo::Union{String, Nothing} = nothing
    description::Union{String, Nothing} = nothing
end

"""Conflict holding a package back."""
@kwdef mutable struct ConflictInfo
    package::String
    held_at::String
    latest::String
    blocked_by::String
    compat_constraint::Union{String, Nothing} = nothing
end

"""Metrics for a single dependency."""
@kwdef mutable struct PackageMetrics
    name::String
    disk_size_bytes::Int64 = 0
    compile_time_seconds::Float64 = 0.0
    is_direct::Bool = false
end

"""Information about the active project/environment."""
@kwdef mutable struct ProjectInfo
    name::Union{String, Nothing} = nothing
    uuid::Union{UUID, Nothing} = nothing
    version::Union{String, Nothing} = nothing
    is_package::Bool = false
    path::Union{String, Nothing} = nothing
    dep_count::Int = 0
    is_workspace::Bool = false
    workspace_projects::Vector{String} = String[]
end

# ── Graph layout for dependency visualization ─────────────────────────────────

@kwdef mutable struct GraphNode
    name::String
    uuid::UUID
    x::Float64 = 0.0
    y::Float64 = 0.0
    vx::Float64 = 0.0
    vy::Float64 = 0.0
    is_direct::Bool = false
end

@kwdef mutable struct GraphEdge
    from::UUID
    to::UUID
end

# ── Tab-specific state ────────────────────────────────────────────────────────

"""State for the Installed Packages tab."""
@kwdef mutable struct InstalledState
    packages::Vector{PackageRow} = PackageRow[]
    filtered::Vector{PackageRow} = PackageRow[]
    filter_input::TextInput = TextInput(; label="  Filter: ", focused=false)
    selected::Int = 1
    scroll_offset::Int = 0
    show_indirect::Bool = true
    adding::Bool = false
    add_input::TextInput = TextInput(; label="  Package name: ", focused=false)
    loading::Bool = false
end

"""State for the Updates tab."""
@kwdef mutable struct UpdatesState
    updates::Vector{UpdateInfo} = UpdateInfo[]
    selected::Int = 1
    scroll_offset::Int = 0
    loading::Bool = false
    dry_run_output::Union{String, Nothing} = nothing
    show_dry_run::Bool = false
    conflicts_focused::Bool = false  # true = keyboard focus on conflicts panel
end

"""State for the Registry Explorer tab."""
@kwdef mutable struct RegistryState
    search_input::TextInput = TextInput(; label="  Search: ", focused=false)
    results::Vector{RegistryPackage} = RegistryPackage[]
    selected::Int = 1
    scroll_offset::Int = 0
    loading::Bool = false
    registry_index::Vector{RegistryPackage} = RegistryPackage[]
    index_loaded::Bool = false
    search_timer_active::Bool = false
    detail_panel_focused::Bool = false
    installing_name::Union{String, Nothing} = nothing  # name of package currently being installed
    installed_names::Set{String} = Set{String}()        # packages installed this session
    failed_names::Set{String} = Set{String}()            # packages that failed to install
end

"""State for the Dependencies tab."""
@kwdef mutable struct DependenciesState
    tree_root::Union{TreeNode, Nothing} = nothing
    tree_view::Union{TreeView, Nothing} = nothing
    graph_nodes::Vector{GraphNode} = GraphNode[]
    graph_edges::Vector{GraphEdge} = GraphEdge[]
    show_graph::Bool = false
    selected_node::Union{UUID, Nothing} = nothing
    why_output::Union{String, Nothing} = nothing
    loading::Bool = false
    graph_iterations::Int = 0
end

"""State for the Conflicts sub-view."""
@kwdef mutable struct ConflictsState
    conflicts::Vector{ConflictInfo} = ConflictInfo[]
    selected::Int = 1
    loading::Bool = false
end

"""State for the Metrics tab."""
@kwdef mutable struct MetricsState
    metrics::Vector{PackageMetrics} = PackageMetrics[]
    view_mode::Symbol = :size  # :size or :compile
    loading::Bool = false
    profiling::Bool = false
    profile_progress::Float64 = 0.0
    sort_by::Symbol = :size   # :size, :compile, :name
    sort_desc::Bool = true
end

"""State for the install failure triage overlay."""
@kwdef mutable struct TriageState
    show::Bool = false
    package_name::String = ""
    error_message::String = ""          # full verbose Pkg error
    pkg_log::String = ""                # Pkg IO output during install
    scroll_pane::ScrollPane = ScrollPane(String[]; following=false)
end

# ── Main application model ────────────────────────────────────────────────────

"""The top-level PkgTUI application model."""
@kwdef mutable struct PkgTUIApp <: Model
    # ── Core ──
    quit::Bool = false
    tick::Int = 0
    tq::TaskQueue = TaskQueue()

    # ── Navigation ──
    active_tab::Int = 1
    tab_names::Vector{String} = ["Installed", "Updates", "Registry", "Dependencies", "Metrics"]
    show_help::Bool = false

    # ── Environment ──
    project_info::ProjectInfo = ProjectInfo()
    env_switching::Bool = false
    env_list::Vector{String} = String[]
    env_selected::Int = 1

    # ── Tab states ──
    installed::InstalledState = InstalledState()
    updates_state::UpdatesState = UpdatesState()
    registry::RegistryState = RegistryState()
    deps::DependenciesState = DependenciesState()
    conflicts::ConflictsState = ConflictsState()
    metrics::MetricsState = MetricsState()

    # ── Modal / confirmation ──
    modal::Union{Modal, Nothing} = nothing
    modal_action::Union{Symbol, Nothing} = nothing
    modal_target::Union{String, Nothing} = nothing

    # ── Triage overlay ──
    triage::TriageState = TriageState()

    # ── Logging ──
    log_pane::ScrollPane = ScrollPane(String[]; following=true)
    show_log::Bool = true
    status_message::String = ""
    status_style::Symbol = :text
end

Tachikoma.should_quit(m::PkgTUIApp) = m.quit
Tachikoma.task_queue(m::PkgTUIApp) = m.tq
