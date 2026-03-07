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
                Span("  ↑↓←→ scroll ", tstyle(:text_dim)),
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
    push!(
        lines,
        [
            Span("  Package: ", tstyle(:text_dim)),
            Span(tr.package_name, tstyle(:accent, bold = true)),
        ],
    )
    push!(lines, [Span("")])

    # Prepare error text
    error_text = tr.error_message
    if startswith(error_text, "Error in add: ")
        error_text = error_text[length("Error in add: ")+1:end]
    end
    combined = error_text * (isempty(strip(tr.pkg_log)) ? "" : "\n" * tr.pkg_log)
    is_unsat = occursin("unsatisfiable", lowercase(combined))

    if is_unsat
        # ── Compat range lines (visual summary) ──
        pkgs = _parse_resolver_log(combined)
        if !isempty(pkgs)
            push!(lines, [Span("  Compat Ranges", tstyle(:accent, bold = true))])
            push!(lines, [Span("  " * "─"^40, tstyle(:text_dim))])
            push!(lines, [Span("")])
            append!(lines, _build_ver_bars(pkgs, 40))
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
        push!(
            lines,
            [
                Span("  Error Details  ", tstyle(:text)),
                Span("[o] collapse ▴", tstyle(:success)),
            ],
        )
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
        push!(
            lines,
            [
                Span("  Error Details  ", tstyle(:text)),
                Span("[o] expand ▾", tstyle(:accent)),
                Span("  ($(length(detail_lines)) lines hidden)", tstyle(:text_dim)),
            ],
        )
        push!(lines, [Span("  " * "─"^40, tstyle(:text_dim))])
    end

    # ── Diagnostics ──
    push!(lines, [Span("")])
    push!(lines, [Span("  Diagnostics", tstyle(:text, bold = true))])
    push!(lines, [Span("  " * "─"^40, tstyle(:text_dim))])

    julia_ver = string(VERSION)
    env_path = something(project_info.path, "unknown")
    env_name = something(project_info.name, basename(dirname(env_path)))

    push!(
        lines,
        [Span("  Julia version:  ", tstyle(:text_dim)), Span("v$julia_ver", tstyle(:text))],
    )
    push!(
        lines,
        [Span("  Environment:    ", tstyle(:text_dim)), Span(env_name, tstyle(:text))],
    )
    push!(
        lines,
        [Span("  Env path:       ", tstyle(:text_dim)), Span(env_path, tstyle(:text))],
    )
    push!(
        lines,
        [
            Span("  Direct deps:    ", tstyle(:text_dim)),
            Span("$(project_info.dep_count)", tstyle(:text)),
        ],
    )

    # ── Suggestions ──
    push!(lines, [Span("")])
    push!(lines, [Span("  Suggestions", tstyle(:text, bold = true))])
    push!(lines, [Span("  " * "─"^40, tstyle(:text_dim))])

    suggestions = analyze_error(tr.error_message, tr.package_name)
    for s in suggestions
        push!(lines, [Span("  • ", tstyle(:text_dim)), Span(s, tstyle(:text))])
    end

    push!(lines, [Span("")])

    # Store lines and build scroll pane with render callback for horizontal scroll
    tr._lines = lines
    render_fn = (buf, area, v_offset) -> begin
        h = tr.h_offset
        for i in 1:area.height
            idx = v_offset + i
            (idx < 1 || idx > length(tr._lines)) && continue
            y = area.y + i - 1
            col = area.x - h
            for span in tr._lines[idx]
                col > right(area) && break
                col = set_string!(buf, col, y, span.content, span.style;
                                  max_x = right(area))
            end
        end
    end
    tr.scroll_pane = ScrollPane(render_fn, length(lines); following = false)
end

# ══════════════════════════════════════════════════════════════════════════════
# Unsatisfiable requirements — parsing, version bars, and tree colorization
# ══════════════════════════════════════════════════════════════════════════════

"""Convert a version string like `"1.29.4"` to a numeric value for proportional positioning."""
function _ver_to_num(s::AbstractString)::Float64
    parts = split(strip(s), '.')
    val = 0.0
    # Weight: major * 10000, minor * 100, patch * 1
    weights = (10_000.0, 100.0, 1.0)
    for (i, p) in enumerate(parts)
        i > 3 && break
        n = tryparse(Float64, String(p))
        n === nothing && continue
        val += n * weights[i]
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

"""
    _parse_ver_ranges(s) → Vector{Tuple{String,String}}

Parse a comma-separated version range string like
`"0.0.1 - 3.1.1, 9.33.0 - 9.7.0"` into a vector of `(min, max)` pairs.
Also strips trailing `"or uninstalled"` from the input.
"""
function _parse_ver_ranges(s::AbstractString)::Vector{Tuple{String,String}}
    s = strip(String(s))
    # Strip trailing "or uninstalled"
    s = replace(s, r"\s+or\s+uninstalled\s*$"i => "")
    isempty(s) && return Tuple{String,String}[]
    ranges = Tuple{String,String}[]
    for part in split(s, ',')
        part = strip(String(part))
        isempty(part) && continue
        m = match(r"^(.+?)\s+-\s+(.+)$", part)
        if m !== nothing
            push!(ranges, (strip(String(m.captures[1])), strip(String(m.captures[2]))))
        else
            push!(ranges, (part, part))
        end
    end
    return ranges
end

# ── Structured types for parsed resolver data ──

struct _VerConstraint
    source::String
    ranges::Vector{Tuple{String,String}}  # each element is (ver_min, ver_max)
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

Handles **nested** resolver trees correctly by tracking the indentation
depth of each `PkgName [uuid] log:` header via a stack.  Content lines
(possible versions, constraints) are attributed to the nearest ancestor
package header whose depth is *less* than the current line's depth.
"""
function _parse_resolver_log(text::String)::Vector{_PkgVerInfo}
    # --- data accumulators (keyed by name, insertion-ordered) ---
    pkg_names = String[]
    pkg_possible = Dict{String,Tuple{String,String}}()
    pkg_constraints = Dict{String,Vector{_VerConstraint}}()

    # Stack of (name, char_depth) — outermost package first
    pkg_stack = Tuple{String,Int}[]

    for raw_line in split(text, '\n')
        line = strip(String(raw_line))
        isempty(line) && continue

        # ── Compute character depth: count of chars before first ASCII letter ──
        raw_str = String(raw_line)
        depth = 0
        found_alpha = false
        for ch in raw_str
            if isletter(ch) && isascii(ch)
                found_alpha = true
                break
            end
            depth += 1
        end
        found_alpha || continue   # line has no ASCII letters — skip

        # ── Package header: "PkgName [uuid] log:" ──
        m = match(r"([A-Za-z]\w+)\s+\[[^\]]+\]\s+log:", line)
        if m !== nothing
            name = String(m.captures[1])
            # Pop stack entries at same or deeper level (leaving scope)
            while !isempty(pkg_stack) && last(pkg_stack)[2] >= depth
                pop!(pkg_stack)
            end
            push!(pkg_stack, (name, depth))
            if !haskey(pkg_constraints, name)
                push!(pkg_names, name)
                pkg_possible[name] = ("", "")
                pkg_constraints[name] = _VerConstraint[]
            end
            continue
        end

        # ── Determine owning package from the stack ──
        # Walk the stack from deepest to shallowest; the first entry whose
        # depth is strictly less than the current line's depth owns this line.
        active = ""
        for i = length(pkg_stack):-1:1
            if pkg_stack[i][2] < depth
                active = pkg_stack[i][1]
                break
            end
        end
        if isempty(active) && !isempty(pkg_stack)
            active = last(pkg_stack)[1]
        end
        isempty(active) && continue

        # ── Possible versions: "possible versions are: X - Y or uninstalled" ──
        m = match(r"possible versions are:\s*(.+?)\s+or\s+uninstalled", line)
        if m !== nothing
            pmin, pmax = _parse_ver_range(String(m.captures[1]))
            pkg_possible[active] = (pmin, pmax)
            continue
        end

        # ── Fixed: "PkgName [uuid] is fixed to version X.Y.Z" ──
        m = match(r"is fixed to version\s+(\S+)", line)
        if m !== nothing
            v = String(m.captures[1])
            push!(pkg_constraints[active], _VerConstraint("fixed", [(v, v)], false))
            continue
        end

        # ── Conflict with range: "... to versions: X - Y — no versions left" ──
        m = match(
            r"restricted by compatibility requirements with\s+(\w[\w.]*)\s+\[[^\]]+\]\s+to versions:\s*(.+?)\s*(?:—|--|—)\s*no versions left",
            line,
        )
        if m !== nothing
            ranges = _parse_ver_ranges(String(m.captures[2]))
            push!(
                pkg_constraints[active],
                _VerConstraint(String(m.captures[1]), ranges, true),
            )
            continue
        end

        # ── Conflict (uninstalled): "... to versions: uninstalled" ──
        m = match(
            r"restricted by compatibility requirements with\s+(\w[\w.]*)\s+\[[^\]]+\]\s+to versions:\s*uninstalled",
            line,
        )
        if m !== nothing
            push!(
                pkg_constraints[active],
                _VerConstraint(String(m.captures[1]), Tuple{String,String}[], true),
            )
            continue
        end

        # ── Non-conflict compatibility constraint (no "no versions left") ──
        # "restricted by compatibility requirements with PKG [uuid] to versions: X - Y"
        # This narrows the range but still has versions left.
        m = match(
            r"restricted by compatibility requirements with\s+(\w[\w.]*)\s+\[[^\]]+\]\s+to versions:\s*(.+)",
            line,
        )
        if m !== nothing
            ranges = _parse_ver_ranges(String(m.captures[2]))
            push!(
                pkg_constraints[active],
                _VerConstraint(String(m.captures[1]), ranges, false),
            )
            continue
        end

        # ── Restricted with remaining: "restricted to versions X by SOURCE, leaving only versions: Y" ──
        m = match(
            r"restricted to versions\s+(.+?)\s+by\s+(.+?),\s*leaving only versions:\s*(.+)",
            line,
        )
        if m !== nothing
            source_raw = String(m.captures[2])
            source = if occursin("explicit", lowercase(source_raw))
                "explicit"
            else
                # Strip UUID brackets like [abcd1234-...] and any trailing text
                replace(source_raw, r"\s*\[[^\]]+\].*" => "")
            end
            ranges = _parse_ver_ranges(String(m.captures[3]))
            push!(pkg_constraints[active], _VerConstraint(source, ranges, false))
            continue
        end

        # ── Restricted by explicit without "leaving" clause ──
        m = match(
            r"restricted to versions\s+(.+?)\s+by\s+an\s+explicit\s+requirement",
            line,
        )
        if m !== nothing && !any(c -> c.source == "explicit", pkg_constraints[active])
            ranges = _parse_ver_ranges(String(m.captures[1]))
            push!(pkg_constraints[active], _VerConstraint("explicit", ranges, false))
            continue
        end
    end

    # ── Build result vector in insertion order ──
    pkgs = _PkgVerInfo[]
    for name in pkg_names
        pmin, pmax = pkg_possible[name]
        isempty(pmin) && continue
        push!(pkgs, _PkgVerInfo(name, pmin, pmax, pkg_constraints[name]))
    end

    return pkgs
end

"""
    _build_ver_bars(pkgs, line_w) → Vector{Vector{Span}}

Build a bars-only proportional line-chart of version ranges.
Every range is drawn on a shared horizontal axis so that overlapping /
non-overlapping regions are immediately visible.

**Conflict-centric grouping**: when package A requires dependency B but
no versions satisfy the constraint (conflict), the visualization groups
all constraints on B under a `✗ Conflict: B` header, then shows one
bar per constraint source (including the conflicting package's range):

    ✗ Conflict: JuMP
    Available      ├──────────────────────────────────────┤  0.18.3 — 1.30.0
    BilevelJuMP    ├────────┤                               0.21.0 — 0.21.10
    SolarPosition                             ├────────────┤  1.29.4 — 1.30.0
    Intersection:  ✗ none

Non-conflict packages are shown separately with their own sections.
"""
function _build_ver_bars(pkgs::Vector{_PkgVerInfo}, line_w::Int)::Vector{Vector{Span}}
    lines = Vector{Span}[]

    # Compute label width dynamically from all labels that will appear
    all_labels = String["Available", "Intersection"]
    for pkg in pkgs
        for c in pkg.constraints
            c.source != "fixed" && push!(all_labels, c.source)
        end
    end
    label_w = maximum(length, all_labels; init = 13) + 1

    # ── 1. Cross-reference: find conflict targets ──
    # A package that has any is_conflict constraint is a "conflict target" —
    # its version range can't be satisfied.  We show ONLY bars for that
    # package's constraints (Available + each constraint source).
    pkg_by_name = Dict(p.name => p for p in pkgs)
    conflict_targets = String[]  # names of packages whose deps can't be satisfied
    for pkg in pkgs
        if any(c -> c.is_conflict, pkg.constraints)
            push!(conflict_targets, pkg.name)
        end
    end

    # ── 2. Compute a single global axis across ALL packages & constraints ──
    global_min = Inf
    global_max = -Inf
    for pkg in pkgs
        pmin = _ver_to_num(pkg.possible_min)
        pmax = _ver_to_num(pkg.possible_max)
        global_min = min(global_min, pmin)
        global_max = max(global_max, pmax)
        for c in pkg.constraints
            for (rmin, rmax) in c.ranges
                isempty(rmin) && continue
                global_min = min(global_min, _ver_to_num(rmin))
                global_max = max(global_max, _ver_to_num(rmax))
            end
        end
    end
    axis_range = global_max - global_min
    axis_range = axis_range > 0 ? axis_range : 1.0

    # Helper: version number → column position (0-based, in [0, line_w-1])
    to_col(v::Float64) =
        clamp(round(Int, (v - global_min) / axis_range * (line_w - 1)), 0, line_w - 1)

    # ── Inner helper: build spans for a (possibly multi-range) line ──
    # `vranges` is a Vector of (min_str, max_str) pairs, e.g.
    #   [("0.0.1","3.1.1"), ("9.33.0","9.7.0")]
    function range_spans(
        label::String,
        vranges::Vector{Tuple{String,String}},
        style::Symbol,
    )
        lbl = rpad(label, label_w)

        # Compute column segments for each range
        segments = Tuple{Int,Int}[]
        for (vmin_str, vmax_str) in vranges
            cmin = to_col(_ver_to_num(vmin_str))
            cmax = to_col(_ver_to_num(vmax_str))
            cmax = max(cmax, cmin)
            push!(segments, (cmin, cmax))
        end

        # Build text label (all ranges joined by ", ")
        range_labels = String[]
        for (vmin, vmax) in vranges
            if vmin == vmax
                push!(range_labels, vmin)
            else
                push!(range_labels, "$vmin — $vmax")
            end
        end
        tag = join(range_labels, ", ")

        # Draw all segments onto one line buffer
        buf = fill(' ', line_w)
        for (cmin, cmax) in segments
            if cmin == cmax
                buf[cmin+1] = '│'
            else
                buf[cmin+1] = '├'
                for i = (cmin+2):cmax
                    buf[i] = '─'
                end
                buf[cmax+1] = '┤'
            end
        end

        # Build spans — color bar characters, dim everything else
        spans = Span[Span("    $lbl", tstyle(:text_dim))]
        i = 1
        while i <= length(buf)
            if buf[i] in ('├', '─', '┤', '│')
                j = i
                while j <= length(buf) && buf[j] in ('├', '─', '┤', '│')
                    j += 1
                end
                push!(spans, Span(String(buf[i:j-1]), tstyle(style)))
                i = j
            else
                j = i
                while j <= length(buf) && !(buf[j] in ('├', '─', '┤', '│'))
                    j += 1
                end
                push!(spans, Span(String(buf[i:j-1]), tstyle(:text_dim)))
                i = j
            end
        end

        push!(spans, Span("  $tag", tstyle(style)))
        return spans
    end

    # Convenience overload for a single (min, max) pair (e.g., Available range)
    range_spans(label::String, vmin::String, vmax::String, style::Symbol) =
        range_spans(label, [(vmin, vmax)], style)

    # ── 3. Conflict sections — bars only for the conflict target ──
    # Show ONLY the conflict target's bars: Available range + each constraint
    # that restricts it (both non-conflict and conflict constraints).
    # Do NOT show separate sections for other packages involved.
    shown_in_conflict = Set{String}()

    for target_name in conflict_targets
        haskey(pkg_by_name, target_name) || continue
        target = pkg_by_name[target_name]
        push!(shown_in_conflict, target_name)

        # Also mark all packages that appear as constraint sources — they
        # should NOT get their own non-conflict section below.
        for c in target.constraints
            push!(shown_in_conflict, c.source)
        end

        # Header
        push!(lines, [Span("    ✗ Conflict: $(target_name)", tstyle(:error, bold = true))])

        # Bar chart: Available range of the conflict target
        push!(
            lines,
            range_spans("Available", target.possible_min, target.possible_max, :success),
        )

        # One bar per constraint on this target, sorted by first range min ascending
        # so bars appear left-to-right on the chart.
        sorted_cs = sort(
            target.constraints;
            by = c -> isempty(c.ranges) ? Inf : _ver_to_num(first(c.ranges)[1]),
        )
        for c in sorted_cs
            c.source == "fixed" && continue   # skip "fixed" — not a requirer
            if c.is_conflict
                if !isempty(c.ranges)
                    # Conflict constraint with known range(s)
                    push!(lines, range_spans(c.source, c.ranges, :error))
                else
                    # Conflict constraint without range (e.g., "to versions: uninstalled")
                    lbl = rpad(c.source, label_w)
                    push!(
                        lines,
                        [
                            Span("    $lbl", tstyle(:text_dim)),
                            Span("✗ none", tstyle(:error)),
                        ],
                    )
                end
            else
                push!(lines, range_spans(c.source, c.ranges, :warning))
            end
        end

        push!(
            lines,
            [Span("    $(rpad("Intersection", label_w))", tstyle(:text_dim)), Span("✗ none", tstyle(:error))],
        )
        push!(lines, [Span("")])
    end

    # ── 4. Non-conflict package sections (only those not involved in a conflict) ──
    for pkg in pkgs
        pkg.name in shown_in_conflict && continue

        non_conflict_cs = filter(c -> !c.is_conflict, pkg.constraints)

        push!(lines, [Span("    $(pkg.name)", tstyle(:accent, bold = true))])
        push!(lines, range_spans("Available", pkg.possible_min, pkg.possible_max, :success))
        for c in non_conflict_cs
            push!(lines, range_spans(c.source, c.ranges, :warning))
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
            push!(
                spans,
                Span(String(SubString(raw, pos, prevind(raw, off))), tstyle(:text)),
            )
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

    if evt.key == :left
        tr.h_offset = max(0, tr.h_offset - 4)
        return
    end

    if evt.key == :right
        tr.h_offset += 4
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

    if evt.key == :home
        tr.h_offset = 0
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
