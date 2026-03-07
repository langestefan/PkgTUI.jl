"""
    Main layout and StatusBar rendering for PkgTUI.
"""

"""
    render_layout(m::PkgTUIApp, f::Frame)

Renders the main application layout: tabs → active view → log pane → status bar.
"""
function render_layout(m::PkgTUIApp, f::Frame)
    buf = f.buffer
    area = f.area

    # Main vertical layout: tabs | content | log | status
    # Hide inline log pane when the full-screen Log tab is active
    log_height = (m.show_log && m.active_tab != 6) ? 6 : 0
    constraints = if log_height > 0
        [Fixed(3), Fill(), Fixed(log_height), Fixed(1)]
    else
        [Fixed(3), Fill(), Fixed(1)]
    end
    rows = split_layout(Layout(Vertical, constraints), area)

    # ── Tab bar ──
    tabs = TabBar(m.tab_names; active = m.active_tab)
    render(tabs, rows[1], buf)

    # ── Active tab content ──
    content_area = rows[2]
    if m.active_tab == 1
        render_installed_tab(m, content_area, buf)
    elseif m.active_tab == 2
        render_updates_tab(m, content_area, buf)
    elseif m.active_tab == 3
        render_registry_tab(m, content_area, buf)
    elseif m.active_tab == 4
        render_dependencies_tab(m, content_area, buf)
    elseif m.active_tab == 5
        render_metrics_tab(m, content_area, buf)
    elseif m.active_tab == 6
        render_log_tab(m, content_area, buf)
    end

    # ── Log pane (not shown when Log tab is active) ──
    if m.show_log && m.active_tab != 6
        log_area = rows[3]
        log_inner =
            render(Block(title = "Log [l]", border_style = tstyle(:border)), log_area, buf)
        render(m.log_pane, log_inner, buf)
    end

    # ── Status bar ──
    status_row = rows[end]
    env_name = if m.project_info.name !== nothing
        m.project_info.name
    elseif m.project_info.path !== nothing
        basename(dirname(m.project_info.path))
    else
        "unknown"
    end

    ws_indicator = m.project_info.is_workspace ? " [ws]" : ""
    pkg_count = m.project_info.dep_count

    left_spans = [
        Span("  $(env_name)$(ws_indicator) ", tstyle(:accent, bold = true)),
        Span(" $(pkg_count) deps ", tstyle(:text_dim)),
    ]
    if !isempty(m.status_message)
        push!(left_spans, Span(" │ ", tstyle(:border)))
        push!(left_spans, Span(m.status_message, tstyle(m.status_style)))
    end

    right_spans = [
        Span("[e]nv ", tstyle(:text_dim)),
        Span("[l]og ", tstyle(:text_dim)),
        Span("[?]help ", tstyle(:text_dim)),
        Span("[q]uit ", tstyle(:text_dim)),
    ]

    render(StatusBar(left = left_spans, right = right_spans), status_row, buf)
end

# ── Toast notifications ──────────────────────────────────────────────────────

"""Push a non-blocking toast notification (stays until dismissed)."""
function push_toast!(
    m::PkgTUIApp,
    message::String;
    style::Symbol = :text,
    icon::String = "",
    hint::String = "",
)
    push!(m.toasts, Toast(; message = message, style = style, icon = icon, hint = hint))
end

"""Dismiss the most recent toast notification."""
function dismiss_toast!(m::PkgTUIApp)
    isempty(m.toasts) || pop!(m.toasts)
end

"""
    render_toasts(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the most recent toast notification centered on screen.
Uses a prominent double-line border and generous padding.
"""
function render_toasts(m::PkgTUIApp, area::Rect, buf::Buffer)
    isempty(m.toasts) && return

    toast = last(m.toasts)

    # Build content lines
    main_line = ""
    if !isempty(toast.icon)
        main_line *= toast.icon * "  "
    end
    main_line *= toast.message

    footer = ""
    if !isempty(toast.hint)
        footer = toast.hint * "  "
    end
    footer *= "[Esc] close"

    # Size: generous padding around content
    content_w = max(length(main_line), length(footer)) + 6   # 3 padding each side
    toast_w = min(content_w + 2, area.width - 4)              # +2 for border chars
    toast_h = 7  # border + blank + message + blank + footer + blank + border

    toast_rect = center(area, toast_w, toast_h)

    # Clear the background behind the toast so underlying text doesn't bleed through
    bg_style = tstyle(:text)  # use default background
    for cy = toast_rect.y:(toast_rect.y+toast_rect.height-1)
        for cx = toast_rect.x:(toast_rect.x+toast_rect.width-1)
            set_char!(buf, cx, cy, ' ', bg_style)
        end
    end

    border_style = tstyle(toast.style, bold = true)
    inner = render(Block(border_style = border_style, box = BOX_DOUBLE), toast_rect, buf)

    # Center the main message line (row 1 of inner, after top padding)
    msg_y = inner.y + 1
    msg_x = inner.x + max(0, (inner.width - length(main_line)) ÷ 2)
    if !isempty(toast.icon)
        set_string!(buf, msg_x, msg_y, toast.icon, tstyle(toast.style, bold = true))
        text_x = msg_x + length(toast.icon) + 2
        set_string!(buf, text_x, msg_y, toast.message, tstyle(toast.style))
    else
        set_string!(buf, msg_x, msg_y, toast.message, tstyle(toast.style))
    end

    # Center the footer line (row 3 of inner)
    foot_y = inner.y + 3
    foot_x = inner.x + max(0, (inner.width - length(footer)) ÷ 2)
    set_string!(buf, foot_x, foot_y, footer, tstyle(:text_dim))
end

"""
    render_help_overlay(m::PkgTUIApp, area::Rect, buf::Buffer)

Render a full-screen help overlay with keybinding reference.
"""
function render_help_overlay(m::PkgTUIApp, area::Rect, buf::Buffer)
    help_rect = center(area, min(area.width - 4, 70), min(area.height - 4, 30))
    inner = render(
        Block(title = "Help — PkgTUI", border_style = tstyle(:accent), box = BOX_DOUBLE),
        help_rect,
        buf,
    )

    help_lines = [
        "Global Keys:",
        "  q / Esc      Quit PkgTUI",
        "  1-6          Switch tabs",
        "  e            Switch environment",
        "  l            Toggle log pane",
        "  ?            Toggle this help",
        "",
        "Installed Tab:",
        "  a            Add package",
        "  r / Delete   Remove selected package",
        "  u            Update selected package",
        "  U            Update all packages",
        "  p            Pin selected package",
        "  f            Free selected package",
        "  /            Focus filter",
        "  t            Toggle indirect deps",
        "",
        "Updates Tab:",
        "  u            Update selected",
        "  U            Update all",
        "  d            Dry-run preview",
        "  c            Toggle conflicts panel",
        "  R            Refresh",
        "",
        "Registry Tab:",
        "  Enter        Install selected",
        "  v            Select version to install",
        "  /            Focus search",
        "  t            Triage failed install",
        "",
        "Dependencies Tab:",
        "  g            Toggle tree/graph view",
        "  w            Show why (dependency path)",
        "  Enter        Expand/collapse node",
        "",
        "Metrics Tab:",
        "  s            Switch size/compile view",
        "  r            Run profiling",
        "",
        "Log Tab:",
        "  /            Search log",
        "  c            Clear log",
        "  G            Jump to bottom (follow)",
        "  g            Jump to top",
    ]

    for (i, line) in enumerate(help_lines)
        y = inner.y + i - 1
        y > inner.y + inner.height - 1 && break
        style = startswith(line, "  ") ? tstyle(:text) : tstyle(:accent, bold = true)
        set_string!(buf, inner.x + 1, y, line, style)
    end
end

"""
    render_env_switcher(m::PkgTUIApp, area::Rect, buf::Buffer)

Render an environment switching overlay.
"""
function render_env_switcher(m::PkgTUIApp, area::Rect, buf::Buffer)
    h = min(length(m.env_list) + 4, area.height - 4)
    w = min(60, area.width - 4)
    env_rect = center(area, w, h)

    inner = render(
        Block(
            title = "Switch Environment",
            border_style = tstyle(:accent),
            box = BOX_ROUNDED,
        ),
        env_rect,
        buf,
    )

    for (i, env) in enumerate(m.env_list)
        y = inner.y + i - 1
        y > inner.y + inner.height - 1 && break
        display_name = env
        # Shorten long paths
        if length(display_name) > inner.width - 4
            display_name = "..." * display_name[end-inner.width+7:end]
        end

        if i == m.env_selected
            set_string!(
                buf,
                inner.x + 1,
                y,
                "▶ " * display_name,
                tstyle(:accent, bold = true),
            )
        else
            set_string!(buf, inner.x + 1, y, "  " * display_name, tstyle(:text))
        end
    end
end
