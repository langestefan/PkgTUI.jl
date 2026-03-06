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
    for y = overlay_rect.y:(overlay_rect.y+overlay_rect.height-1)
        set_string!(buf, overlay_rect.x, y, blank, tstyle(:text))
    end

    inner = render(
        Block(
            title = "Install Triage: $(tr.package_name)",
            border_style = tstyle(:accent),
            box = BOX_DOUBLE,
        ),
        overlay_rect,
        buf,
    )

    # Layout: scroll pane content | bottom status bar
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), inner)
    content_area = rows[1]
    status_area = rows[2]

    # Render the scroll pane with triage content
    render(tr.scroll_pane, content_area, buf)

    # Bottom action bar
    render(
        StatusBar(
            left = [
                Span("  ↑↓ scroll ", tstyle(:text_dim)),
                Span(
                    "[o]utput ",
                    tr.pkg_output_expanded ? tstyle(:success) : tstyle(:accent),
                ),
                Span("[r]etry ", tstyle(:accent)),
                Span("[Esc] close ", tstyle(:text_dim)),
            ],
            right = [],
        ),
        status_area,
        buf,
    )
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

    # ── Condensed Summary (most likely cause) ──
    box_header = "  ╔══ Summary ══════════════════════════════════════╗"
    box_inner_w = length(box_header) - 5  # subtract "  ║  " prefix (content starts at col 6)
    push!(lines, box_header)
    summary = extract_error_summary(tr.error_message, tr.pkg_log, tr.package_name)
    for s in summary
        # Truncate long lines to fit inside the summary box
        display_s = length(s) > box_inner_w ? s[1:prevind(s, box_inner_w)] * "…" : s
        push!(lines, "  ║  " * display_s)
    end
    push!(lines, "  ╚═══════════════════════════════════════════════════╝")
    push!(lines, "")

    # ── Error details (collapsible) ──
    # Combine error message + pkg log into one collapsible section
    error_text = tr.error_message
    if startswith(error_text, "Error in add: ")
        error_text = error_text[length("Error in add: ")+1:end]
    end

    # Collect all detail lines (error message + pkg log)
    detail_lines = String[]
    for raw_line in split(error_text, '\n')
        line = String(raw_line)
        if length(line) <= 80
            push!(detail_lines, line)
        else
            remaining = line
            while length(remaining) > 80
                idx = findlast(' ', remaining[1:80])
                if idx === nothing
                    idx = 80
                end
                push!(detail_lines, remaining[1:idx])
                remaining = remaining[idx+1:end]
            end
            !isempty(remaining) && push!(detail_lines, remaining)
        end
    end
    if !isempty(strip(tr.pkg_log))
        push!(detail_lines, "")
        for raw_line in split(tr.pkg_log, '\n')
            line = String(raw_line)
            !isempty(strip(line)) && push!(detail_lines, line)
        end
    end

    push!(lines, "")
    if tr.pkg_output_expanded
        push!(lines, "  Error Details  [o] collapse ▴")
        push!(lines, "  " * "─"^40)
        push!(lines, "")
        for dl in detail_lines
            push!(lines, "  " * dl)
        end
    else
        push!(lines, "  Error Details  [o] expand ▾  ($(length(detail_lines)) lines hidden)")
        push!(lines, "  " * "─"^40)
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
    tr.scroll_pane = ScrollPane(lines; following = false)
end

"""
    extract_error_summary(error_msg, pkg_log, pkg_name) → Vector{String}

Parse the error and Pkg output to produce a short 2-4 line summary
identifying the most likely root cause.
"""
function extract_error_summary(
    error_msg::String,
    pkg_log::String,
    pkg_name::String,
)::Vector{String}
    combined = error_msg * "\n" * pkg_log
    lower = lowercase(combined)
    summary = String[]

    # ── Unsatisfiable / compat conflicts ──
    if occursin("unsatisfiable", lower) ||
       occursin("resolve", lower) && occursin("compat", lower)
        push!(summary, "Root cause: Dependency conflict")
        # Try to extract the conflicting constraint
        for line in split(combined, '\n')
            stripped = strip(String(line))
            if occursin("requires", lowercase(stripped)) ||
               (occursin("compat", lowercase(stripped)) && occursin("[", stripped))
                push!(summary, stripped)
                length(summary) >= 4 && break
            end
        end
        if length(summary) == 1
            push!(summary, "Julia v$(VERSION) compat bounds may be too strict.")
        end
        return summary
    end

    # ── Package not found ──
    if occursin("not found", lower) ||
       occursin("does not exist", lower) ||
       occursin("no registered package", lower)
        push!(summary, "Root cause: Package not found in registry")
        push!(summary, "'$(pkg_name)' may be misspelled or not registered.")
        return summary
    end

    # ── Network / download failures ──
    if occursin("network", lower) ||
       occursin("dns", lower) ||
       occursin("timeout", lower) ||
       occursin("could not resolve host", lower)
        push!(summary, "Root cause: Network error")
        push!(summary, "Could not download package or registry data.")
        return summary
    end

    # ── Permission errors ──
    if occursin("permission denied", lower) ||
       occursin("access denied", lower) ||
       occursin("eacces", lower)
        push!(summary, "Root cause: Permission denied")
        push!(summary, "Check write access to ~/.julia/ depot.")
        return summary
    end

    # ── Build / compile errors ──
    if occursin("build error", lower) ||
       occursin("precompile error", lower) ||
       occursin("failed to precompile", lower)
        push!(summary, "Root cause: Build/precompile failure")
        # Try to find the actual error line
        for line in split(combined, '\n')
            stripped = strip(String(line))
            if occursin("ERROR:", stripped)
                push!(summary, stripped[1:min(80, length(stripped))])
                length(summary) >= 4 && break
            end
        end
        return summary
    end

    # ── Git errors ──
    if occursin("git", lower) && (occursin("error", lower) || occursin("fatal", lower))
        push!(summary, "Root cause: Git error")
        push!(summary, "Registry or package repo could not be cloned/fetched.")
        return summary
    end

    # ── Fallback: extract first ERROR: line ──
    push!(summary, "Root cause: Install failed")
    for line in split(combined, '\n')
        stripped = strip(String(line))
        if startswith(stripped, "ERROR:") || startswith(stripped, "error:")
            msg = stripped[1:min(78, length(stripped))]
            push!(summary, msg)
            break
        end
    end
    if length(summary) == 1
        push!(summary, "See error details and Pkg output below.")
    end

    return summary
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
        push!(
            suggestions,
            "Check if $(pkg_name) supports your Julia version (v$(VERSION)).",
        )
        push!(suggestions, "Look for compat constraints in your Project.toml.")
        push!(
            suggestions,
            "Consider: Pkg.add(name=\"$(pkg_name)\", version=\"older-version\").",
        )
    end

    if occursin("not found", msg_lower) || occursin("does not exist", msg_lower)
        push!(suggestions, "Package '$(pkg_name)' was not found in the registry.")
        push!(suggestions, "Check the spelling of the package name.")
        push!(suggestions, "The package may not be registered in General registry.")
        push!(suggestions, "Try: Pkg.add(url=\"https://github.com/...\")")
    end

    if occursin("network", msg_lower) ||
       occursin("dns", msg_lower) ||
       occursin("timeout", msg_lower)
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
            (result = result, log = String(take!(io)), name = pkg_name)
        end
        return
    end

    if evt.key == :char && evt.char == 'o'
        tr.pkg_output_expanded = !tr.pkg_output_expanded
        build_triage_content!(tr, m.project_info)
        return
    end
end
