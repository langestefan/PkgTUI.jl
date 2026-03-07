"""
    Updates available tab view.
"""

"""
    render_updates_tab(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the "Updates" tab showing packages with available updates.
"""
function render_updates_tab(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.updates_state

    if st.show_dry_run && st.dry_run_output !== nothing
        render_dry_run_panel(m, area, buf)
        return
    end

    # If there are conflicts, split the area to show both
    has_conflicts = !isempty(m.conflicts.conflicts)
    if has_conflicts
        # Layout: updates table | conflicts panel | hints
        conflict_height = min(length(m.conflicts.conflicts) + 4, 10)
        rows =
            split_layout(Layout(Vertical, [Fill(), Fixed(conflict_height), Fixed(1)]), area)
    else
        # Layout: updates table | hints
        rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), area)
    end

    table_area = rows[1]
    inner = render(
        Block(
            title = "Available Updates ($(length(st.updates)))",
            border_style = tstyle(:border),
        ),
        table_area,
        buf,
    )

    if st.loading
        set_string!(
            buf,
            inner.x + 2,
            inner.y + 1,
            "Checking for updates...",
            tstyle(:text_dim, italic = true),
        )
    elseif isempty(st.updates)
        set_string!(
            buf,
            inner.x + 2,
            inner.y + 1,
            "All packages are up to date!",
            tstyle(:success),
        )
    else
        # Header
        render_updates_header(inner, buf)

        # Rows
        visible = inner.height - 2
        st.scroll_offset = clamp(st.scroll_offset, 0, max(0, length(st.updates) - visible))

        if st.selected > st.scroll_offset + visible
            st.scroll_offset = st.selected - visible
        elseif st.selected <= st.scroll_offset
            st.scroll_offset = max(0, st.selected - 1)
        end

        for i = 1:visible
            idx = i + st.scroll_offset
            idx > length(st.updates) && break
            info = st.updates[idx]
            y = inner.y + 1 + i
            is_updating = (info.name in st.updating_names) || st.update_all_running
            is_updated = info.name in st.updated_names
            render_update_row(
                info,
                inner.x,
                y,
                inner.width,
                buf,
                idx == st.selected,
                is_updating,
                is_updated,
                m.tick,
            )
        end
    end

    # Conflicts panel (if any)
    if has_conflicts
        render_conflicts_panel(m, rows[2], buf)
    end

    # Action hints
    # Conflict focus indicator
    conflict_hint =
        has_conflicts ?
        [
            Span(
                "[c]onflicts ",
                st.conflicts_focused ? tstyle(:accent, bold = true) : tstyle(:text_dim),
            ),
        ] : Span[]

    render(
        StatusBar(
            left = vcat(
                [
                    Span("  [u]pdate selected ", tstyle(:accent)),
                    Span("[U]pdate all ", tstyle(:accent)),
                    Span("[d]ry-run ", tstyle(:accent)),
                    Span("[R]efresh ", tstyle(:text_dim)),
                ],
                conflict_hint,
            ),
            right = [],
        ),
        rows[end],
        buf,
    )
end

"""Render updates table header."""
function render_updates_header(area::Rect, buf::Buffer)
    y = area.y
    style = tstyle(:title, bold = true)
    cx = area.x + 1

    set_string!(buf, cx, y, " ", style)
    set_string!(buf, cx + 2, y, "Package", style)
    set_string!(buf, cx + 25, y, "Current", style)
    set_string!(buf, cx + 38, y, "Latest", style)
    set_string!(buf, cx + 51, y, "Blocked By", style)

    for x = area.x:(area.x+area.width-1)
        set_char!(buf, x, y + 1, '─', tstyle(:border))
    end
end

"""Render a single update info row."""
function render_update_row(
    info::UpdateInfo,
    x::Int,
    y::Int,
    width::Int,
    buf::Buffer,
    selected::Bool,
    is_updating::Bool = false,
    is_updated::Bool = false,
    tick::Int = 0,
)
    cx = x + 1

    # Status indicator
    indicator = info.can_update ? "⌃" : "⌅"
    ind_style =
        info.can_update ? tstyle(:success, bold = true) : tstyle(:warning, bold = true)
    set_string!(buf, cx, y, indicator, selected ? tstyle(:accent, bold = true) : ind_style)

    # Package name — green when updated
    name_style = if is_updated
        tstyle(:success, bold = selected)
    elseif selected
        tstyle(:accent, bold = true)
    else
        tstyle(:primary)
    end
    set_string!(buf, cx + 2, y, info.name, name_style)

    # Current version
    set_string!(
        buf,
        cx + 25,
        y,
        "v" * info.current_version,
        selected ? tstyle(:accent) : tstyle(:text),
    )

    # Latest version
    latest =
        info.latest_compatible !== nothing ? info.latest_compatible :
        info.latest_available !== nothing ? info.latest_available : "—"
    latest_str = latest == "—" ? latest : "v" * latest
    set_string!(buf, cx + 38, y, latest_str, selected ? tstyle(:accent) : tstyle(:success))

    # Status / blocker column
    status_x = cx + 51
    if is_updating
        spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        frame = mod(tick ÷ 4, length(spinner_chars)) + 1
        set_string!(
            buf,
            status_x,
            y,
            "$(spinner_chars[frame]) Updating…",
            tstyle(:warning, bold = true),
        )
    elseif is_updated
        set_string!(buf, status_x, y, "Updated ✓", tstyle(:success))
    elseif info.blocker !== nothing && status_x + length(info.blocker) <= x + width
        set_string!(
            buf,
            status_x,
            y,
            "⌅ " * info.blocker,
            selected ? tstyle(:accent) : tstyle(:error),
        )
    elseif info.can_update
        set_string!(buf, status_x, y, "—", tstyle(:text_dim))
    end

    # Selection indicator
    if selected
        set_string!(buf, cx - 1, y, "▶", tstyle(:accent))
    end
end

# ── Dry-run section helpers ───────────────────────────────────────────────────

"""Section display order for the dry-run diff panel."""
const _DRY_RUN_SECTION_ORDER = [:upgraded, :downgraded, :added, :removed]

"""Return the ordered list of sections that have entries in `diff`."""
function _dry_run_section_order(diff::Union{DryRunDiff,Nothing})::Vector{Symbol}
    diff === nothing && return Symbol[]
    order = Symbol[]
    for kind in _DRY_RUN_SECTION_ORDER
        any(e -> e.kind == kind, diff.entries) && push!(order, kind)
    end
    return order
end

"""Section icon, label, and style for a given kind."""
function _section_meta(kind::Symbol)
    if kind == :upgraded
        return "⬆", "upgraded", :success
    elseif kind == :downgraded
        return "⬇", "downgraded", :warning
    elseif kind == :added
        return "+", "added", :success
    elseif kind == :removed
        return "−", "removed", :error
    else
        return " ", string(kind), :text_dim
    end
end

"""
    _build_dry_run_lines(st) → Vector{NamedTuple}

Build a flat list of virtual lines for the dry-run panel.
Each line is a NamedTuple with `:kind` (∈ {:header, :entry, :blank})
and associated data.  Section headers are always present;
entries appear only when the section is expanded.
"""
function _build_dry_run_lines(st::UpdatesState)
    diff = st.dry_run_output
    diff === nothing && return NamedTuple[]
    (diff.error !== nothing || isempty(diff.entries)) && return NamedTuple[]

    lines = NamedTuple[]
    sections = _dry_run_section_order(diff)
    for (si, kind) in enumerate(sections)
        entries = filter(e -> e.kind == kind, diff.entries)
        expanded = get(st.dry_run_sections, kind, true)
        icon, label, style_sym = _section_meta(kind)
        push!(
            lines,
            (kind = :header, section = kind, section_idx = si,
             icon = icon, label = label, count = length(entries),
             expanded = expanded, style_sym = style_sym),
        )
        if expanded
            for entry in entries
                push!(lines, (kind = :entry, entry = entry, style_sym = style_sym))
            end
        end
        # blank separator between sections
        si < length(sections) && push!(lines, (kind = :blank,))
    end
    return lines
end

"""Render dry-run output panel."""
function render_dry_run_panel(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.updates_state
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), area)

    inner = render(
        Block(
            title = "Dry Run — Manifest Diff",
            border_style = tstyle(:accent),
            box = BOX_DOUBLE,
        ),
        rows[1],
        buf,
    )

    diff = st.dry_run_output
    if diff !== nothing
        if diff.error !== nothing
            set_string!(buf, inner.x + 1, inner.y, "Error: $(diff.error)", tstyle(:error))
        elseif isempty(diff.entries)
            set_string!(buf, inner.x + 1, inner.y, "No changes — environment is up to date.", tstyle(:success))
        else
            vlines = _build_dry_run_lines(st)
            visible = inner.height
            total = length(vlines)

            # Clamp scroll so selected line is visible
            st.dry_run_selected = clamp(st.dry_run_selected, 1, total)
            if st.dry_run_selected > st.dry_run_scroll + visible
                st.dry_run_scroll = st.dry_run_selected - visible
            elseif st.dry_run_selected <= st.dry_run_scroll
                st.dry_run_scroll = max(0, st.dry_run_selected - 1)
            end
            st.dry_run_scroll = clamp(st.dry_run_scroll, 0, max(0, total - visible))

            # Column positions
            name_col = inner.x + 4
            old_col = inner.x + 30
            arrow_col = inner.x + 42
            new_col = inner.x + 46

            for vi in 1:visible
                idx = vi + st.dry_run_scroll
                idx > total && break
                y = inner.y + vi - 1
                vl = vlines[idx]
                is_sel = (idx == st.dry_run_selected)

                if vl.kind == :header
                    chevron = vl.expanded ? "▼" : "▶"
                    sel_marker = is_sel ? "▸ " : "  "
                    header_text = "$(sel_marker)$(chevron) $(vl.icon) $(vl.count) package$(vl.count == 1 ? "" : "s") $(vl.label)"
                    style = is_sel ? tstyle(vl.style_sym, bold = true) : tstyle(vl.style_sym)
                    set_string!(buf, inner.x + 1, y, header_text, style)

                elseif vl.kind == :entry
                    entry = vl.entry
                    icon, _ = _section_meta(entry.kind)
                    entry_style = tstyle(vl.style_sym)

                    set_string!(buf, inner.x + 3, y, icon, entry_style)
                    set_string!(buf, name_col, y, entry.name, entry_style)

                    if entry.old_version !== nothing
                        set_string!(buf, old_col, y, entry.old_version, tstyle(:text_dim))
                    elseif entry.kind == :added
                        set_string!(buf, old_col, y, "—", tstyle(:text_dim))
                    end

                    if entry.kind in (:upgraded, :downgraded)
                        set_string!(buf, arrow_col, y, "→", tstyle(:text_dim))
                    end

                    if entry.new_version !== nothing
                        nstyle = entry.kind == :downgraded ? tstyle(:warning, bold = true) : tstyle(:success, bold = true)
                        set_string!(buf, new_col, y, entry.new_version, nstyle)
                    elseif entry.kind == :removed
                        set_string!(buf, new_col, y, "—", tstyle(:text_dim))
                    end
                end
                # :blank lines are just empty — skip rendering
            end

            # Scroll indicator
            if total > visible
                pct = round(Int, (st.dry_run_scroll + visible) / total * 100)
                scroll_text = "↑↓ $(min(pct, 100))%"
                set_string!(buf, inner.x + inner.width - length(scroll_text) - 1, inner.y + inner.height - 1, scroll_text, tstyle(:text_dim))
            end
        end
    end

    # Summary footer
    summary_parts = String[]
    if diff !== nothing && diff.error === nothing && !isempty(diff.entries)
        n_up = count(e -> e.kind == :upgraded, diff.entries)
        n_down = count(e -> e.kind == :downgraded, diff.entries)
        n_add = count(e -> e.kind == :added, diff.entries)
        n_rm = count(e -> e.kind == :removed, diff.entries)
        n_up > 0 && push!(summary_parts, "⬆ $n_up upgraded")
        n_down > 0 && push!(summary_parts, "⬇ $n_down downgraded")
        n_add > 0 && push!(summary_parts, "+ $n_add added")
        n_rm > 0 && push!(summary_parts, "− $n_rm removed")
    end
    summary_text = isempty(summary_parts) ? "" : "  " * join(summary_parts, "  ")

    render(
        StatusBar(
            left = [
                Span("  [Esc] Close  [Enter] Expand/Collapse", tstyle(:text_dim)),
                Span(summary_text, tstyle(:text)),
            ],
            right = [],
        ),
        rows[2],
        buf,
    )
end

# ──────────────────────────────────────────────────────────────────────────────
# Updates tab key handling
# ──────────────────────────────────────────────────────────────────────────────

"""
    handle_updates_keys!(m::PkgTUIApp, evt::KeyEvent) → Bool
"""
function handle_updates_keys!(m::PkgTUIApp, evt::KeyEvent)::Bool
    st = m.updates_state

    # Dry-run mode: Esc exits, Enter/Space toggles sections, arrows navigate
    if st.show_dry_run
        vlines = _build_dry_run_lines(st)
        total = length(vlines)
        if evt.key == :escape
            st.show_dry_run = false
            return true
        elseif evt.key == :up
            st.dry_run_selected = max(1, st.dry_run_selected - 1)
            return true
        elseif evt.key == :down
            st.dry_run_selected = min(total, st.dry_run_selected + 1)
            return true
        elseif evt.key == :pageup
            st.dry_run_selected = max(1, st.dry_run_selected - 10)
            return true
        elseif evt.key == :pagedown
            st.dry_run_selected = min(total, st.dry_run_selected + 10)
            return true
        elseif evt.key == :home
            st.dry_run_selected = 1
            return true
        elseif evt.key == :end_key || (evt.key == :char && evt.char == 'G')
            st.dry_run_selected = total
            return true
        elseif evt.key == :enter || (evt.key == :char && evt.char == ' ')
            if st.dry_run_selected >= 1 && st.dry_run_selected <= total
                vl = vlines[st.dry_run_selected]
                if vl.kind == :header
                    st.dry_run_sections[vl.section] = !get(st.dry_run_sections, vl.section, true)
                end
            end
            return true
        end
        return false
    end

    # Delegate to conflicts panel when focused there
    if st.conflicts_focused && !isempty(m.conflicts.conflicts)
        if evt.key == :char && evt.char == 'c'
            st.conflicts_focused = false
            return true
        end
        return handle_conflicts_keys!(m, evt)
    end

    if evt.key == :char
        c = evt.char
        if c == 'c'
            if !isempty(m.conflicts.conflicts)
                st.conflicts_focused = true
            else
                push_toast!(m, "No conflicts found", style = :text_dim, icon = "ℹ")
            end
            return true
        elseif c == 'u' && !isempty(st.updates)
            idx = st.selected
            if idx >= 1 && idx <= length(st.updates)
                name = st.updates[idx].name
                # Check if the package is pinned
                pinned_pkg =
                    findfirst(p -> p.name == name && p.is_pinned, m.installed.packages)
                if pinned_pkg !== nothing
                    push_toast!(
                        m,
                        "'$name' is pinned — free it first with [f]";
                        style = :warning,
                        icon = "⚠",
                        hint = "[f] free",
                    )
                else
                    push_log!(m, "Updating $name...")
                    push!(st.updating_names, name)
                    spawn_task!(m.tq, :update_single) do
                        io = IOBuffer()
                        result = update_package(name, io)
                        (result = result, log = String(take!(io)), name = name)
                    end
                end
            end
            return true
        elseif c == 'U'
            push_log!(m, "Updating all packages...")
            st.update_all_running = true
            spawn_task!(m.tq, :update_all) do
                io = IOBuffer()
                result = update_all(io)
                (result = result, log = String(take!(io)))
            end
            return true
        elseif c == 'd'
            push_log!(m, "Running dry-run update check...")
            spawn_task!(m.tq, :dry_run) do
                io = IOBuffer()
                dry_run_update(io)
            end
            return true
        elseif c == 'R'
            refresh_updates!(m)
            return true
        end
    elseif evt.key == :up
        st.selected = max(1, st.selected - 1)
        return true
    elseif evt.key == :down
        st.selected = min(length(st.updates), st.selected + 1)
        return true
    elseif evt.key == :pageup
        st.selected = max(1, st.selected - 10)
        return true
    elseif evt.key == :pagedown
        st.selected = min(length(st.updates), st.selected + 10)
        return true
    end

    return false
end

"""Trigger an async refresh of update information."""
function refresh_updates!(m::PkgTUIApp)
    m.updates_state.loading = true
    push_log!(m, "Checking for updates...")
    spawn_task!(m.tq, :fetch_outdated) do
        io = IOBuffer()
        fetch_outdated(io)
    end
end
