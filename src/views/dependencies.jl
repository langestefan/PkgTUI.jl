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

"""Render the graph visualization of dependencies."""
function render_dep_graph(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.deps

    # Legend + status
    settled = st.graph_iterations >= 200
    status_str = settled ? "settled" : "layouting ($(st.graph_iterations)/200)"
    inner = render(
        Block(
            title = "Dependency Graph ($(length(st.graph_nodes)) nodes, $(length(st.graph_edges)) edges) [$status_str]",
            border_style = tstyle(:border),
        ),
        area,
        buf,
    )

    if isempty(st.graph_nodes)
        set_string!(
            buf,
            inner.x + 2,
            inner.y + 1,
            "No dependencies to graph.",
            tstyle(:text_dim),
        )
        return
    end

    # Run a layout iteration each frame for animation
    if !settled
        step_force_layout!(
            st.graph_nodes,
            st.graph_edges;
            width = Float64(inner.width),
            height = Float64(inner.height),
        )
        st.graph_iterations += 1
    end

    uuid_pos = Dict(n.uuid => (n.x, n.y) for n in st.graph_nodes)

    # Draw edges using Bresenham line algorithm
    for edge in st.graph_edges
        p1 = get(uuid_pos, edge.from, nothing)
        p2 = get(uuid_pos, edge.to, nothing)
        (p1 === nothing || p2 === nothing) && continue

        x1, y1 = round(Int, p1[1]) + inner.x, round(Int, p1[2]) + inner.y
        x2, y2 = round(Int, p2[1]) + inner.x, round(Int, p2[2]) + inner.y

        draw_line!(buf, x1, y1, x2, y2, inner, tstyle(:text_dim))
    end

    # Draw nodes on top (sorted: selected last so it renders on top)
    sorted_nodes = sort(st.graph_nodes; by = n -> n.uuid == st.selected_node ? 1 : 0)
    for node in sorted_nodes
        nx = round(Int, node.x) + inner.x
        ny = round(Int, node.y) + inner.y
        nx = clamp(nx, inner.x, inner.x + inner.width - 1)
        ny = clamp(ny, inner.y, inner.y + inner.height - 1)

        is_selected = node.uuid == st.selected_node
        style = if is_selected
            tstyle(:accent, bold = true)
        elseif node.is_direct
            tstyle(:primary, bold = true)
        else
            tstyle(:text_dim)
        end

        # Node marker
        marker = is_selected ? '◉' : (node.is_direct ? '●' : '○')
        set_char!(buf, nx, ny, marker, style)

        # Draw label next to node
        label = node.name
        label_x = nx + 2
        max_label = inner.x + inner.width - label_x
        if max_label > 3
            display_label = length(label) > max_label ? label[1:max_label] : label
            set_string!(buf, label_x, ny, display_label, style)
        end
    end

    # Legend at bottom-right
    ly = inner.y + inner.height - 2
    lx = inner.x + inner.width - 22
    if lx > inner.x && ly > inner.y
        set_string!(buf, lx, ly, "● direct  ○ indirect", tstyle(:text_dim))
    end
end

"""Draw a line between two points using Bresenham's algorithm."""
function draw_line!(buf::Buffer, x1::Int, y1::Int, x2::Int, y2::Int, bounds::Rect, style)
    dx = abs(x2 - x1)
    dy = -abs(y2 - y1)
    sx = x1 < x2 ? 1 : -1
    sy = y1 < y2 ? 1 : -1
    err = dx + dy
    x, y = x1, y1

    max_steps = dx - dy + 2  # prevent infinite loop
    for _ = 1:max_steps
        # Pick line char based on direction
        cx = clamp(x, bounds.x, bounds.x + bounds.width - 1)
        cy = clamp(y, bounds.y, bounds.y + bounds.height - 1)
        if cx == x && cy == y  # only draw if within bounds
            char = if dx > -dy * 2
                '─'
            elseif -dy > dx * 2
                '│'
            else
                (sx > 0) == (sy > 0) ? '╲' : '╱'
            end
            set_char!(buf, x, y, char, style)
        end

        (x == x2 && y == y2) && break
        e2 = 2 * err
        if e2 >= dy
            err += dy
            x += sx
        end
        if e2 <= dx
            err += dx
            y += sy
        end
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
            if st.show_graph && isempty(st.graph_nodes) && !isempty(m.installed.packages)
                nodes, edges = build_graph_layout(m.installed.packages)
                st.graph_nodes = nodes
                st.graph_edges = edges
                st.graph_iterations = 0
            end
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
    if st.show_graph && !isempty(st.graph_nodes)
        if evt.key == :up || evt.key == :down
            current_idx = findfirst(n -> n.uuid == st.selected_node, st.graph_nodes)
            if current_idx === nothing
                st.selected_node = st.graph_nodes[1].uuid
            else
                delta = evt.key == :up ? -1 : 1
                new_idx = clamp(current_idx + delta, 1, length(st.graph_nodes))
                st.selected_node = st.graph_nodes[new_idx].uuid
            end
            return true
        end
    end

    return false
end

"""Get the name of the currently selected dependency."""
function get_selected_dep_name(st::DependenciesState, m::PkgTUIApp)::Union{String,Nothing}
    if st.show_graph && st.selected_node !== nothing
        idx = findfirst(n -> n.uuid == st.selected_node, st.graph_nodes)
        return idx !== nothing ? st.graph_nodes[idx].name : nothing
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
