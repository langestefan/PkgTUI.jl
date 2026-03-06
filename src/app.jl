"""
    Application orchestration — view, update!, init!, cleanup! for PkgTUIApp.
"""

import Pkg

# ──────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ──────────────────────────────────────────────────────────────────────────────

"""
    init!(m::PkgTUIApp, terminal::Tachikoma.Terminal)

One-time initialization: load environment info, fetch packages, start
registry indexing.
"""
function Tachikoma.init!(m::PkgTUIApp, terminal::Tachikoma.Terminal)
    push_log!(m, "PkgTUI starting...")

    # Fetch project info
    spawn_task!(m.tq, :fetch_project) do
        fetch_project_info()
    end

    # Fetch installed packages
    m.installed.loading = true
    spawn_task!(m.tq, :fetch_installed) do
        io = IOBuffer()
        fetch_installed(io)
    end

    # Start registry index build in background
    spawn_task!(m.tq, :build_registry_index) do
        build_registry_index()
    end

    # Auto-refresh timer: check for updates every 5 minutes
    spawn_timer!(m.tq, :auto_refresh, 300.0; repeat=true)

    push_log!(m, "Loading environment data...")
end

function Tachikoma.cleanup!(m::PkgTUIApp)
    # Nothing to clean up currently
end

# ──────────────────────────────────────────────────────────────────────────────
# View
# ──────────────────────────────────────────────────────────────────────────────

"""
    view(m::PkgTUIApp, f::Frame)

Main render function called every frame (~60fps).
"""
function Tachikoma.view(m::PkgTUIApp, f::Frame)
    m.tick += 1

    # Clear status message after a while
    if !isempty(m.status_message) && m.tick % 300 == 0
        m.status_message = ""
    end

    # Render main layout
    render_layout(m, f)

    # Overlays (rendered on top)
    if m.modal !== nothing
        render(m.modal, f.area, f.buffer)
    end

    if m.show_help
        render_help_overlay(m, f.area, f.buffer)
    end

    if m.env_switching
        render_env_switcher(m, f.area, f.buffer)
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Key Event handling
# ──────────────────────────────────────────────────────────────────────────────

"""
    update!(m::PkgTUIApp, evt::KeyEvent)

Handle keyboard events. Modal/overlay gets priority, then tab-specific handlers.
"""
function Tachikoma.update!(m::PkgTUIApp, evt::KeyEvent)
    # ── Modal handling (highest priority) ──
    if m.modal !== nothing
        handle_modal_keys!(m, evt)
        return
    end

    # ── Help overlay ──
    if m.show_help
        if evt.key == :escape || (evt.key == :char && evt.char == '?')
            m.show_help = false
        end
        return
    end

    # ── Environment switcher ──
    if m.env_switching
        handle_env_switcher_keys!(m, evt)
        return
    end

    # ── Tab-specific handlers (higher priority for escape in input modes) ──
    consumed = if m.active_tab == 1
        handle_installed_keys!(m, evt)
    elseif m.active_tab == 2
        handle_updates_keys!(m, evt)
    elseif m.active_tab == 3
        handle_registry_keys!(m, evt)
    elseif m.active_tab == 4
        handle_dependencies_keys!(m, evt)
    elseif m.active_tab == 5
        handle_metrics_keys!(m, evt)
    else
        false
    end
    consumed && return

    # ── Global keys (only if tab handler didn't consume) ──
    if evt.key == :char
        c = evt.char
        if c == 'q'
            m.quit = true
            return
        elseif c == '?'
            m.show_help = true
            return
        elseif c == 'l'
            m.show_log = !m.show_log
            return
        elseif c in ('1', '2', '3', '4', '5')
            new_tab = Int(c - '0')
            m.active_tab = new_tab
            # Auto-refresh updates when switching to Updates tab
            if new_tab == 2 && isempty(m.updates_state.updates) && !m.updates_state.loading
                refresh_updates!(m)
            end
            return
        end
    elseif evt.key == :escape
        m.quit = true
        return
    elseif evt.key == :ctrl && evt.char == 'e'
        start_env_switcher!(m)
        return
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Task Event handling
# ──────────────────────────────────────────────────────────────────────────────

"""
    update!(m::PkgTUIApp, evt::TaskEvent)

Handle results from background tasks.
"""
function Tachikoma.update!(m::PkgTUIApp, evt::TaskEvent)
    if evt.value isa Exception
        handle_task_error!(m, evt.id, evt.value)
        return
    end

    if evt.id == :fetch_project
        m.project_info = evt.value::ProjectInfo
        push_log!(m, "Environment: $(something(m.project_info.name, "unnamed")) " *
                     "($(m.project_info.dep_count) deps)")

    elseif evt.id == :fetch_installed
        packages = evt.value::Vector{PackageRow}
        m.installed.packages = packages
        m.installed.loading = false
        apply_filter!(m.installed)
        push_log!(m, "Loaded $(length(packages)) packages.")
        set_status!(m, "$(length(packages)) packages loaded", :success)

        # Build dependency tree
        if !isempty(packages)
            tree_root = build_dependency_tree(packages)
            m.deps.tree_root = tree_root
            m.deps.tree_view = TreeView(tree_root; block=Block())
        end

    elseif evt.id == :build_registry_index
        m.registry.registry_index = evt.value::Vector{RegistryPackage}
        m.registry.index_loaded = true
        push_log!(m, "Registry index: $(length(m.registry.registry_index)) packages indexed.")
        # Show initial results (top packages)
        do_registry_search!(m)

    elseif evt.id == :add
        result = evt.value
        msg = result isa NamedTuple ? result.result : string(result)
        push_log!(m, msg)
        if result isa NamedTuple && !isempty(result.log)
            for line in split(result.log, '\n')
                !isempty(strip(line)) && push_log!(m, "  " * line)
            end
        end
        set_status!(m, msg, :success)
        refresh_all!(m)

    elseif evt.id == :remove
        result = evt.value
        msg = result isa NamedTuple ? result.result : string(result)
        push_log!(m, msg)
        set_status!(m, msg, :success)
        refresh_all!(m)

    elseif evt.id == :update_single || evt.id == :update_all
        result = evt.value
        msg = result isa NamedTuple ? result.result : string(result)
        push_log!(m, msg)
        set_status!(m, msg, :success)
        refresh_all!(m)

    elseif evt.id == :pin || evt.id == :free
        result = evt.value
        msg = result isa NamedTuple ? result.result : string(result)
        push_log!(m, msg)
        set_status!(m, msg, :success)
        refresh_all!(m)

    elseif evt.id == :fetch_outdated
        updates, raw = evt.value::Tuple{Vector{UpdateInfo}, String}
        m.updates_state.updates = updates
        m.updates_state.loading = false
        m.conflicts.conflicts = extract_conflicts(updates)
        push_log!(m, "Found $(length(updates)) packages with updates available.")
        set_status!(m, "$(length(updates)) updates available", :warning)

    elseif evt.id == :dry_run
        output = evt.value::String
        m.updates_state.dry_run_output = output
        m.updates_state.show_dry_run = true
        push_log!(m, "Dry-run complete.")

    elseif evt.id == :why
        output = evt.value::String
        m.deps.why_output = output
        push_log!(m, "Pkg.why() result:")
        for line in split(output, '\n')
            !isempty(strip(line)) && push_log!(m, "  " * line)
        end

    elseif evt.id == :measure_sizes
        metrics = evt.value::Vector{PackageMetrics}
        m.metrics.metrics = metrics
        m.metrics.profile_progress = 0.5
        push_log!(m, "Disk sizes measured. Starting compile profiling...")

        # Now run compile profiling
        spawn_task!(m.tq, :compile_profile) do
            io = IOBuffer()
            run_precompile_profiling(io)
        end

    elseif evt.id == :compile_profile
        timings = evt.value::Vector{Tuple{String, Float64}}
        # Merge compile times into existing metrics
        timing_map = Dict(name => secs for (name, secs) in timings)
        for m_item in m.metrics.metrics
            m_item.compile_time_seconds = get(timing_map, m_item.name, 0.0)
        end
        m.metrics.profiling = false
        m.metrics.profile_progress = 1.0
        push_log!(m, "Profiling complete. $(length(timings)) packages profiled.")
        set_status!(m, "Profiling complete", :success)

    elseif evt.id == :switch_env
        push_log!(m, "Environment switched.")
        set_status!(m, "Environment switched", :success)
        refresh_all!(m)

    elseif evt.id == :fetch_env_list
        m.env_list = evt.value::Vector{String}

    elseif evt.id == :auto_refresh
        # Periodic background refresh — only if not already loading
        if !m.installed.loading
            push_log!(m, "Auto-refresh: checking for changes...")
            spawn_task!(m.tq, :fetch_installed) do
                io = IOBuffer()
                fetch_installed(io)
            end
        end
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Modal handling
# ──────────────────────────────────────────────────────────────────────────────

function handle_modal_keys!(m::PkgTUIApp, evt::KeyEvent)
    if evt.key == :escape
        m.modal = nothing
        m.modal_action = nothing
        m.modal_target = nothing
        return
    end

    if evt.key == :left || evt.key == :right
        # Toggle between confirm/cancel
        if m.modal !== nothing
            m.modal = Modal(;
                title=m.modal.title,
                message=m.modal.message,
                confirm_label=m.modal.confirm_label,
                cancel_label=m.modal.cancel_label,
                selected=m.modal.selected == :confirm ? :cancel : :confirm,
            )
        end
        return
    end

    if evt.key == :enter
        if m.modal !== nothing && m.modal.selected == :confirm
            execute_modal_action!(m)
        end
        m.modal = nothing
        m.modal_action = nothing
        m.modal_target = nothing
        return
    end
end

function execute_modal_action!(m::PkgTUIApp)
    action = m.modal_action
    target = m.modal_target
    target === nothing && return

    if action == :remove
        push_log!(m, "Removing $target...")
        spawn_task!(m.tq, :remove) do
            io = IOBuffer()
            result = remove_package(target, io)
            (result=result, log=String(take!(io)))
        end
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Environment switcher
# ──────────────────────────────────────────────────────────────────────────────

function start_env_switcher!(m::PkgTUIApp)
    m.env_switching = true
    m.env_selected = 1
    spawn_task!(m.tq, :fetch_env_list) do
        fetch_environment_list()
    end
end

function handle_env_switcher_keys!(m::PkgTUIApp, evt::KeyEvent)
    if evt.key == :escape
        m.env_switching = false
        return
    elseif evt.key == :up
        m.env_selected = max(1, m.env_selected - 1)
        return
    elseif evt.key == :down
        m.env_selected = min(length(m.env_list), m.env_selected + 1)
        return
    elseif evt.key == :enter
        if m.env_selected >= 1 && m.env_selected <= length(m.env_list)
            env_path = m.env_list[m.env_selected]
            m.env_switching = false
            push_log!(m, "Switching to: $env_path")
            spawn_task!(m.tq, :switch_env) do
                Pkg.activate(dirname(env_path))
                "Switched to $(dirname(env_path))"
            end
        end
        return
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

"""Push a message to the log pane."""
function push_log!(m::PkgTUIApp, msg::String)
    push_line!(m.log_pane, msg)
end

"""Set the status bar message with a style."""
function set_status!(m::PkgTUIApp, msg::String, style::Symbol)
    m.status_message = msg
    m.status_style = style
end

"""Handle an error from a background task."""
function handle_task_error!(m::PkgTUIApp, id::Symbol, err::Exception)
    msg = "Error in $id: $(sprint(showerror, err))"
    push_log!(m, msg)
    set_status!(m, "Error: $(sprint(showerror, err))", :error)

    # Reset loading states
    if id == :fetch_installed
        m.installed.loading = false
    elseif id == :fetch_outdated
        m.updates_state.loading = false
    elseif id in (:measure_sizes, :compile_profile)
        m.metrics.profiling = false
    end
end

"""Refresh all data after a package operation."""
function refresh_all!(m::PkgTUIApp)
    # Refresh project info
    spawn_task!(m.tq, :fetch_project) do
        fetch_project_info()
    end

    # Refresh installed packages
    m.installed.loading = true
    spawn_task!(m.tq, :fetch_installed) do
        io = IOBuffer()
        fetch_installed(io)
    end

    # Refresh outdated info
    refresh_updates!(m)
end

# ──────────────────────────────────────────────────────────────────────────────
# Public entry point
# ──────────────────────────────────────────────────────────────────────────────

"""
    pkgtui(; project::Union{String, Nothing}=nothing, fps::Int=30)

Launch the PkgTUI terminal interface.

# Arguments
- `project`: Path to a Julia project to activate. Defaults to the current active environment.
- `fps`: Frames per second for the TUI render loop (default: 30).
"""
function pkgtui(; project::Union{String, Nothing}=nothing, fps::Int=30)
    if project !== nothing
        Pkg.activate(project)
    end
    app(PkgTUIApp(); fps=fps, default_bindings=true)
end
