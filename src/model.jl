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
    version::Union{String,Nothing} = nothing
    is_direct_dep::Bool = false
    is_pinned::Bool = false
    is_tracking_path::Bool = false
    is_tracking_repo::Bool = false
    is_tracking_registry::Bool = false
    source::Union{String,Nothing} = nothing
    dependencies::Vector{UUID} = UUID[]
end

"""Information about an available update."""
@kwdef mutable struct UpdateInfo
    name::String
    current_version::String
    latest_compatible::Union{String,Nothing} = nothing
    latest_available::Union{String,Nothing} = nothing
    blocker::Union{String,Nothing} = nothing
    can_update::Bool = true   # ⌃ = true, ⌅ = false
end

"""A single package change in a dry-run diff."""
@kwdef struct DryRunEntry
    name::String
    kind::Symbol   # :upgraded, :downgraded, :added, :removed, :unchanged
    old_version::Union{String,Nothing} = nothing
    new_version::Union{String,Nothing} = nothing
end

"""Result of a dry-run manifest diff."""
@kwdef struct DryRunDiff
    entries::Vector{DryRunEntry} = DryRunEntry[]
    error::Union{String,Nothing} = nothing
end

"""A package found in the registry search."""
@kwdef mutable struct RegistryPackage
    name::String
    uuid::Union{UUID,Nothing} = nothing
    latest_version::Union{String,Nothing} = nothing
    repo::Union{String,Nothing} = nothing
    description::Union{String,Nothing} = nothing
end

"""Conflict holding a package back."""
@kwdef mutable struct ConflictInfo
    package::String
    held_at::String
    latest::String
    blocked_by::String
    compat_constraint::Union{String,Nothing} = nothing
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
    name::Union{String,Nothing} = nothing
    uuid::Union{UUID,Nothing} = nothing
    version::Union{String,Nothing} = nothing
    is_package::Bool = false
    path::Union{String,Nothing} = nothing
    dep_count::Int = 0
    is_workspace::Bool = false
    workspace_projects::Vector{String} = String[]
end

# ── Graph layout for dependency visualization (removed force-directed) ────────

# ── Tab-specific state ────────────────────────────────────────────────────────

"""State for the Installed Packages tab."""
@kwdef mutable struct InstalledState
    packages::Vector{PackageRow} = PackageRow[]
    filtered::Vector{PackageRow} = PackageRow[]
    filter_input::TextInput = TextInput(; label = "  Filter: ", focused = false)
    selected::Int = 1
    scroll_offset::Int = 0
    show_indirect::Bool = true
    adding::Bool = false
    add_input::TextInput = TextInput(; label = "  Package name: ", focused = false)
    loading::Bool = false
end

"""State for the Updates tab."""
@kwdef mutable struct UpdatesState
    updates::Vector{UpdateInfo} = UpdateInfo[]
    selected::Int = 1
    scroll_offset::Int = 0
    loading::Bool = false
    dry_run_output::Union{DryRunDiff,Nothing} = nothing
    show_dry_run::Bool = false
    dry_run_sections::Dict{Symbol,Bool} = Dict{Symbol,Bool}()  # section kind → expanded?
    dry_run_selected::Int = 1  # selected row in virtual line list (1-based)
    dry_run_scroll::Int = 0    # scroll offset for dry-run panel
    conflicts_focused::Bool = false  # true = keyboard focus on conflicts panel
    updating_names::Set{String} = Set{String}()   # packages currently being updated
    updated_names::Set{String} = Set{String}()     # packages successfully updated this session
    update_all_running::Bool = false               # true while "Update all" is in progress
end

"""State for the version picker overlay in the Registry tab."""
@kwdef mutable struct VersionPickerState
    show::Bool = false
    package_name::String = ""
    versions::Vector{String} = String[]
    selected::Int = 1
    scroll_offset::Int = 0
end

"""State for the Registry Explorer tab."""
@kwdef mutable struct RegistryState
    search_input::TextInput = TextInput(; label = "  Search: ", focused = false)
    results::Vector{RegistryPackage} = RegistryPackage[]
    selected::Int = 1
    scroll_offset::Int = 0
    loading::Bool = false
    registry_index::Vector{RegistryPackage} = RegistryPackage[]
    index_loaded::Bool = false
    search_timer_active::Bool = false
    detail_panel_focused::Bool = false
    installing_name::Union{String,Nothing} = nothing  # name of package currently being installed
    removing_name::Union{String,Nothing} = nothing      # name of package currently being removed
    installed_names::Set{String} = Set{String}()        # packages installed this session
    failed_names::Set{String} = Set{String}()            # packages that failed to install
    version_picker::VersionPickerState = VersionPickerState()
end

"""State for the Dependencies tab."""
@kwdef mutable struct DependenciesState
    tree_root::Union{TreeNode,Nothing} = nothing
    tree_view::Union{TreeView,Nothing} = nothing
    show_graph::Bool = false
    graph_selected::Int = 1
    graph_scroll::Int = 0
    why_output::Union{String,Nothing} = nothing
    loading::Bool = false
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
    selected::Int = 1         # selected row in table
    scroll_offset::Int = 0    # scroll offset for table
end

"""State for the install failure triage overlay."""
@kwdef mutable struct TriageState
    show::Bool = false
    package_name::String = ""
    error_message::String = ""          # full verbose Pkg error
    pkg_log::String = ""                # Pkg IO output during install
    scroll_pane::ScrollPane = ScrollPane(String[]; following = false)
    pkg_output_expanded::Bool = false   # Pkg output collapsed by default
    h_offset::Int = 0                   # horizontal scroll offset
    _lines::Vector{Vector{Span}} = Vector{Span}[]  # stored lines for h-scroll render
    _overlay_width::Int = 0              # last overlay width (triggers rebuild on resize)
end

"""State for the full-screen Log tab."""
@kwdef mutable struct LogState
    scroll_offset::Int = 0
    following::Bool = true              # auto-scroll to bottom
    search_active::Bool = false
    search_query::String = ""
    search_input::TextInput = TextInput(; label = "  Search: ", focused = false)
end

# ── Toast notifications ───────────────────────────────────────────────────────

"""A non-blocking notification overlay displayed in the center of the screen."""
@kwdef mutable struct Toast
    message::String
    style::Symbol = :text          # :success, :warning, :error, :text, :accent
    icon::String = ""              # e.g. "✓", "⚠", "✗"
    hint::String = ""              # e.g. "[t] triage"
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
    tab_names::Vector{String} =
        ["Installed", "Updates", "Registry", "Dependencies", "Metrics", "Log"]
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
    log_state::LogState = LogState()

    # ── Modal / confirmation ──
    modal::Union{Modal,Nothing} = nothing
    modal_action::Union{Symbol,Nothing} = nothing
    modal_target::Union{String,Nothing} = nothing

    # ── Triage overlay ──
    triage::TriageState = TriageState()

    # ── Toast notifications ──
    toasts::Vector{Toast} = Toast[]

    # ── Logging ──
    log_pane::ScrollPane = ScrollPane(String[]; following = true)
    show_log::Bool = true
    status_message::String = ""
    status_style::Symbol = :text
end

Tachikoma.should_quit(m::PkgTUIApp) = m.quit
Tachikoma.task_queue(m::PkgTUIApp) = m.tq
