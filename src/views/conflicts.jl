"""
    Dependency conflict resolver view.
"""

"""
    render_conflicts_panel(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the conflicts panel showing packages held back by compatibility constraints.
This is rendered as a sub-panel within the Updates or Dependencies tab.
"""
function render_conflicts_panel(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.conflicts

    inner = render(Block(
        title="Dependency Conflicts ($(length(st.conflicts)))",
        border_style=tstyle(:warning),
    ), area, buf)

    if st.loading
        set_string!(buf, inner.x + 2, inner.y + 1,
            "Analyzing conflicts...", tstyle(:text_dim, italic=true))
        return
    end

    if isempty(st.conflicts)
        set_string!(buf, inner.x + 2, inner.y + 1,
            "No dependency conflicts detected.", tstyle(:success))
        return
    end

    # Header
    y = inner.y
    hx = inner.x + 1
    style = tstyle(:title, bold=true)
    set_string!(buf, hx, y, "Package", style)
    set_string!(buf, hx + 20, y, "Held At", style)
    set_string!(buf, hx + 32, y, "Latest", style)
    set_string!(buf, hx + 44, y, "Blocked By", style)
    y += 1
    for x in inner.x:(inner.x + inner.width - 1)
        set_char!(buf, x, y, '─', tstyle(:border))
    end
    y += 1

    # Rows
    for (i, conflict) in enumerate(st.conflicts)
        y > inner.y + inner.height - 1 && break
        is_selected = (i == st.selected)

        name_style = is_selected ? tstyle(:accent, bold=true) : tstyle(:warning)
        set_string!(buf, hx, y, conflict.package, name_style)
        set_string!(buf, hx + 20, y, "v" * conflict.held_at,
            is_selected ? tstyle(:accent) : tstyle(:text))
        set_string!(buf, hx + 32, y, "v" * conflict.latest,
            is_selected ? tstyle(:accent) : tstyle(:success))
        set_string!(buf, hx + 44, y, conflict.blocked_by,
            is_selected ? tstyle(:accent) : tstyle(:error))

        if is_selected
            set_string!(buf, hx - 1, y, "▶", tstyle(:accent))
        end
        y += 1
    end
end

"""
    extract_conflicts(updates::Vector{UpdateInfo}) → Vector{ConflictInfo}

Extract conflict information from the updates list. Packages marked with ⌅
(cannot update) are conflicts.
"""
function extract_conflicts(updates::Vector{UpdateInfo})::Vector{ConflictInfo}
    conflicts = ConflictInfo[]
    for u in updates
        u.can_update && continue  # ⌃ packages can be updated, skip them
        latest = something(u.latest_available, u.latest_compatible, "unknown")
        push!(conflicts, ConflictInfo(
            package=u.name,
            held_at=u.current_version,
            latest=latest,
            blocked_by=something(u.blocker, "unknown"),
        ))
    end
    return conflicts
end

"""
    handle_conflicts_keys!(m::PkgTUIApp, evt::KeyEvent) → Bool
"""
function handle_conflicts_keys!(m::PkgTUIApp, evt::KeyEvent)::Bool
    st = m.conflicts
    isempty(st.conflicts) && return false

    if evt.key == :up
        st.selected = max(1, st.selected - 1)
        return true
    elseif evt.key == :down
        st.selected = min(length(st.conflicts), st.selected + 1)
        return true
    elseif evt.key == :enter
        # Show why for the blocking package
        if st.selected >= 1 && st.selected <= length(st.conflicts)
            conflict = st.conflicts[st.selected]
            push_log!(m, "Running Pkg.why(\"$(conflict.blocked_by)\")...")
            spawn_task!(m.tq, :why) do
                io = IOBuffer()
                why_package(conflict.blocked_by, io)
            end
        end
        return true
    end

    return false
end
