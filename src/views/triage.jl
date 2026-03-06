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
Uses styled `Vector{Vector{Span}}` content for color-coded output.
For unsatisfiable requirements errors, adds version range bar visualization
and color-coded dependency tree.
"""
function build_triage_content!(tr::TriageState, project_info::ProjectInfo)
    lines = Vector{Span}[]

    # ── Header ──
    push!(lines, [
        Span("  Package: ", tstyle(:text_dim)),
        Span(tr.package_name, tstyle(:accent, bold = true)),
    ])
    push!(lines, [Span("")])

    # Prepare error text
    error_text = tr.error_message
    if startswith(error_text, "Error in add: ")
        error_text = error_text[length("Error in add: ")+1:end]
    end
    combined = error_text * (isempty(strip(tr.pkg_log)) ? "" : "\n" * tr.pkg_log)
    is_unsat = occursin("unsatisfiable", lowercase(combined))

    if is_unsat
        # ── Version Range Bars (visual summary) ──
        pkgs = _parse_resolver_log(combined)
        if !isempty(pkgs)
            push!(lines, [Span("  Version Ranges", tstyle(:accent, bold = true))])
            push!(lines, [Span("  " * "─"^40, tstyle(:text_dim))])
            push!(lines, [Span("")])
            append!(lines, _build_ver_bars(pkgs, 30))
        end
    end

    # ── Error details (collapsible) ──
    detail_lines = String[]
    for raw_line in split(error_text, '\n')
        line = String(raw_line)
        if length(line) <= 80
            push!(detail_lines, line)
        else
            remaining = line
            while length(remaining) > 80
                idx = findlast(' ', remaining[1:min(80, length(remaining))])
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

    push!(lines, [Span("")])
    if tr.pkg_output_expanded
        push!(lines, [
            Span("  Error Details  ", tstyle(:text)),
            Span("[o] collapse ▴", tstyle(:success)),
        ])
        push!(lines, [Span("  " * "─"^40, tstyle(:text_dim))])
        push!(lines, [Span("")])
        if is_unsat
            for dl in detail_lines
                push!(lines, _colorize_tree_line("  " * dl))
            end
        else
            for dl in detail_lines
                push!(lines, [Span("  " * dl, tstyle(:text))])
            end
        end
    else
        push!(lines, [
            Span("  Error Details  ", tstyle(:text)),
            Span("[o] expand ▾", tstyle(:accent)),
            Span("  ($(length(detail_lines)) lines hidden)", tstyle(:text_dim)),
        ])
        push!(lines, [Span("  " * "─"^40, tstyle(:text_dim))])
    end

    # ── Diagnostics ──
    push!(lines, [Span("")])
    push!(lines, [Span("  Diagnostics", tstyle(:text, bold = true))])
    push!(lines, [Span("  " * "─"^40, tstyle(:text_dim))])

    julia_ver = string(VERSION)
    env_path = something(project_info.path, "unknown")
    env_name = something(project_info.name, basename(dirname(env_path)))

    push!(lines, [
        Span("  Julia version:  ", tstyle(:text_dim)),
        Span("v$julia_ver", tstyle(:text)),
    ])
    push!(lines, [
        Span("  Environment:    ", tstyle(:text_dim)),
        Span(env_name, tstyle(:text)),
    ])
    push!(lines, [
        Span("  Env path:       ", tstyle(:text_dim)),
        Span(env_path, tstyle(:text)),
    ])
    push!(lines, [
        Span("  Direct deps:    ", tstyle(:text_dim)),
        Span("$(project_info.dep_count)", tstyle(:text)),
    ])

    # ── Suggestions ──
    push!(lines, [Span("")])
    push!(lines, [Span("  Suggestions", tstyle(:text, bold = true))])
    push!(lines, [Span("  " * "─"^40, tstyle(:text_dim))])

    suggestions = analyze_error(tr.error_message, tr.package_name)
    for s in suggestions
        push!(lines, [Span("  • ", tstyle(:text_dim)), Span(s, tstyle(:text))])
    end

    push!(lines, [Span("")])

    # Build the scroll pane with styled content
    tr.scroll_pane = ScrollPane(lines; following = false)
end

# ══════════════════════════════════════════════════════════════════════════════
# Unsatisfiable requirements — parsing, version bars, and tree colorization
# ══════════════════════════════════════════════════════════════════════════════

"""Convert a version string like `"1.29.4"` to a numeric value for proportional bar placement."""
function _ver_to_num(s::AbstractString)::Float64
    parts = split(strip(s), '.')
    val = 0.0
    for (i, p) in enumerate(parts)
        n = tryparse(Float64, String(p))
        n === nothing && continue
        val += n * (1_000_000.0^(1 - i))
    end
    return val
end

"""Parse a version range string `"X.Y.Z - A.B.C"` or `"X.Y.Z"` into `(min, max)` strings."""
function _parse_ver_range(s::AbstractString)::Tuple{String,String}
    s = strip(String(s))
    m = match(r"^(.+?)\s+-\s+(.+)$", s)
    m !== nothing && return (strip(String(m.captures[1])), strip(String(m.captures[2])))
    return (s, s)
end

# ── Structured types for parsed resolver data ──

struct _VerConstraint
    source::String
    ver_min::String
    ver_max::String
    is_conflict::Bool
end

struct _PkgVerInfo
    name::String
    possible_min::String
    possible_max::String
    constraints::Vector{_VerConstraint}
end

"""
    _parse_resolver_log(text) → Vector{_PkgVerInfo}

Parse the Pkg resolver "Unsatisfiable requirements" output into structured
version info for each package in the conflict chain.
"""
function _parse_resolver_log(text::String)::Vector{_PkgVerInfo}
    pkgs = _PkgVerInfo[]
    cur_name = ""
    cur_pmin = ""
    cur_pmax = ""
    cur_cs = _VerConstraint[]

    for raw_line in split(text, '\n')
        line = strip(String(raw_line))
        isempty(line) && continue

        # Package header: "PkgName [uuid] log:"
        m = match(r"([A-Za-z]\w+)\s+\[[0-9a-f]+\]\s+log:", line)
        if m !== nothing
            if !isempty(cur_name) && !isempty(cur_pmin)
                push!(pkgs, _PkgVerInfo(cur_name, cur_pmin, cur_pmax, copy(cur_cs)))
            end
            cur_name = String(m.captures[1])
            cur_pmin = cur_pmax = ""
            cur_cs = _VerConstraint[]
            continue
        end

        # Possible versions: "possible versions are: X - Y or uninstalled"
        m = match(r"possible versions are:\s*(.+?)\s+or\s+uninstalled", line)
        if m !== nothing
            cur_pmin, cur_pmax = _parse_ver_range(String(m.captures[1]))
            continue
        end

        # Fixed: "PkgName [uuid] is fixed to version X.Y.Z"
        m = match(r"is fixed to version\s+(\S+)", line)
        if m !== nothing
            v = String(m.captures[1])
            push!(cur_cs, _VerConstraint("fixed", v, v, false))
            continue
        end

        # Conflict: "restricted by compatibility requirements with PKG [uuid] to versions: uninstalled"
        m = match(
            r"restricted by compatibility requirements with\s+(\w[\w.]*)\s+\[[0-9a-f]+\]\s+to versions:\s*uninstalled",
            line,
        )
        if m !== nothing
            push!(cur_cs, _VerConstraint(String(m.captures[1]), "", "", true))
            continue
        end

        # Restricted with remaining: "restricted to versions X by SOURCE, leaving only versions: Y"
        m = match(
            r"restricted to versions\s+(.+?)\s+by\s+(.+?),\s*leaving only versions:\s*(.+)",
            line,
        )
        if m !== nothing
            source_raw = String(m.captures[2])
            source = if occursin("explicit", lowercase(source_raw))
                "explicit"
            else
                replace(source_raw, r"\s*\[[0-9a-f]+\].*" => "")
            end
            rmin, rmax = _parse_ver_range(String(m.captures[3]))
            push!(cur_cs, _VerConstraint(source, rmin, rmax, false))
            continue
        end

        # Restricted by explicit without "leaving" clause
        m = match(
            r"restricted to versions\s+(.+?)\s+by\s+an\s+explicit\s+requirement",
            line,
        )
        if m !== nothing && !any(c -> c.source == "explicit", cur_cs)
            rmin, rmax = _parse_ver_range(String(m.captures[1]))
            push!(cur_cs, _VerConstraint("explicit", rmin, rmax, false))
            continue
        end
    end

    # Save last package
    if !isempty(cur_name) && !isempty(cur_pmin)
        push!(pkgs, _PkgVerInfo(cur_name, cur_pmin, cur_pmax, copy(cur_cs)))
    end

    return pkgs
end

"""Build styled horizontal version range bars for all packages in the conflict."""
function _build_ver_bars(pkgs::Vector{_PkgVerInfo}, bar_w::Int)::Vector{Vector{Span}}
    lines = Vector{Span}[]
    label_w = 13

    for pkg in pkgs
        pmin_n = _ver_to_num(pkg.possible_min)
        pmax_n = _ver_to_num(pkg.possible_max)
        range_total = pmax_n - pmin_n

        # Package name header
        push!(lines, [Span("    $(pkg.name)", tstyle(:accent, bold = true))])

        # Available bar (full green)
        ver_str = if pkg.possible_min == pkg.possible_max
            pkg.possible_min
        else
            "$(pkg.possible_min) — $(pkg.possible_max)"
        end
        push!(lines, [
            Span("    " * rpad("Available", label_w), tstyle(:text_dim)),
            Span("█"^bar_w, tstyle(:success)),
            Span("  $ver_str", tstyle(:success)),
        ])

        # Each constraint bar
        for c in pkg.constraints
            label = rpad(c.source, label_w)

            if c.is_conflict
                push!(lines, [
                    Span("    $label", tstyle(:text_dim)),
                    Span("░"^bar_w, tstyle(:error)),
                    Span("  ✗ conflict", tstyle(:error)),
                ])
            else
                cmin_n = _ver_to_num(c.ver_min)
                cmax_n = _ver_to_num(c.ver_max)

                if range_total > 0
                    start_frac = clamp((cmin_n - pmin_n) / range_total, 0.0, 1.0)
                    end_frac = clamp((cmax_n - pmin_n) / range_total, 0.0, 1.0)
                else
                    start_frac = 0.0
                    end_frac = 1.0
                end

                start_pos = round(Int, start_frac * bar_w)
                end_pos = round(Int, end_frac * bar_w)
                end_pos = max(end_pos, start_pos + 1)
                end_pos = min(end_pos, bar_w)

                prefix_len = start_pos
                fill_len = end_pos - start_pos
                suffix_len = bar_w - end_pos

                ver_str = if c.ver_min == c.ver_max
                    c.ver_min
                else
                    "$(c.ver_min) — $(c.ver_max)"
                end

                spans = Span[Span("    $label", tstyle(:text_dim))]
                prefix_len > 0 && push!(spans, Span("░"^prefix_len, tstyle(:text_dim)))
                push!(spans, Span("█"^fill_len, tstyle(:warning)))
                suffix_len > 0 && push!(spans, Span("░"^suffix_len, tstyle(:text_dim)))
                push!(spans, Span("  $ver_str", tstyle(:warning)))
                push!(lines, spans)
            end
        end

        push!(lines, [Span("")])
    end

    return lines
end

"""
    _colorize_tree_line(raw) → Vector{Span}

Color-code a single line of the Pkg resolver tree output:
- Package names → accent (cyan)
- Version numbers → success (green)
- UUIDs → dim
- Conflict markers → error (red)
"""
function _colorize_tree_line(raw::String)::Vector{Span}
    isempty(strip(raw)) && return [Span("")]

    # Collect tokens: (byte_offset, byte_length, style)
    tokens = Tuple{Int,Int,Symbol}[]

    # UUIDs: [xxxxxxxx]
    for m in eachmatch(r"\[[0-9a-f]{4,}\]", raw)
        push!(tokens, (m.offset, ncodeunits(m.match), :text_dim))
    end

    # Conflict markers
    for m in eachmatch(r"no versions left", raw)
        push!(tokens, (m.offset, ncodeunits(m.match), :error))
    end
    for m in eachmatch(r"uninstalled", raw)
        # Only color "uninstalled" when it appears after "versions:"
        if m.offset > 1 && occursin("versions:", raw[1:prevind(raw, m.offset)])
            push!(tokens, (m.offset, ncodeunits(m.match), :error))
        end
    end

    # Version numbers/ranges (not overlapping existing tokens)
    for m in eachmatch(r"\d+\.\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+(?:\.\d+)?)?)?", raw)
        overlaps = any(t -> m.offset >= t[1] && m.offset < t[1] + t[2], tokens)
        !overlaps && push!(tokens, (m.offset, ncodeunits(m.match), :success))
    end

    # Package names (capitalized word before [uuid])
    for m in eachmatch(r"[A-Z]\w+(?=\s*\[)", raw)
        overlaps = any(t -> m.offset >= t[1] && m.offset < t[1] + t[2], tokens)
        !overlaps && push!(tokens, (m.offset, ncodeunits(m.match), :accent))
    end

    sort!(tokens, by = first)

    # Build spans from tokens with plain text in between
    spans = Span[]
    pos = 1
    for (off, len, style) in tokens
        if off > pos
            push!(spans, Span(String(SubString(raw, pos, prevind(raw, off))), tstyle(:text)))
        end
        tok_end = prevind(raw, off + len)
        push!(spans, Span(String(SubString(raw, off, tok_end)), tstyle(style)))
        pos = off + len
    end
    if pos <= ncodeunits(raw)
        push!(spans, Span(String(SubString(raw, pos)), tstyle(:text)))
    end

    isempty(spans) && return [Span(raw, tstyle(:text))]
    return spans
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
