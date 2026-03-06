"""
    Dependencies tab view — tree and graph visualization.
"""

"""
    render_dependencies_tab(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the "Dependencies" tab with tree or graph view.
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
    if st.show_graph
        render_dep_graph(m, rows[1], buf)
    else
        render_dep_tree(m, rows[1], buf)
    end

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
                Span("  [g]raph/tree ", tstyle(:accent)),
                Span("[w]hy ", tstyle(:accent)),
                Span("[Enter] expand ", tstyle(:text_dim)),
            ],
            right = [Span(st.show_graph ? "Graph View " : "Tree View ", tstyle(:text_dim))],
        ),
        rows[end],
        buf,
    )
end

"""Render the tree view of dependencies (linux `tree`-style connectors)."""
function render_dep_tree(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.deps

    inner = render(
        Block(
            title = st.loading ? "Loading..." : "Dependency Tree",
            border_style = tstyle(:border),
        ),
        area,
        buf,
    )

    if st.loading
        set_string!(
            buf,
            inner.x + 2,
            inner.y + 1,
            "Building dependency tree...",
            tstyle(:text_dim, italic = true),
        )
    elseif st.tree_view !== nothing
        _render_tree_linux_style(st.tree_view, inner, buf)
    else
        set_string!(
            buf,
            inner.x + 2,
            inner.y + 1,
            "No dependencies found.",
            tstyle(:text_dim),
        )
    end
end

"""
    _render_tree_linux_style(tv, area, buf)

Custom tree renderer that mimics the Linux `tree` command output:
```
.
├── Dates v1.11.0
│   ├── Printf v1.11.0
│   └── Unicode v1.11.0
└── JuMP v1.29.4
    ├── LinearAlgebra v1.12.0
    └── MathOptInterface v1.49.0
```
Uses 4-char wide columns: `├── `, `└── `, `│   `, `    `.
"""
function _render_tree_linux_style(tv::TreeView, area::Rect, buf::Buffer)
    (area.width < 1 || area.height < 1) && return
    tv.last_area = area

    flat = Tachikoma.flatten_tree(tv.root, tv.show_root)
    n = length(flat)
    visible_h = area.height

    # Auto-scroll to keep selection visible
    if tv.selected >= 1
        if tv.selected - 1 < tv.offset
            tv.offset = tv.selected - 1
        elseif tv.selected > tv.offset + visible_h
            tv.offset = tv.selected - visible_h
        end
    end

    max_cx = right(area)
    conn_style = tv.connector_style
    # When show_root=true, parent_lasts[1] is the root's is_last (always true),
    # so we offset by 1 to skip it and align columns with actual ancestors.
    pl_offset = tv.show_root ? 1 : 0

    for i = 1:visible_h
        idx = tv.offset + i
        idx > n && break
        row = flat[idx]
        y = area.y + i - 1
        cx = area.x

        if row.depth > 0
            # Ancestor continuation lines: "│   " or "    " (4 chars each)
            for d = 1:(row.depth-1)
                pidx = d + pl_offset
                if pidx <= length(row.parent_lasts) && !row.parent_lasts[pidx]
                    # Continuing ancestor — draw vertical bar
                    cx <= max_cx && set_char!(buf, cx, y, '│', conn_style)
                end
                cx += 4
            end

            # Branch connector: "├── " or "└── " (4 chars)
            if row.is_last
                cx <= max_cx && set_char!(buf, cx, y, '└', conn_style)
                cx + 1 <= max_cx && set_char!(buf, cx + 1, y, '─', conn_style)
                cx + 2 <= max_cx && set_char!(buf, cx + 2, y, '─', conn_style)
            else
                cx <= max_cx && set_char!(buf, cx, y, '├', conn_style)
                cx + 1 <= max_cx && set_char!(buf, cx + 1, y, '─', conn_style)
                cx + 2 <= max_cx && set_char!(buf, cx + 2, y, '─', conn_style)
            end
            cx += 4  # connector (1) + dashes (2) + space (1) = 4
        end

        # Label (no expand indicator — matches `tree` style)
        cx > max_cx && continue
        style = (tv.selected == idx) ? tv.selected_style : row.style
        set_string!(buf, cx, y, row.label, style; max_x = max_cx)
    end

    # Scroll indicators
    if tv.offset > 0
        set_char!(buf, right(area), area.y, '▲', tstyle(:text_dim))
    end
    if tv.offset + visible_h < n
        set_char!(buf, right(area), bottom(area), '▼', tstyle(:text_dim))
    end
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
        if c == 'g'
            st.show_graph = !st.show_graph
            return true
        elseif c == 'w'
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

    # Delegate to TreeView if in tree mode
    if !st.show_graph && st.tree_view !== nothing
        if handle_key!(st.tree_view, evt)
            return true
        end
    end

    # Graph mode navigation
    if st.show_graph && !isempty(m.installed.packages)
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
    if st.show_graph && !isempty(m.installed.packages)
        idx = clamp(st.graph_selected, 1, length(m.installed.packages))
        return m.installed.packages[idx].name
    end
    # Tree mode: get selected label from TreeView's flattened rows
    if st.tree_view !== nothing && st.tree_view.selected >= 1
        flat = Tachikoma.flatten_tree(st.tree_view.root, st.tree_view.show_root)
        if st.tree_view.selected <= length(flat)
            label = flat[st.tree_view.selected].label
            # Labels look like "PackageName vX.Y.Z" — extract the name part
            parts = split(label)
            return isempty(parts) ? nothing : String(first(parts))
        end
    end
    return nothing
end
