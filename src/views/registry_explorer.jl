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
    search_inner = render(
        Block(title = "Search Registry", border_style = tstyle(:border)),
        left_rows[1],
        buf,
    )
    render(st.search_input, search_inner, buf)

    # Results list
    results_inner = render(
        Block(
            title = st.loading ? "Searching..." : "Results ($(length(st.results)))",
            border_style = tstyle(:border),
        ),
        left_rows[2],
        buf,
    )

    if !st.index_loaded
        set_string!(
            buf,
            results_inner.x + 2,
            results_inner.y + 1,
            "Loading registry index...",
            tstyle(:text_dim, italic = true),
        )
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

        # Column positions: Name | Version | Status  (scale with panel width)
        name_col = results_inner.x + 2
        name_width = max(16, div(results_inner.width * 55, 100) - 2)
        ver_x = results_inner.x + name_width + 2
        status_x = ver_x + 10

        for i = 1:visible
            idx = i + st.scroll_offset
            idx > length(st.results) && break
            pkg = st.results[idx]
            y = results_inner.y + i - 1
            is_selected = (idx == st.selected)
            is_installing = (st.installing_name == pkg.name)
            is_installed = (pkg.name in installed_set)
            is_failed = (pkg.name in st.failed_names)

            if is_selected
                set_string!(buf, results_inner.x, y, "▶", tstyle(:accent))
            end

            # Name column (truncate to fit)
            name_style = if is_installed
                tstyle(:success, bold = is_selected)
            elseif is_failed
                tstyle(:error, bold = is_selected)
            elseif is_selected
                tstyle(:accent, bold = true)
            else
                tstyle(:primary)
            end
            display_name = length(pkg.name) > name_width ? pkg.name[1:name_width-1] * "…" : pkg.name
            set_string!(buf, name_col, y, display_name, name_style)

            # Version column (always shown)
            if pkg.latest_version !== nothing
                set_string!(
                    buf,
                    ver_x,
                    y,
                    "v" * pkg.latest_version,
                    is_selected ? tstyle(:accent) : tstyle(:text_dim),
                )
            end

            # Status column
            if is_installing
                spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
                frame = mod(m.tick ÷ 4, length(spinner_chars)) + 1
                set_string!(
                    buf,
                    status_x,
                    y,
                    "$(spinner_chars[frame]) Installing…",
                    tstyle(:warning, bold = true),
                )
            elseif is_installed
                set_string!(buf, status_x, y, "Installed ✓", tstyle(:success))
            elseif is_failed
                set_string!(buf, status_x, y, "Failed ✗", tstyle(:error))
            end
        end
    end

    # Action hints — show [t]riage when a failed package is selected
    selected_is_failed =
        !isempty(st.results) &&
        st.selected >= 1 &&
        st.selected <= length(st.results) &&
        st.results[st.selected].name in st.failed_names

    hint_spans = [
        Span("  [Enter] Install ", tstyle(:accent)),
        Span("[v]ersion ", tstyle(:accent)),
        Span("[/] Focus search ", tstyle(:text_dim)),
    ]
    if selected_is_failed
        push!(hint_spans, Span("[t]riage ", tstyle(:error)))
    end
    render(StatusBar(left = hint_spans, right = []), left_rows[3], buf)

    # ── Right panel: detail ──
    detail_inner = render(
        Block(title = "Package Details", border_style = tstyle(:border)),
        cols[2],
        buf,
    )

    if !isempty(st.results) && st.selected >= 1 && st.selected <= length(st.results)
        pkg = st.results[st.selected]
        render_registry_detail(pkg, detail_inner, buf)
    else
        set_string!(
            buf,
            detail_inner.x + 2,
            detail_inner.y + 1,
            "Select a package to see details",
            tstyle(:text_dim),
        )
    end
end

"""Render package details in the right panel."""
function render_registry_detail(pkg::RegistryPackage, area::Rect, buf::Buffer)
    y = area.y
    x = area.x + 2

    set_string!(buf, x, y, pkg.name, tstyle(:primary, bold = true))
    y += 2

    if pkg.latest_version !== nothing
        set_string!(buf, x, y, "Version: ", tstyle(:text_dim))
        set_string!(buf, x + 9, y, "v" * pkg.latest_version, tstyle(:text))
        y += 1
    end

    if pkg.uuid !== nothing
        set_string!(buf, x, y, "UUID: ", tstyle(:text_dim))
        uuid_str = string(pkg.uuid)
        display_uuid =
            length(uuid_str) > area.width - 10 ? uuid_str[1:area.width-10] : uuid_str
        set_string!(buf, x + 6, y, display_uuid, tstyle(:text))
        y += 1
    end

    if pkg.repo !== nothing
        set_string!(buf, x, y, "Repo: ", tstyle(:text_dim))
        repo_str = length(pkg.repo) > area.width - 10 ? pkg.repo[1:area.width-10] : pkg.repo
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
                label = "  Search: ",
                text = text(st.search_input),
                focused = false,
            )
            return true
        elseif evt.key == :enter
            # Unfocus search, keep query
            st.search_input = TextInput(;
                label = "  Search: ",
                text = text(st.search_input),
                focused = false,
            )
            return true
        elseif evt.key == :down
            # Move focus from search input to results list
            st.search_input = TextInput(;
                label = "  Search: ",
                text = text(st.search_input),
                focused = false,
            )
            st.selected = max(1, st.selected)
            return true
        elseif evt.key == :char && evt.char in ('1', '2', '3', '4', '5')
            # Let tab-switch keys pass through to global handler
            return false
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
                label = "  Search: ",
                text = text(st.search_input),
                focused = true,
            )
            return true
        elseif c == 'v'
            # Open version picker for the selected package
            if !isempty(st.results) && st.selected >= 1 && st.selected <= length(st.results)
                pkg = st.results[st.selected]
                vp = st.version_picker
                vp.package_name = pkg.name
                vp.versions = String[]
                vp.selected = 1
                vp.scroll_offset = 0
                vp.show = true
                push_log!(m, "Loading versions for $(pkg.name)...")
                spawn_task!(m.tq, :fetch_versions) do
                    fetch_package_versions(pkg.name)
                end
            end
            return true
        elseif c == 't'
            # Open triage for a failed package
            if !isempty(st.results) && st.selected >= 1 && st.selected <= length(st.results)
                pkg = st.results[st.selected]
                if pkg.name in st.failed_names
                    m.triage.package_name = pkg.name
                    # Re-use stored error if available, otherwise generic
                    if isempty(m.triage.error_message) || m.triage.package_name != pkg.name
                        m.triage.error_message = "Error in add: installation failed for $(pkg.name)"
                        m.triage.pkg_log = ""
                    end
                    build_triage_content!(m.triage, m.project_info)
                    m.triage.show = true
                    push_log!(m, "Triage window opened for $(pkg.name).")
                    return true
                end
            end
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
                (result = result, log = String(take!(io)), name = pkg.name)
            end
        end
        return true
    elseif evt.key == :up
        if st.selected <= 1
            # At top of results — move focus back to search input
            st.search_input = TextInput(;
                label = "  Search: ",
                text = text(st.search_input),
                focused = true,
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

# ──────────────────────────────────────────────────────────────────────────────
# Version picker overlay
# ──────────────────────────────────────────────────────────────────────────────

"""
    render_version_picker(m::PkgTUIApp, area::Rect, buf::Buffer)

Render a centered overlay listing all available versions of a package.
"""
function render_version_picker(m::PkgTUIApp, area::Rect, buf::Buffer)
    vp = m.registry.version_picker
    isempty(vp.versions) && return

    # Size the overlay
    w = min(area.width - 4, 40)
    h = min(area.height - 4, length(vp.versions) + 4)  # +4 for border + status
    h = max(h, 6)
    overlay_rect = center(area, w, h)

    # Clear background
    blank = " "^overlay_rect.width
    for y = overlay_rect.y:(overlay_rect.y+overlay_rect.height-1)
        set_string!(buf, overlay_rect.x, y, blank, tstyle(:text))
    end

    inner = render(
        Block(
            title = "Install $(vp.package_name) — Select Version",
            border_style = tstyle(:accent),
            box = BOX_DOUBLE,
        ),
        overlay_rect,
        buf,
    )

    # Layout: list | status bar
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), inner)
    list_area = rows[1]
    status_area = rows[2]

    visible = list_area.height
    vp.scroll_offset = clamp(vp.scroll_offset, 0, max(0, length(vp.versions) - visible))

    if vp.selected > vp.scroll_offset + visible
        vp.scroll_offset = vp.selected - visible
    elseif vp.selected <= vp.scroll_offset
        vp.scroll_offset = max(0, vp.selected - 1)
    end

    for i = 1:visible
        idx = i + vp.scroll_offset
        idx > length(vp.versions) && break
        y = list_area.y + i - 1
        is_selected = (idx == vp.selected)

        if is_selected
            set_string!(buf, list_area.x, y, "▶", tstyle(:accent))
        end

        ver_str = "v" * vp.versions[idx]
        style = is_selected ? tstyle(:accent, bold = true) : tstyle(:text)
        set_string!(buf, list_area.x + 2, y, ver_str, style)

        # Mark latest
        if idx == 1
            set_string!(
                buf,
                list_area.x + 2 + length(ver_str) + 1,
                y,
                "(latest)",
                tstyle(:text_dim),
            )
        end
    end

    render(
        StatusBar(
            left = [
                Span("  ↑↓ select ", tstyle(:text_dim)),
                Span("[Enter] install ", tstyle(:accent)),
                Span("[Esc] cancel ", tstyle(:text_dim)),
            ],
            right = [],
        ),
        status_area,
        buf,
    )
end

"""
    handle_version_picker_keys!(m::PkgTUIApp, evt::KeyEvent) → Bool

Handle keyboard input for the version picker overlay.
"""
function handle_version_picker_keys!(m::PkgTUIApp, evt::KeyEvent)::Bool
    vp = m.registry.version_picker

    if evt.key == :escape
        vp.show = false
        return true
    elseif evt.key == :up
        vp.selected = max(1, vp.selected - 1)
        return true
    elseif evt.key == :down
        vp.selected = min(length(vp.versions), vp.selected + 1)
        return true
    elseif evt.key == :pageup
        vp.selected = max(1, vp.selected - 10)
        return true
    elseif evt.key == :pagedown
        vp.selected = min(length(vp.versions), vp.selected + 10)
        return true
    elseif evt.key == :home
        vp.selected = 1
        return true
    elseif evt.key == :endd
        vp.selected = length(vp.versions)
        return true
    elseif evt.key == :enter
        if vp.selected >= 1 && vp.selected <= length(vp.versions)
            version = vp.versions[vp.selected]
            pkg_name = vp.package_name
            st = m.registry

            # Don't install if already installing something
            if st.installing_name !== nothing
                vp.show = false
                return true
            end

            st.installing_name = pkg_name
            push_log!(m, "Installing $(pkg_name)@$(version)...")
            spawn_task!(m.tq, :add) do
                io = IOBuffer()
                result = add_package(pkg_name, io; version = version)
                # Pin to the selected version so compat is set correctly
                if !startswith(result, "Error")
                    try
                        pin_package(pkg_name, io; version = VersionNumber(version))
                    catch
                    end
                end
                (result = result, log = String(take!(io)), name = pkg_name)
            end
            vp.show = false
        end
        return true
    end

    return false
end
