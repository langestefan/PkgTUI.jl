"""
    Registry Explorer tab view.
"""

"""
    render_registry_tab(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the "Registry" tab with search and package details.
"""
function render_registry_tab(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.registry

    # Horizontal split: results list | detail panel
    cols = split_layout(Layout(Horizontal, [Percent(55), Fill()]), area)

    # ── Left panel: search + results ──
    left_rows = split_layout(Layout(Vertical, [Fixed(3), Fill(), Fixed(1)]), cols[1])

    # Search bar
    search_inner = render(Block(title="Search Registry", border_style=tstyle(:border)),
        left_rows[1], buf)
    render(st.search_input, search_inner, buf)

    # Results list
    results_inner = render(Block(
        title=st.loading ? "Searching..." : "Results ($(length(st.results)))",
        border_style=tstyle(:border)
    ), left_rows[2], buf)

    if !st.index_loaded
        set_string!(buf, results_inner.x + 2, results_inner.y + 1,
            "Loading registry index...", tstyle(:text_dim, italic=true))
    elseif isempty(st.results)
        query = text(st.search_input)
        msg = isempty(strip(query)) ? "Type to search packages" : "No packages found"
        set_string!(buf, results_inner.x + 2, results_inner.y + 1, msg, tstyle(:text_dim))
    else
        visible = results_inner.height
        st.scroll_offset = clamp(st.scroll_offset, 0, max(0, length(st.results) - visible))

        if st.selected > st.scroll_offset + visible
            st.scroll_offset = st.selected - visible
        elseif st.selected <= st.scroll_offset
            st.scroll_offset = max(0, st.selected - 1)
        end

        # Build set of already-installed package names for quick lookup
        installed_set = Set{String}()
        for p in m.installed.packages
            push!(installed_set, p.name)
        end
        union!(installed_set, st.installed_names)

        for i in 1:visible
            idx = i + st.scroll_offset
            idx > length(st.results) && break
            pkg = st.results[idx]
            y = results_inner.y + i - 1
            is_selected = (idx == st.selected)
            is_installing = (st.installing_name == pkg.name)
            is_installed = (pkg.name in installed_set)

            if is_selected
                set_string!(buf, results_inner.x, y, "▶", tstyle(:accent))
            end

            name_style = if is_installed
                tstyle(:success, bold=is_selected)
            elseif is_selected
                tstyle(:accent, bold=true)
            else
                tstyle(:primary)
            end
            set_string!(buf, results_inner.x + 2, y, pkg.name, name_style)

            # Status column: installing progress or installed badge
            status_x = results_inner.x + max(25, div(results_inner.width, 2))
            status_w = results_inner.x + results_inner.width - status_x - 1
            if is_installing
                # Show "Installing" + animated spinner
                spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
                frame = mod(m.tick ÷ 4, length(spinner_chars)) + 1
                label = "$(spinner_chars[frame]) Installing…"
                set_string!(buf, status_x, y, label, tstyle(:warning, bold=true))
            elseif is_installed
                set_string!(buf, status_x, y, "Installed ✓", tstyle(:success))
            elseif pkg.latest_version !== nothing
                if status_x + 10 <= results_inner.x + results_inner.width
                    set_string!(buf, status_x, y, "v" * pkg.latest_version,
                        is_selected ? tstyle(:accent) : tstyle(:text_dim))
                end
            end
        end
    end

    # Action hints
    render(StatusBar(
        left=[
            Span("  [Enter] Install ", tstyle(:accent)),
            Span("[/] Focus search ", tstyle(:text_dim)),
        ],
        right=[],
    ), left_rows[3], buf)

    # ── Right panel: detail ──
    detail_inner = render(Block(title="Package Details", border_style=tstyle(:border)),
        cols[2], buf)

    if !isempty(st.results) && st.selected >= 1 && st.selected <= length(st.results)
        pkg = st.results[st.selected]
        render_registry_detail(pkg, detail_inner, buf)
    else
        set_string!(buf, detail_inner.x + 2, detail_inner.y + 1,
            "Select a package to see details", tstyle(:text_dim))
    end
end

"""Render package details in the right panel."""
function render_registry_detail(pkg::RegistryPackage, area::Rect, buf::Buffer)
    y = area.y
    x = area.x + 2

    set_string!(buf, x, y, pkg.name, tstyle(:primary, bold=true))
    y += 2

    if pkg.latest_version !== nothing
        set_string!(buf, x, y, "Version: ", tstyle(:text_dim))
        set_string!(buf, x + 9, y, "v" * pkg.latest_version, tstyle(:text))
        y += 1
    end

    if pkg.uuid !== nothing
        set_string!(buf, x, y, "UUID: ", tstyle(:text_dim))
        uuid_str = string(pkg.uuid)
        display_uuid = length(uuid_str) > area.width - 10 ?
            uuid_str[1:area.width-10] : uuid_str
        set_string!(buf, x + 6, y, display_uuid, tstyle(:text))
        y += 1
    end

    if pkg.repo !== nothing
        set_string!(buf, x, y, "Repo: ", tstyle(:text_dim))
        repo_str = length(pkg.repo) > area.width - 10 ?
            pkg.repo[1:area.width-10] : pkg.repo
        set_string!(buf, x + 6, y, repo_str, tstyle(:text))
        y += 1
    end

    if pkg.description !== nothing
        y += 1
        set_string!(buf, x, y, "Description:", tstyle(:text_dim))
        y += 1
        # Word-wrap the description
        words = split(pkg.description)
        line = ""
        max_w = area.width - 4
        for word in words
            if length(line) + length(word) + 1 > max_w
                set_string!(buf, x, y, line, tstyle(:text))
                y += 1
                y > area.y + area.height - 1 && break
                line = word
            else
                line = isempty(line) ? word : line * " " * word
            end
        end
        if !isempty(line) && y <= area.y + area.height - 1
            set_string!(buf, x, y, line, tstyle(:text))
        end
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Registry tab key handling
# ──────────────────────────────────────────────────────────────────────────────

"""
    handle_registry_keys!(m::PkgTUIApp, evt::KeyEvent) → Bool
"""
function handle_registry_keys!(m::PkgTUIApp, evt::KeyEvent)::Bool
    st = m.registry

    # ── Search input focused ──
    if st.search_input.focused
        if evt.key == :escape
            # Unfocus but keep the search query
            st.search_input = TextInput(;
                label="  Search: ",
                text=text(st.search_input),
                focused=false,
            )
            return true
        elseif evt.key == :enter
            # Unfocus search, keep query
            st.search_input = TextInput(;
                label="  Search: ",
                text=text(st.search_input),
                focused=false
            )
            return true
        elseif evt.key == :down
            # Move focus from search input to results list
            st.search_input = TextInput(;
                label="  Search: ",
                text=text(st.search_input),
                focused=false,
            )
            st.selected = max(1, st.selected)
            return true
        else
            handle_key!(st.search_input, evt)
            # Trigger search
            do_registry_search!(m)
            return true
        end
    end

    # ── Normal mode ──
    if evt.key == :char
        c = evt.char
        if c == '/'
            st.search_input = TextInput(;
                label="  Search: ",
                text=text(st.search_input),
                focused=true
            )
            return true
        end
    elseif evt.key == :enter
        if !isempty(st.results) && st.selected >= 1 && st.selected <= length(st.results)
            pkg = st.results[st.selected]
            # Don't re-install if already installed or currently installing
            if st.installing_name !== nothing
                return true
            end
            st.installing_name = pkg.name
            push_log!(m, "Installing $(pkg.name)...")
            spawn_task!(m.tq, :add) do
                io = IOBuffer()
                result = add_package(pkg.name, io)
                (result=result, log=String(take!(io)), name=pkg.name)
            end
        end
        return true
    elseif evt.key == :up
        if st.selected <= 1
            # At top of results — move focus back to search input
            st.search_input = TextInput(;
                label="  Search: ",
                text=text(st.search_input),
                focused=true,
            )
        else
            st.selected = st.selected - 1
        end
        return true
    elseif evt.key == :down
        st.selected = min(length(st.results), st.selected + 1)
        return true
    elseif evt.key == :pageup
        st.selected = max(1, st.selected - 10)
        return true
    elseif evt.key == :pagedown
        st.selected = min(length(st.results), st.selected + 10)
        return true
    end

    return false
end

"""Perform a registry search based on current search input."""
function do_registry_search!(m::PkgTUIApp)
    st = m.registry
    query = strip(text(st.search_input))
    if st.index_loaded
        st.results = search_registry(st.registry_index, query)
        st.selected = isempty(st.results) ? 0 : 1
        st.scroll_offset = 0
    end
end
