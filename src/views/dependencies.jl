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
        why_inner = render(Block(title="Pkg.why()", border_style=tstyle(:border)),
            rows[2], buf)
        lines = split(st.why_output, '\n')
        for (i, line) in enumerate(lines)
            y = why_inner.y + i - 1
            y > why_inner.y + why_inner.height - 1 && break
            set_string!(buf, why_inner.x + 1, y, line, tstyle(:text))
        end
    end

    # ── Hints ──
    render(StatusBar(
        left=[
            Span("  [g]raph/tree ", tstyle(:accent)),
            Span("[w]hy ", tstyle(:accent)),
            Span("[Enter] expand ", tstyle(:text_dim)),
        ],
        right=[
            Span(st.show_graph ? "Graph View " : "Tree View ", tstyle(:text_dim)),
        ],
    ), rows[end], buf)
end

"""Render the tree view of dependencies."""
function render_dep_tree(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.deps

    inner = render(Block(
        title=st.loading ? "Loading..." : "Dependency Tree",
        border_style=tstyle(:border)
    ), area, buf)

    if st.loading
        set_string!(buf, inner.x + 2, inner.y + 1,
            "Building dependency tree...", tstyle(:text_dim, italic=true))
    elseif st.tree_view !== nothing
        render(st.tree_view, inner, buf)
    else
        set_string!(buf, inner.x + 2, inner.y + 1,
            "No dependencies found.", tstyle(:text_dim))
    end
end

"""Render the graph visualization of dependencies."""
function render_dep_graph(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.deps

    inner = render(Block(
        title="Dependency Graph ($(length(st.graph_nodes)) nodes, $(length(st.graph_edges)) edges)",
        border_style=tstyle(:border)
    ), area, buf)

    if isempty(st.graph_nodes)
        set_string!(buf, inner.x + 2, inner.y + 1,
            "No dependencies to graph.", tstyle(:text_dim))
        return
    end

    # Run a layout iteration each frame for animation
    if st.graph_iterations < 200
        step_force_layout!(st.graph_nodes, st.graph_edges;
            width=Float64(inner.width), height=Float64(inner.height))
        st.graph_iterations += 1
    end

    uuid_pos = Dict(n.uuid => (n.x, n.y) for n in st.graph_nodes)

    # Draw edges using braille-style line characters
    for edge in st.graph_edges
        p1 = get(uuid_pos, edge.from, nothing)
        p2 = get(uuid_pos, edge.to, nothing)
        (p1 === nothing || p2 === nothing) && continue

        # Simple line drawing between nodes
        x1, y1 = round(Int, p1[1]) + inner.x, round(Int, p1[2]) + inner.y
        x2, y2 = round(Int, p2[1]) + inner.x, round(Int, p2[2]) + inner.y

        # Clamp to inner area
        x1 = clamp(x1, inner.x, inner.x + inner.width - 1)
        y1 = clamp(y1, inner.y, inner.y + inner.height - 1)
        x2 = clamp(x2, inner.x, inner.x + inner.width - 1)
        y2 = clamp(y2, inner.y, inner.y + inner.height - 1)

        # Draw simple line using midpoint
        mx, my = div(x1 + x2, 2), div(y1 + y2, 2)
        mx = clamp(mx, inner.x, inner.x + inner.width - 1)
        my = clamp(my, inner.y, inner.y + inner.height - 1)

        if abs(x2 - x1) > abs(y2 - y1)
            # Horizontal-ish: draw ─
            for x in min(x1, x2):max(x1, x2)
                x = clamp(x, inner.x, inner.x + inner.width - 1)
                set_char!(buf, x, my, '·', tstyle(:text_dim))
            end
        else
            # Vertical-ish: draw │
            for y in min(y1, y2):max(y1, y2)
                y = clamp(y, inner.y, inner.y + inner.height - 1)
                set_char!(buf, mx, y, '·', tstyle(:text_dim))
            end
        end
    end

    # Draw nodes on top
    for node in st.graph_nodes
        nx = round(Int, node.x) + inner.x
        ny = round(Int, node.y) + inner.y
        nx = clamp(nx, inner.x, inner.x + inner.width - 1)
        ny = clamp(ny, inner.y, inner.y + inner.height - 1)

        is_selected = node.uuid == st.selected_node
        style = if is_selected
            tstyle(:accent, bold=true)
        elseif node.is_direct
            tstyle(:primary, bold=true)
        else
            tstyle(:text_dim)
        end

        # Draw node label (truncated to fit)
        label = node.name
        max_label = inner.x + inner.width - nx - 1
        if max_label > 0
            display_label = length(label) > max_label ? label[1:max_label] : label
            set_string!(buf, nx, ny, display_label, style)
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
function get_selected_dep_name(st::DependenciesState, m::PkgTUIApp)::Union{String, Nothing}
    if st.show_graph && st.selected_node !== nothing
        node = findfirst(n -> n.uuid == st.selected_node, st.graph_nodes)
        return node !== nothing ? st.graph_nodes[node].name : nothing
    end
    # For tree mode, we'd need to parse the TreeView's selected label
    # For now return the first direct dep as fallback
    if !isempty(m.installed.packages)
        direct = filter(p -> p.is_direct_dep, m.installed.packages)
        return isempty(direct) ? nothing : first(direct).name
    end
    return nothing
end
