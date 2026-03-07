"""
    Dependencies tab view — two-panel dependency explorer.
"""

"""
    render_dependencies_tab(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the "Dependencies" tab with two-panel explorer (package list + detail).
"""
function render_dependencies_tab(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.deps

    # Layout: content | why output | hints
    has_why = st.why_output !== nothing
    constraints = if has_why
        [Fill(), Fixed(6), Fixed(1)]
    else
        [Fill(), Fixed(1)]
    end
    rows = split_layout(Layout(Vertical, constraints), area)

    # ── Main content ──
    render_dep_graph(m, rows[1], buf)

    # ── Why output panel ──
    if has_why
        why_inner =
            render(Block(title = "Pkg.why()", border_style = tstyle(:border)), rows[2], buf)
        lines = split(st.why_output, '\n')
        for (i, line) in enumerate(lines)
            y = why_inner.y + i - 1
            y > why_inner.y + why_inner.height - 1 && break
            set_string!(buf, why_inner.x + 1, y, line, tstyle(:text))
        end
    end

    # ── Hints ──
    render(
        StatusBar(
            left = [
                Span("  [w]hy ", tstyle(:accent)),
                Span("[↑↓] navigate ", tstyle(:text_dim)),
            ],
            right = [Span("Explorer ", tstyle(:text_dim))],
        ),
        rows[end],
        buf,
    )
end



"""Render a two-panel dependency explorer: package list + detail view."""
function render_dep_graph(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.deps
    pkgs = m.installed.packages

    # Split into left (package list) and right (detail) panels
    cols = split_layout(Layout(Horizontal, [Ratio(1, 3), Ratio(2, 3)]), area)

    # ── Left panel: package list ──
    left_inner = render(
        Block(title = "Packages ($(length(pkgs)))", border_style = tstyle(:border)),
        cols[1],
        buf,
    )

    if isempty(pkgs)
        set_string!(buf, left_inner.x + 1, left_inner.y, "No packages.", tstyle(:text_dim))
    else
        # Clamp selection
        st.graph_selected = clamp(st.graph_selected, 1, length(pkgs))
        visible_h = left_inner.height

        # Auto-scroll
        if st.graph_selected - 1 < st.graph_scroll
            st.graph_scroll = st.graph_selected - 1
        elseif st.graph_selected > st.graph_scroll + visible_h
            st.graph_scroll = st.graph_selected - visible_h
        end

        for i = 1:visible_h
            idx = st.graph_scroll + i
            idx > length(pkgs) && break
            pkg = pkgs[idx]
            y = left_inner.y + i - 1

            is_sel = idx == st.graph_selected
            marker = pkg.is_direct_dep ? "● " : "○ "
            label = marker * pkg.name

            style = if is_sel
                tstyle(:accent, bold = true)
            elseif pkg.is_direct_dep
                tstyle(:primary)
            else
                tstyle(:text_dim)
            end

            # Highlight bar for selected
            if is_sel
                for cx = left_inner.x:(left_inner.x+left_inner.width-1)
                    set_char!(buf, cx, y, ' ', tstyle(:accent))
                end
            end

            set_string!(
                buf,
                left_inner.x + 1,
                y,
                label,
                style;
                max_x = left_inner.x + left_inner.width - 1,
            )
        end

        # Scroll indicators
        if st.graph_scroll > 0
            set_char!(buf, right(cols[1]) - 1, left_inner.y, '▲', tstyle(:text_dim))
        end
        if st.graph_scroll + visible_h < length(pkgs)
            set_char!(buf, right(cols[1]) - 1, bottom(left_inner), '▼', tstyle(:text_dim))
        end
    end

    # ── Right panel: dependency detail for selected package ──
    if !isempty(pkgs) && 1 <= st.graph_selected <= length(pkgs)
        sel_pkg = pkgs[st.graph_selected]

        right_inner = render(
            Block(
                title = "$(sel_pkg.name)" *
                        (sel_pkg.version !== nothing ? " v$(sel_pkg.version)" : ""),
                border_style = tstyle(:border),
            ),
            cols[2],
            buf,
        )

        # Build UUID → PackageRow lookup
        uuid_map = Dict(p.uuid => p for p in pkgs)

        # ── Depends on ──
        deps_list = [get(uuid_map, dep_uuid, nothing) for dep_uuid in sel_pkg.dependencies]
        deps_list = filter(!isnothing, deps_list)
        sort!(deps_list; by = p -> p.name)

        # ── Used by (reverse dependencies) ──
        used_by = [p for p in pkgs if sel_pkg.uuid in p.dependencies]
        sort!(used_by; by = p -> p.name)

        row = 0  # relative row counter

        # "Depends on" header
        set_string!(
            buf,
            right_inner.x + 1,
            right_inner.y + row,
            "Depends on ($(length(deps_list))):",
            tstyle(:accent, bold = true),
        )
        row += 1

        if isempty(deps_list)
            set_string!(
                buf,
                right_inner.x + 3,
                right_inner.y + row,
                "(none)",
                tstyle(:text_dim),
            )
            row += 1
        else
            for (i, dep) in enumerate(deps_list)
                right_inner.y + row > bottom(right_inner) && break
                connector = i == length(deps_list) ? "└── " : "├── "
                marker = dep.is_direct_dep ? "● " : "○ "
                ver = dep.version !== nothing ? " v$(dep.version)" : ""
                line = connector * marker * dep.name * ver
                style = dep.is_direct_dep ? tstyle(:primary) : tstyle(:text_dim)
                set_string!(
                    buf,
                    right_inner.x + 3,
                    right_inner.y + row,
                    line,
                    style;
                    max_x = right_inner.x + right_inner.width - 1,
                )
                row += 1
            end
        end

        row += 1  # blank line separator

        # "Used by" header
        if right_inner.y + row <= bottom(right_inner)
            set_string!(
                buf,
                right_inner.x + 1,
                right_inner.y + row,
                "Used by ($(length(used_by))):",
                tstyle(:accent, bold = true),
            )
            row += 1

            if isempty(used_by)
                if right_inner.y + row <= bottom(right_inner)
                    set_string!(
                        buf,
                        right_inner.x + 3,
                        right_inner.y + row,
                        "(none)",
                        tstyle(:text_dim),
                    )
                end
            else
                for (i, dep) in enumerate(used_by)
                    right_inner.y + row > bottom(right_inner) && break
                    connector = i == length(used_by) ? "└── " : "├── "
                    marker = dep.is_direct_dep ? "● " : "○ "
                    ver = dep.version !== nothing ? " v$(dep.version)" : ""
                    line = connector * marker * dep.name * ver
                    style = dep.is_direct_dep ? tstyle(:primary) : tstyle(:text_dim)
                    set_string!(
                        buf,
                        right_inner.x + 3,
                        right_inner.y + row,
                        line,
                        style;
                        max_x = right_inner.x + right_inner.width - 1,
                    )
                    row += 1
                end
            end
        end
    else
        render(Block(title = "Details", border_style = tstyle(:border)), cols[2], buf)
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Dependencies tab key handling
# ──────────────────────────────────────────────────────────────────────────────

"""
    handle_dependencies_keys!(m::PkgTUIApp, evt::KeyEvent) → Bool
"""
function handle_dependencies_keys!(m::PkgTUIApp, evt::KeyEvent)::Bool
    st = m.deps

    if evt.key == :char
        c = evt.char
        if c == 'w'
            # Find selected package name for Pkg.why
            pkg_name = get_selected_dep_name(st, m)
            if pkg_name !== nothing
                push_log!(m, "Running Pkg.why(\"$pkg_name\")...")
                spawn_task!(m.tq, :why) do
                    io = IOBuffer()
                    why_package(pkg_name, io)
                end
            end
            return true
        end
    end

    # Navigation
    if !isempty(m.installed.packages)
        if evt.key == :up || evt.key == :down
            delta = evt.key == :up ? -1 : 1
            st.graph_selected =
                clamp(st.graph_selected + delta, 1, length(m.installed.packages))
            return true
        end
    end

    return false
end

"""Get the name of the currently selected dependency."""
function get_selected_dep_name(st::DependenciesState, m::PkgTUIApp)::Union{String,Nothing}
    if !isempty(m.installed.packages)
        idx = clamp(st.graph_selected, 1, length(m.installed.packages))
        return m.installed.packages[idx].name
    end
    return nothing
end
