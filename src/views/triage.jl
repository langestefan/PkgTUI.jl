"""
    Install Triage overlay — debug why a package failed to install.
"""

"""
    render_triage_overlay(m::PkgTUIApp, area::Rect, buf::Buffer)

Render a full-screen overlay with error details, diagnostics, and suggestions
for a failed package install.
"""
function render_triage_overlay(m::PkgTUIApp, area::Rect, buf::Buffer)
    tr = m.triage

    # Size: nearly full-screen
    w = min(area.width - 4, 90)
    h = min(area.height - 2, 40)
    overlay_rect = center(area, w, h)

    # Clear the background behind the overlay so underlying content doesn't bleed through
    blank = " "^overlay_rect.width
    for y in overlay_rect.y:(overlay_rect.y + overlay_rect.height - 1)
        set_string!(buf, overlay_rect.x, y, blank, tstyle(:text))
    end

    inner = render(Block(
        title="Install Triage: $(tr.package_name)",
        border_style=tstyle(:accent),
        box=BOX_DOUBLE,
    ), overlay_rect, buf)

    # Layout: scroll pane content | bottom status bar
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), inner)
    content_area = rows[1]
    status_area = rows[2]

    # Render the scroll pane with triage content
    render(tr.scroll_pane, content_area, buf)

    # Bottom action bar
    render(StatusBar(
        left=[
            Span("  ↑↓ scroll ", tstyle(:text_dim)),
            Span("[r]etry ", tstyle(:accent)),
            Span("[Esc] close ", tstyle(:text_dim)),
        ],
        right=[],
    ), status_area, buf)
end

"""
    build_triage_content!(tr::TriageState, project_info::ProjectInfo)

Populate the triage scroll pane with error details, diagnostics, and suggestions.
"""
function build_triage_content!(tr::TriageState, project_info::ProjectInfo)
    lines = String[]

    # ── Header ──
    push!(lines, "  Package: $(tr.package_name)")
    push!(lines, "")

    # ── Error details ──
    push!(lines, "  Error Details")
    push!(lines, "  " * "─"^40)
    push!(lines, "")

    # Strip the "Error in add: " prefix for cleaner display
    error_text = tr.error_message
    if startswith(error_text, "Error in add: ")
        error_text = error_text[length("Error in add: ")+1:end]
    end

    # Word-wrap error lines for readability
    for raw_line in split(error_text, '\n')
        line = String(raw_line)
        if length(line) <= 80
            push!(lines, "  " * line)
        else
            # Simple word-wrap
            remaining = line
            while length(remaining) > 80
                idx = findlast(' ', remaining[1:80])
                if idx === nothing
                    idx = 80
                end
                push!(lines, "  " * remaining[1:idx])
                remaining = remaining[idx+1:end]
            end
            !isempty(remaining) && push!(lines, "  " * remaining)
        end
    end

    # ── Pkg log output (if any) ──
    if !isempty(strip(tr.pkg_log))
        push!(lines, "")
        push!(lines, "  Pkg Output")
        push!(lines, "  " * "─"^40)
        for raw_line in split(tr.pkg_log, '\n')
            line = String(raw_line)
            !isempty(strip(line)) && push!(lines, "  " * line)
        end
    end

    # ── Diagnostics ──
    push!(lines, "")
    push!(lines, "  Diagnostics")
    push!(lines, "  " * "─"^40)

    julia_ver = string(VERSION)
    env_path = something(project_info.path, "unknown")
    env_name = something(project_info.name, basename(dirname(env_path)))

    push!(lines, "  Julia version:  v$(julia_ver)")
    push!(lines, "  Environment:    $(env_name)")
    push!(lines, "  Env path:       $(env_path)")
    push!(lines, "  Direct deps:    $(project_info.dep_count)")

    # ── Suggestions ──
    push!(lines, "")
    push!(lines, "  Suggestions")
    push!(lines, "  " * "─"^40)

    suggestions = analyze_error(tr.error_message, tr.package_name)
    for s in suggestions
        push!(lines, "  • " * s)
    end

    push!(lines, "")

    # Build the scroll pane
    tr.scroll_pane = ScrollPane(lines; following=false)
end

"""
    analyze_error(error_msg::String, pkg_name::String) → Vector{String}

Analyze the error message and return actionable suggestions.
"""
function analyze_error(error_msg::String, pkg_name::String)::Vector{String}
    suggestions = String[]
    msg_lower = lowercase(error_msg)

    if occursin("unsatisfiable", msg_lower) || occursin("compat", msg_lower)
        push!(suggestions, "Compatibility constraints are blocking installation.")
        push!(suggestions, "Try: Pkg.update() to widen compat bounds, then retry.")
        push!(suggestions, "Check if $(pkg_name) supports your Julia version (v$(VERSION)).")
        push!(suggestions, "Look for compat constraints in your Project.toml.")
        push!(suggestions, "Consider: Pkg.add(name=\"$(pkg_name)\", version=\"older-version\").")
    end

    if occursin("not found", msg_lower) || occursin("does not exist", msg_lower)
        push!(suggestions, "Package '$(pkg_name)' was not found in the registry.")
        push!(suggestions, "Check the spelling of the package name.")
        push!(suggestions, "The package may not be registered in General registry.")
        push!(suggestions, "Try: Pkg.add(url=\"https://github.com/...\")")
    end

    if occursin("network", msg_lower) || occursin("dns", msg_lower) || occursin("timeout", msg_lower)
        push!(suggestions, "A network error occurred during installation.")
        push!(suggestions, "Check your internet connection.")
        push!(suggestions, "Try again — it might be a transient issue.")
    end

    if occursin("permission", msg_lower) || occursin("access denied", msg_lower)
        push!(suggestions, "A permission error occurred.")
        push!(suggestions, "Check file permissions in your Julia depot (~/.julia/).")
    end

    if occursin("git", msg_lower) && occursin("error", msg_lower)
        push!(suggestions, "A Git-related error occurred.")
        push!(suggestions, "Ensure Git is installed and accessible.")
        push!(suggestions, "Try: Pkg.Registry.update() to refresh registries.")
    end

    # Fallback suggestions
    if isempty(suggestions)
        push!(suggestions, "An unexpected error occurred during installation.")
        push!(suggestions, "Try: Pkg.update() and retry the install.")
        push!(suggestions, "Try: Pkg.resolve() to fix dependency conflicts.")
        push!(suggestions, "Check the package's GitHub issues page for known problems.")
    end

    push!(suggestions, "Press [r] to retry installing $(pkg_name).")

    return suggestions
end

"""
    handle_triage_keys!(m::PkgTUIApp, evt::KeyEvent)

Handle keyboard events in the triage overlay.
"""
function handle_triage_keys!(m::PkgTUIApp, evt::KeyEvent)
    tr = m.triage

    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        tr.show = false
        return
    end

    if evt.key == :up
        tr.scroll_pane.offset = max(0, tr.scroll_pane.offset - 1)
        tr.scroll_pane.following = false
        return
    end

    if evt.key == :down
        tr.scroll_pane.offset += 1
        tr.scroll_pane.following = false
        return
    end

    if evt.key == :pageup
        tr.scroll_pane.offset = max(0, tr.scroll_pane.offset - 10)
        tr.scroll_pane.following = false
        return
    end

    if evt.key == :pagedown
        tr.scroll_pane.offset += 10
        tr.scroll_pane.following = false
        return
    end

    if evt.key == :char && evt.char == 'r'
        # Retry installing the package
        pkg_name = tr.package_name
        tr.show = false
        # Clear failed state and retry
        delete!(m.registry.failed_names, pkg_name)
        m.registry.installing_name = pkg_name
        push_log!(m, "Retrying install of $(pkg_name)...")
        set_status!(m, "Retrying $(pkg_name)...", :warning)
        spawn_task!(m.tq, :add) do
            io = IOBuffer()
            result = add_package(pkg_name, io)
            (result=result, log=String(take!(io)), name=pkg_name)
        end
        return
    end
end
