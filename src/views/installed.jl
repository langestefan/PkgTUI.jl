"""
    Installed packages tab view.
"""

"""
    render_installed_tab(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the "Installed" tab showing all packages with filter, actions, and details.
"""
function render_installed_tab(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.installed

    # Layout: filter bar | package table | action hints
    rows = split_layout(Layout(Vertical, [Fixed(3), Fill(), Fixed(1)]), area)

    # ── Filter bar ──
    filter_area = rows[1]
    filter_inner = render(Block(
        title=st.show_indirect ? "Filter (showing all)" : "Filter (direct only)",
        border_style=tstyle(:border)
    ), filter_area, buf)

    if st.adding
        render(st.add_input, filter_inner, buf)
    else
        render(st.filter_input, filter_inner, buf)
    end

    # ── Package table ──
    table_area = rows[2]
    packages = st.filtered
    table_inner = render(Block(
        title="Packages ($(length(packages)))",
        border_style=tstyle(:border)
    ), table_area, buf)

    # Build update lookup from updates state
    update_lookup = Dict{String,UpdateInfo}()
    for u in m.updates_state.updates
        update_lookup[u.name] = u
    end

    if st.loading
        set_string!(buf, table_inner.x + 2, table_inner.y + 1,
            "Loading packages...", tstyle(:text_dim, italic=true))
    elseif isempty(packages)
        set_string!(buf, table_inner.x + 2, table_inner.y + 1,
            "No packages found.", tstyle(:text_dim))
    else
        # Header
        render_package_table_header(table_inner, buf)

        # Rows
        visible_height = table_inner.height - 2  # minus header + separator
        st.scroll_offset = clamp(st.scroll_offset, 0, max(0, length(packages) - visible_height))

        # Auto-scroll to keep selection visible
        if st.selected > st.scroll_offset + visible_height
            st.scroll_offset = st.selected - visible_height
        elseif st.selected <= st.scroll_offset
            st.scroll_offset = max(0, st.selected - 1)
        end

        for i in 1:visible_height
            idx = i + st.scroll_offset
            idx > length(packages) && break
            pkg = packages[idx]
            y = table_inner.y + 1 + i
            is_selected = (idx == st.selected)
            upd = get(update_lookup, pkg.name, nothing)
            render_package_row(pkg, table_inner.x, y, table_inner.width, buf, is_selected, upd)
        end
    end

    # ── Action hints ──
    hints_area = rows[3]
    if st.adding
        render(StatusBar(
            left=[Span("  Enter to add, Esc to cancel", tstyle(:text_dim))],
            right=[],
        ), hints_area, buf)
    else
        render(StatusBar(
            left=[
                Span("  [a]dd ", tstyle(:accent)),
                Span("[r]emove ", tstyle(:accent)),
                Span("[u]pdate ", tstyle(:accent)),
                Span("[U]pdate all ", tstyle(:accent)),
                Span("[p]in ", tstyle(:text_dim)),
                Span("[f]ree ", tstyle(:text_dim)),
            ],
            right=[
                Span("[/]filter ", tstyle(:text_dim)),
                Span("[t]oggle indirect ", tstyle(:text_dim)),
            ],
        ), hints_area, buf)
    end
end

"""Render the table header row."""
function render_package_table_header(area::Rect, buf::Buffer)
    y = area.y
    style = tstyle(:title, bold=true)
    col_name = area.x + 1
    col_ver = area.x + max(30, div(area.width, 3))
    col_type = col_ver + 14
    col_status = col_type + 10
    col_update = col_status + 10

    set_string!(buf, col_name, y, "Name", style)
    set_string!(buf, col_ver, y, "Version", style)
    set_string!(buf, col_type, y, "Type", style)
    if col_status + 8 <= area.x + area.width
        set_string!(buf, col_status, y, "Status", style)
    end
    if col_update + 6 <= area.x + area.width
        set_string!(buf, col_update, y, "Update", style)
    end

    # Separator line
    for x in area.x:(area.x + area.width - 1)
        set_char!(buf, x, y + 1, '─', tstyle(:border))
    end
end

"""Render a single package row."""
function render_package_row(pkg::PackageRow, x::Int, y::Int, width::Int, buf::Buffer,
                             selected::Bool,
                             update_info::Union{UpdateInfo, Nothing}=nothing)
    col_name = x + 1
    col_ver = x + max(30, div(width, 3))
    col_type = col_ver + 14
    col_status = col_type + 10
    col_update = col_status + 10

    name_style = if selected
        tstyle(:accent, bold=true)
    elseif pkg.is_direct_dep
        tstyle(:primary)
    else
        tstyle(:text_dim)
    end

    # Selection indicator
    if selected
        set_string!(buf, col_name - 1, y, "▶", tstyle(:accent))
    end

    set_string!(buf, col_name, y, pkg.name, name_style)

    ver_str = something(pkg.version, "—")
    set_string!(buf, col_ver, y, ver_str, selected ? tstyle(:accent) : tstyle(:text))

    type_str = pkg.is_direct_dep ? "direct" : "indirect"
    type_style = pkg.is_direct_dep ? tstyle(:success) : tstyle(:text_dim)
    set_string!(buf, col_type, y, type_str, selected ? tstyle(:accent) : type_style)

    if col_status + 8 <= x + width
        status_str = if pkg.is_pinned
            "pinned"
        elseif pkg.is_tracking_path
            "path"
        elseif pkg.is_tracking_repo
            "repo"
        else
            "registry"
        end
        set_string!(buf, col_status, y, status_str,
            selected ? tstyle(:accent) : tstyle(:text_dim))
    end

    # Update status column
    if col_update + 6 <= x + width && update_info !== nothing
        if update_info.can_update
            ver = something(update_info.latest_compatible, "⬆")
            upd_str = "⬆ $ver"
            set_string!(buf, col_update, y, upd_str,
                selected ? tstyle(:accent) : tstyle(:success))
        else
            upd_str = "⌅ held"
            set_string!(buf, col_update, y, upd_str,
                selected ? tstyle(:accent) : tstyle(:warning))
        end
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Installed tab key handling
# ──────────────────────────────────────────────────────────────────────────────

"""
    handle_installed_keys!(m::PkgTUIApp, evt::KeyEvent) → Bool

Handle key events for the Installed tab. Returns true if the event was consumed.
"""
function handle_installed_keys!(m::PkgTUIApp, evt::KeyEvent)::Bool
    st = m.installed

    # ── Adding mode ──
    if st.adding
        if evt.key == :escape
            st.adding = false
            set_text!(st.add_input, "")
            st.add_input = TextInput(; label="  Package name: ", focused=false)
            return true
        elseif evt.key == :enter
            name = strip(text(st.add_input))
            if !isempty(name)
                push_log!(m, "Adding package: $name...")
                spawn_task!(m.tq, :add) do
                    io = IOBuffer()
                    result = add_package(String(name), io)
                    (result=result, log=String(take!(io)))
                end
            end
            st.adding = false
            set_text!(st.add_input, "")
            st.add_input = TextInput(; label="  Package name: ", focused=false)
            return true
        else
            handle_key!(st.add_input, evt)
            return true
        end
    end

    # ── Filter focused ──
    if st.filter_input.focused
        if evt.key == :escape
            st.filter_input = TextInput(;
                label="  Filter: ",
                text=text(st.filter_input),
                focused=false,
            )
            apply_filter!(st)
            return true
        elseif evt.key == :enter
            st.filter_input = TextInput(;
                label="  Filter: ",
                text=text(st.filter_input),
                focused=false
            )
            return true
        elseif evt.key == :down
            # Move focus from filter input to package list
            st.filter_input = TextInput(;
                label="  Filter: ",
                text=text(st.filter_input),
                focused=false,
            )
            return true
        else
            handle_key!(st.filter_input, evt)
            apply_filter!(st)
            return true
        end
    end

    # ── Normal mode ──
    if evt.key == :char
        c = evt.char
        if c == 'a'
            st.adding = true
            st.add_input = TextInput(; label="  Package name: ", focused=true)
            return true
        elseif c == 'r'
            pkg = selected_package(st)
            if pkg !== nothing
                m.modal = Modal(;
                    title="Remove Package",
                    message="Remove '$(pkg.name)' from the project?",
                    confirm_label="Remove",
                    cancel_label="Cancel",
                    selected=:cancel
                )
                m.modal_action = :remove
                m.modal_target = pkg.name
            end
            return true
        elseif c == 'u'
            pkg = selected_package(st)
            if pkg !== nothing
                if pkg.is_pinned
                    m.modal = Modal(;
                        title="Package Pinned",
                        message="'$(pkg.name)' is pinned to v$(something(pkg.version, "?")). Unpin and update?",
                        confirm_label="Unpin & Update",
                        cancel_label="Cancel",
                        selected=:cancel
                    )
                    m.modal_action = :unpin_and_update
                    m.modal_target = pkg.name
                else
                    push_log!(m, "Updating $(pkg.name)...")
                    spawn_task!(m.tq, :update_single) do
                        io = IOBuffer()
                        result = update_package(pkg.name, io)
                        (result=result, log=String(take!(io)))
                    end
                end
            end
            return true
        elseif c == 'U'
            push_log!(m, "Updating all packages...")
            spawn_task!(m.tq, :update_all) do
                io = IOBuffer()
                result = update_all(io)
                (result=result, log=String(take!(io)))
            end
            return true
        elseif c == 'p'
            pkg = selected_package(st)
            if pkg !== nothing
                push_log!(m, "Pinning $(pkg.name)...")
                spawn_task!(m.tq, :pin) do
                    io = IOBuffer()
                    result = pin_package(pkg.name, io)
                    (result=result, log=String(take!(io)))
                end
            end
            return true
        elseif c == 'f'
            pkg = selected_package(st)
            if pkg !== nothing
                push_log!(m, "Freeing $(pkg.name)...")
                spawn_task!(m.tq, :free) do
                    io = IOBuffer()
                    result = free_package(pkg.name, io)
                    (result=result, log=String(take!(io)))
                end
            end
            return true
        elseif c == '/'
            st.filter_input = TextInput(; label="  Filter: ", focused=true)
            return true
        elseif c == 't'
            st.show_indirect = !st.show_indirect
            apply_filter!(st)
            return true
        end
    elseif evt.key == :up
        if st.selected <= 1
            # At top of list — move focus back to filter input
            st.filter_input = TextInput(;
                label="  Filter: ",
                text=text(st.filter_input),
                focused=true,
            )
        else
            st.selected = st.selected - 1
        end
        return true
    elseif evt.key == :down
        st.selected = min(length(st.filtered), st.selected + 1)
        return true
    elseif evt.key == :pageup
        st.selected = max(1, st.selected - 10)
        return true
    elseif evt.key == :pagedown
        st.selected = min(length(st.filtered), st.selected + 10)
        return true
    elseif evt.key == :home
        st.selected = 1
        return true
    elseif evt.key == :end_key
        st.selected = max(1, length(st.filtered))
        return true
    elseif evt.key == :delete
        # Same as 'r' — remove
        pkg = selected_package(st)
        if pkg !== nothing
            m.modal = Modal(;
                title="Remove Package",
                message="Remove '$(pkg.name)' from the project?",
                confirm_label="Remove",
                cancel_label="Cancel",
                selected=:cancel
            )
            m.modal_action = :remove
            m.modal_target = pkg.name
        end
        return true
    end

    return false
end

# ── Helpers ──────────────────────────────────────────────────────────────────

"""Get the currently selected package, or nothing."""
function selected_package(st::InstalledState)::Union{PackageRow, Nothing}
    if st.selected >= 1 && st.selected <= length(st.filtered)
        return st.filtered[st.selected]
    end
    return nothing
end

"""Apply the current filter text to the installed packages list."""
function apply_filter!(st::InstalledState)
    query = lowercase(strip(text(st.filter_input)))
    base = st.show_indirect ? st.packages : filter(p -> p.is_direct_dep, st.packages)

    if isempty(query)
        st.filtered = copy(base)
    else
        st.filtered = filter(p -> occursin(query, lowercase(p.name)), base)
    end

    st.selected = clamp(st.selected, 1, max(1, length(st.filtered)))
end
