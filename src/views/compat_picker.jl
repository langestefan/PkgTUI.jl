"""
    Compat range picker overlay for the Installed Packages tab.
"""

# ──────────────────────────────────────────────────────────────────────────────
# Range computation
# ──────────────────────────────────────────────────────────────────────────────

"""
    _format_compat_ranges(spec_str) → String

Return a human-readable interval representation of the compat spec, e.g.
`[1.2.0, 3.0.0)` or `[0.2.0, 0.3.0) ∪ [1.0.0, 2.0.0)`.
Returns `""` on empty input or parse error.

Implemented directly from the Julia compat spec rules to avoid relying on
Pkg.Types internals whose representation may vary across versions.
"""
function _format_compat_ranges(spec_str::String)::String
    stripped = strip(spec_str)
    isempty(stripped) && return ""
    try
        parts = [strip(p) for p in split(stripped, ",")]
        filter!(!isempty, parts)
        ranges = map(_compat_single_range, parts)
        any(isnothing, ranges) && return ""
        return join(something.(ranges), " ∪ ")
    catch
        return ""
    end
end

"""Parse "X", "X.Y", or "X.Y.Z" → (major, minor|nothing, patch|nothing)."""
function _compat_vparts(s::AbstractString)::Tuple{Int,Union{Int,Nothing},Union{Int,Nothing}}
    m = match(r"^(\d+)(?:\.(\d+)(?:\.(\d+))?)?$", strip(s))
    m === nothing && throw(ArgumentError("bad version: $s"))
    return (
        parse(Int, m[1]),
        m[2] === nothing ? nothing : parse(Int, m[2]),
        m[3] === nothing ? nothing : parse(Int, m[3]),
    )
end

"""Format lower bound as "X.Y.Z" (defaulting missing components to 0)."""
_compat_lo(maj, min_, pat) = "$(maj).$(something(min_, 0)).$(something(pat, 0))"

"""Exclusive upper VersionNumber for a caret/bare spec."""
function _caret_upper(
    maj::Int,
    min_::Union{Int,Nothing},
    pat::Union{Int,Nothing},
)::VersionNumber
    if maj > 0
        VersionNumber(maj + 1, 0, 0)
    elseif min_ !== nothing && min_ > 0
        VersionNumber(0, min_ + 1, 0)
    elseif pat !== nothing && pat > 0
        VersionNumber(0, something(min_, 0), pat + 1)
    elseif min_ === nothing
        VersionNumber(1, 0, 0)                          # ^0
    elseif pat === nothing
        VersionNumber(0, min_ + 1, 0)                  # ^0.0
    else
        VersionNumber(0, something(min_, 0), pat + 1)  # ^0.0.0
    end
end

"""Exclusive upper VersionNumber for a tilde spec."""
function _tilde_upper(
    maj::Int,
    min_::Union{Int,Nothing},
    pat::Union{Int,Nothing},
)::VersionNumber
    pat !== nothing ? VersionNumber(maj, something(min_, 0) + 1, 0) :
    VersionNumber(maj + 1, 0, 0)
end

"""Compute range string for a caret (^) or bare version spec."""
function _compat_caret(s::AbstractString)::Union{String,Nothing}
    maj, min_, pat = _compat_vparts(s)
    lo = _compat_lo(maj, min_, pat)
    hi = _caret_upper(maj, min_, pat)
    "[$lo, $hi)"
end

"""Compute range string for a tilde (~) spec."""
function _compat_tilde(s::AbstractString)::Union{String,Nothing}
    maj, min_, pat = _compat_vparts(s)
    lo = _compat_lo(maj, min_, pat)
    hi = _tilde_upper(maj, min_, pat)
    "[$lo, $hi)"
end

"""Dispatch a single comma-free spec token to the correct range formatter."""
function _compat_single_range(s::AbstractString)::Union{String,Nothing}
    s = strip(s)
    # Operator detection — order matters: >= before >, <= before <
    m = match(r"^(>=|≥|<=|≤|\^|~|=|>(?!=)|<(?!=))\s*(.+)$", s)
    op = m === nothing ? "^" : String(m[1])
    ver = m === nothing ? s : strip(m[2])
    if op == "^"
        return _compat_caret(ver)
    elseif op == "~"
        return _compat_tilde(ver)
    elseif op == "="
        return "{$(ver)}"
    elseif op == ">=" || op == "≥"
        maj, min_, pat = _compat_vparts(ver)
        return "[$(maj).$(something(min_, 0)).$(something(pat, 0)), ∞)"
    elseif op == ">"
        return "($(ver), ∞)"
    elseif op == "<=" || op == "≤"
        return "[0.0.0, $(ver)]"
    elseif op == "<"
        return "[0.0.0, $(ver))"
    end
    return nothing
end

# ──────────────────────────────────────────────────────────────────────────────
# Redundancy detection
# ──────────────────────────────────────────────────────────────────────────────

"""
    _token_to_interval(token) → (lo, hi) | nothing

Convert a single spec token to a half-open interval `[lo, hi)` as a pair of
`VersionNumber` values.  `hi = nothing` means no upper bound (∞).
Returns `nothing` when the token cannot be parsed.
"""
function _token_to_interval(
    token::AbstractString,
)::Union{Tuple{VersionNumber,Union{VersionNumber,Nothing}},Nothing}
    s = strip(token)
    m = match(r"^(>=|≥|<=|≤|\^|~|=|>(?!=)|<(?!=))\s*(.+)$", s)
    op = m === nothing ? "^" : String(m[1])
    ver = m === nothing ? s : strip(m[2])
    try
        maj, min_, pat = _compat_vparts(ver)
        lo = VersionNumber(maj, something(min_, 0), something(pat, 0))
        if op == "^"
            return (lo, _caret_upper(maj, min_, pat))
        elseif op == "~"
            return (lo, _tilde_upper(maj, min_, pat))
        elseif op == "="
            return (lo, VersionNumber(maj, something(min_, 0), something(pat, 0) + 1))
        elseif op == ">=" || op == "≥"
            return (lo, nothing)
        elseif op == ">"
            return (VersionNumber(maj, something(min_, 0), something(pat, 0) + 1), nothing)
        elseif op == "<=" || op == "≤"
            return (v"0.0.0", VersionNumber(maj, something(min_, 0), something(pat, 0) + 1))
        elseif op == "<"
            return (v"0.0.0", lo)
        end
    catch
    end
    return nothing
end

"""
    _redundant_ranges(spec_str) → Vector{String}

Return the spec tokens (trimmed) that are fully covered by another token in the
same comma-separated spec.  An empty vector means no redundancy was detected.
"""
function _redundant_ranges(spec_str::String)::Vector{String}
    stripped = strip(spec_str)
    isempty(stripped) && return String[]
    tokens = [strip(p) for p in split(stripped, ",")]
    filter!(!isempty, tokens)
    length(tokens) <= 1 && return String[]

    intervals = [_token_to_interval(t) for t in tokens]
    redundant = String[]

    for i in eachindex(tokens)
        iv_i = intervals[i]
        iv_i === nothing && continue
        lo_i, hi_i = iv_i
        for j in eachindex(tokens)
            i == j && continue
            iv_j = intervals[j]
            iv_j === nothing && continue
            lo_j, hi_j = iv_j
            # Does interval j fully contain interval i?
            j_contains_i =
                lo_j <= lo_i && (hi_j === nothing || (hi_i !== nothing && hi_i <= hi_j))
            if j_contains_i
                push!(redundant, tokens[i])
                break
            end
        end
    end
    return redundant
end

# ──────────────────────────────────────────────────────────────────────────────
# Filtering
# ──────────────────────────────────────────────────────────────────────────────

"""
    _filter_by_compat(versions, spec_str) → (matching, parse_error)

Filter `versions` to those satisfying the compat spec string.  Returns all
versions unchanged when `spec_str` is empty.  Returns `([], true)` when the
spec cannot be parsed.
"""
function _filter_by_compat(
    versions::Vector{String},
    spec_str::String,
)::Tuple{Vector{String},Bool}
    stripped = strip(spec_str)
    isempty(stripped) && return (versions, false)
    try
        spec = Pkg.Types.semver_spec(String(stripped))
        matching = filter(v -> VersionNumber(v) in spec, versions)
        return (matching, false)
    catch
        return (String[], true)
    end
end

"""Recompute `cp.matching` and `cp.parse_error` from the current input text."""
function _update_compat_matching!(cp::CompatPickerState)
    cp.matching, cp.parse_error = _filter_by_compat(cp.versions, text(cp.input))
    cp.scroll_offset = 0
end

"""
    _wrap_range_lines(range_str, avail) → Vector{String}

Split `range_str` (a " ∪ "-separated interval string) into lines that each
fit within `avail` columns.  Breaks only at " ∪ " boundaries.
"""
function _wrap_range_lines(range_str::String, avail::Int)::Vector{String}
    parts = split(range_str, " ∪ ")
    lines = String[]
    current = ""
    for part in parts
        s = String(part)
        if isempty(current)
            current = s
        elseif length(current) + 3 + length(s) <= avail  # 3 == length(" ∪ ")
            current = current * " ∪ " * s
        else
            push!(lines, current)
            current = s
        end
    end
    isempty(current) || push!(lines, current)
    return isempty(lines) ? [range_str] : lines
end

# ──────────────────────────────────────────────────────────────────────────────
# Rendering
# ──────────────────────────────────────────────────────────────────────────────

"""
    render_compat_picker(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the compat range picker as a centered overlay.  The resolved interval,
redundancy warning, and version list update live as the user types.
"""
function render_compat_picker(m::PkgTUIApp, area::Rect, buf::Buffer)
    cp = m.compat_picker

    w = min(area.width - 4, 62)
    inner_width = w - 2  # strip double-border

    # Pre-compute range lines so the layout height can adapt.
    spec_str = strip(text(cp.input))
    range_lines = String[]
    if !isempty(spec_str) && !cp.parse_error
        rs = _format_compat_ranges(String(spec_str))
        if !isempty(rs)
            # " Range: " prefix is 8 chars; remaining width for the intervals.
            range_lines = _wrap_range_lines(rs, inner_width - 8)
        end
    end
    n_range_lines = max(1, length(range_lines))

    h = min(area.height - 4, 21 + n_range_lines)
    h = max(h, 14)
    overlay_rect = center(area, w, h)

    # Clear background
    blank = " "^overlay_rect.width
    for y = overlay_rect.y:(overlay_rect.y+overlay_rect.height-1)
        set_string!(buf, overlay_rect.x, y, blank, tstyle(:text))
    end

    inner = render(
        Block(
            title = " Set Compat — $(cp.package_name) ",
            border_style = tstyle(:accent),
            box = BOX_DOUBLE,
        ),
        overlay_rect,
        buf,
    )

    # Layout: current hint | input | separator | range (≥1 line) | warning | version list | status bar
    rows = split_layout(
        Layout(
            Vertical,
            [
                Fixed(1),
                Fixed(1),
                Fixed(1),
                Fixed(n_range_lines),
                Fixed(1),
                Fill(),
                Fixed(1),
            ],
        ),
        inner,
    )
    current_area = rows[1]
    input_area = rows[2]
    sep_area = rows[3]
    range_area = rows[4]
    warn_area = rows[5]
    list_area = rows[6]
    status_area = rows[7]

    # ── Current compat hint ──
    if !isempty(cp.current_compat)
        set_string!(buf, current_area.x, current_area.y, " Current: ", tstyle(:text_dim))
        set_string!(
            buf,
            current_area.x + 10,
            current_area.y,
            "\"$(cp.current_compat)\"",
            tstyle(:secondary),
        )
    else
        set_string!(
            buf,
            current_area.x,
            current_area.y,
            " No compat entry set",
            tstyle(:text_dim),
        )
    end

    # ── Input ──
    render(cp.input, input_area, buf)

    # ── Separator ──
    set_string!(buf, sep_area.x, sep_area.y, "─"^sep_area.width, tstyle(:border))

    # ── Resolved range ──
    if !isempty(spec_str) && !cp.parse_error && !isempty(range_lines)
        set_string!(buf, range_area.x, range_area.y, " Range: ", tstyle(:text_dim))
        for (i, line) in enumerate(range_lines)
            set_string!(
                buf,
                range_area.x + 8,
                range_area.y + i - 1,
                line,
                tstyle(:primary, bold = true),
            )
        end
    elseif cp.parse_error
        set_string!(
            buf,
            range_area.x,
            range_area.y,
            " Range: (invalid spec)",
            tstyle(:error),
        )
    else
        set_string!(buf, range_area.x, range_area.y, " Range: —", tstyle(:text_dim))
    end

    # ── Redundancy warning ──
    if !isempty(spec_str) && !cp.parse_error
        redundant = _redundant_ranges(String(spec_str))
        if !isempty(redundant)
            labels = join(("\"$r\"" for r in redundant), ", ")
            set_string!(
                buf,
                warn_area.x,
                warn_area.y,
                " ⚠ Redundant: $labels",
                tstyle(:warning),
            )
        end
    end

    # ── Version list ──
    if cp.loading
        set_string!(
            buf,
            list_area.x + 1,
            list_area.y,
            " Loading versions...",
            tstyle(:text_dim, italic = true),
        )
    else
        display_versions = isempty(spec_str) ? cp.versions : cp.matching
        n_matching = length(cp.matching)
        n_total = length(cp.versions)

        header_str, header_style = if cp.parse_error
            " Invalid compat spec", tstyle(:error)
        elseif isempty(spec_str)
            " All versions ($n_total) — type a spec to filter:", tstyle(:text_dim)
        elseif n_matching == 0
            " No versions match", tstyle(:warning)
        else
            " Matching: $n_matching / $n_total", tstyle(:success)
        end
        set_string!(buf, list_area.x, list_area.y, header_str, header_style)

        visible = list_area.height - 1  # minus the header row
        cp.scroll_offset =
            clamp(cp.scroll_offset, 0, max(0, length(display_versions) - visible))

        for i = 1:visible
            idx = i + cp.scroll_offset
            idx > length(display_versions) && break
            y = list_area.y + i
            ver_str = "v" * display_versions[idx]
            set_string!(buf, list_area.x + 1, y, "●", tstyle(:accent))
            set_string!(buf, list_area.x + 3, y, ver_str, tstyle(:text))
            if idx == 1
                set_string!(
                    buf,
                    list_area.x + 3 + length(ver_str) + 1,
                    y,
                    "(latest)",
                    tstyle(:text_dim),
                )
            end
        end
    end

    # ── Status bar ──
    render(
        StatusBar(
            left = [
                Span("  [Enter] apply ", tstyle(:accent)),
                Span("[Esc] cancel ", tstyle(:text_dim)),
                Span("[↑↓] scroll versions ", tstyle(:text_dim)),
            ],
            right = [],
        ),
        status_area,
        buf,
    )
end

# ──────────────────────────────────────────────────────────────────────────────
# Key handling
# ──────────────────────────────────────────────────────────────────────────────

"""
    handle_compat_picker_keys!(m::PkgTUIApp, evt::KeyEvent) → Bool

Handle keyboard input for the compat picker overlay.
"""
function handle_compat_picker_keys!(m::PkgTUIApp, evt::KeyEvent)::Bool
    cp = m.compat_picker

    if evt.key == :escape
        cp.show = false
        return true
    elseif evt.key == :enter
        if !cp.parse_error
            spec = strip(text(cp.input))
            pkg_name = cp.package_name
            cp.show = false
            push_log!(m, "Setting compat for $pkg_name...")
            spawn_task!(m.tq, :set_compat) do
                io = IOBuffer()
                result = set_compat(pkg_name, String(spec), io)
                (result = result, log = String(take!(io)))
            end
        end
        return true
    elseif evt.key == :up
        cp.scroll_offset = max(0, cp.scroll_offset - 1)
        return true
    elseif evt.key == :down
        spec_str = strip(text(cp.input))
        display_versions = isempty(spec_str) ? cp.versions : cp.matching
        cp.scroll_offset = min(cp.scroll_offset + 1, max(0, length(display_versions) - 1))
        return true
    elseif evt.key == :pageup
        cp.scroll_offset = max(0, cp.scroll_offset - 10)
        return true
    elseif evt.key == :pagedown
        spec_str = strip(text(cp.input))
        display_versions = isempty(spec_str) ? cp.versions : cp.matching
        cp.scroll_offset = min(cp.scroll_offset + 10, max(0, length(display_versions) - 1))
        return true
    else
        handle_key!(cp.input, evt)
        _update_compat_matching!(cp)
        return true
    end
end
