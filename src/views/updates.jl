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
        y = inner.y
        max_y = inner.y + inner.height - 1

        if diff.error !== nothing
            set_string!(buf, inner.x + 1, y, "Error: $(diff.error)", tstyle(:error))
        elseif isempty(diff.entries)
            set_string!(buf, inner.x + 1, y, "No changes — environment is up to date.", tstyle(:success))
        else
            # Header
            name_col = inner.x + 1
            change_col = inner.x + 3
            old_col = inner.x + 28
            arrow_col = inner.x + 42
            new_col = inner.x + 46

            set_string!(buf, change_col, y, "Package", tstyle(:title, bold = true))
            set_string!(buf, old_col, y, "Current", tstyle(:title, bold = true))
            set_string!(buf, new_col, y, "After Update", tstyle(:title, bold = true))
            y += 1
            if y <= max_y
                for x = inner.x:(inner.x+inner.width-1)
                    set_char!(buf, x, y, '─', tstyle(:border))
                end
                y += 1
            end

            for entry in diff.entries
                y > max_y && break
                icon, style = if entry.kind == :upgraded
                    "⬆", tstyle(:success)
                elseif entry.kind == :downgraded
                    "⬇", tstyle(:warning)
                elseif entry.kind == :added
                    "+", tstyle(:success, bold = true)
                elseif entry.kind == :removed
                    "−", tstyle(:error)
                else
                    " ", tstyle(:text_dim)
                end

                set_string!(buf, name_col, y, icon, style)
                set_string!(buf, change_col, y, entry.name, style)

                if entry.old_version !== nothing
                    set_string!(buf, old_col, y, entry.old_version, tstyle(:text_dim))
                elseif entry.kind == :added
                    set_string!(buf, old_col, y, "—", tstyle(:text_dim))
                end

                if entry.kind in (:upgraded, :downgraded)
                    set_string!(buf, arrow_col, y, "→", tstyle(:text_dim))
                end

                if entry.new_version !== nothing
                    new_style = entry.kind == :downgraded ? tstyle(:warning, bold = true) : tstyle(:success, bold = true)
                    set_string!(buf, new_col, y, entry.new_version, new_style)
                elseif entry.kind == :removed
                    set_string!(buf, new_col, y, "—", tstyle(:text_dim))
                end

                y += 1
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
                Span("  [Esc] Close", tstyle(:text_dim)),
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

    # Dry-run mode: only Esc exits
    if st.show_dry_run
        if evt.key == :escape
            st.show_dry_run = false
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
