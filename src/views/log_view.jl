"""
    Full-screen Log tab — searchable, scrollable log viewer.
"""

"""
    render_log_tab(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the full-screen log tab with all log entries, search, and scroll.
"""
function render_log_tab(m::PkgTUIApp, area::Rect, buf::Buffer)
    ls = m.log_state

    # Layout: search bar (if active) | log content | hints
    has_search = ls.search_active
    constraints = if has_search
        [Fixed(3), Fill(), Fixed(1)]
    else
        [Fill(), Fixed(1)]
    end
    rows = split_layout(Layout(Vertical, constraints), area)

    # ── Search bar ──
    if has_search
        search_inner =
            render(Block(title = "Search", border_style = tstyle(:accent)), rows[1], buf)
        render(ls.search_input, search_inner, buf)
    end

    content_idx = has_search ? 2 : 1

    # ── Log content ──
    content = rows[content_idx]
    lines = m.log_pane.content
    total = length(lines)

    # Apply search filter
    filtered_indices = if !isempty(ls.search_query)
        query_lower = lowercase(ls.search_query)
        [i for i = 1:total if occursin(query_lower, lowercase(lines[i]))]
    else
        collect(1:total)
    end

    n_filtered = length(filtered_indices)
    title = if !isempty(ls.search_query)
        "Log ($(n_filtered)/$(total) lines matching '$(ls.search_query)')"
    else
        "Log ($(total) lines)"
    end

    log_inner = render(Block(title = title, border_style = tstyle(:border)), content, buf)
    visible = log_inner.height

    if isempty(filtered_indices)
        if !isempty(ls.search_query)
            set_string!(
                buf,
                log_inner.x + 2,
                log_inner.y + 1,
                "No log lines match '$(ls.search_query)'",
                tstyle(:text_dim, italic = true),
            )
        else
            set_string!(
                buf,
                log_inner.x + 2,
                log_inner.y + 1,
                "No log entries yet.",
                tstyle(:text_dim, italic = true),
            )
        end
    else
        # Clamp scroll
        max_offset = max(0, n_filtered - visible)
        ls.scroll_offset = clamp(ls.scroll_offset, 0, max_offset)

        # Auto-follow: if at bottom and no search, stay at bottom
        if ls.following && isempty(ls.search_query)
            ls.scroll_offset = max_offset
        end

        for i = 1:visible
            idx = i + ls.scroll_offset
            idx > n_filtered && break
            line_idx = filtered_indices[idx]
            line = lines[line_idx]
            y = log_inner.y + i - 1

            # Line number gutter
            gutter = lpad(string(line_idx), 4) * " │ "
            set_string!(buf, log_inner.x, y, gutter, tstyle(:text_dim))

            # Log line with syntax highlighting
            gutter_width = length(gutter)
            remaining_width = log_inner.width - gutter_width
            display_line = length(line) > remaining_width ? line[1:remaining_width] : line

            style = if startswith(line, "  ") && occursin("failed", lowercase(line))
                tstyle(:error)
            elseif occursin("error", lowercase(line)) || occursin("failed", lowercase(line))
                tstyle(:error, bold = true)
            elseif occursin("warning", lowercase(line))
                tstyle(:warning)
            elseif occursin("success", lowercase(line)) ||
                   occursin("complete", lowercase(line))
                tstyle(:success)
            elseif startswith(line, "  ")
                tstyle(:text_dim)
            else
                tstyle(:text)
            end

            # Highlight search matches
            if !isempty(ls.search_query)
                _render_highlighted_line!(
                    buf,
                    log_inner.x + gutter_width,
                    y,
                    display_line,
                    ls.search_query,
                    style,
                    remaining_width,
                )
            else
                set_string!(buf, log_inner.x + gutter_width, y, display_line, style)
            end
        end

        # Scroll position indicator
        if n_filtered > visible
            pct = round(Int, 100.0 * (ls.scroll_offset + visible) / n_filtered)
            pos_str = "$(min(pct, 100))%"
            set_string!(
                buf,
                log_inner.x + log_inner.width - length(pos_str) - 1,
                log_inner.y + log_inner.height - 1,
                pos_str,
                tstyle(:text_dim),
            )
        end
    end

    # ── Hints ──
    render(
        StatusBar(
            left = [
                Span("  ↑↓ scroll ", tstyle(:text_dim)),
                Span("PgUp/PgDn ", tstyle(:text_dim)),
                Span("[/]search ", tstyle(:accent)),
                Span("[G]o bottom ", tstyle(:accent)),
                Span("[g]o top ", tstyle(:accent)),
                Span("[c]lear ", tstyle(:accent)),
            ],
            right = [
                Span(
                    ls.following ? "Following ● " : "Paused ○ ",
                    ls.following ? tstyle(:success) : tstyle(:text_dim),
                ),
            ],
        ),
        rows[end],
        buf,
    )
end

"""Render a line with search term highlighted."""
function _render_highlighted_line!(
    buf::Buffer,
    x::Int,
    y::Int,
    line::String,
    query::String,
    base_style,
    max_width::Int,
)
    query_lower = lowercase(query)
    line_lower = lowercase(line)
    pos = 1
    cx = x

    while pos <= length(line) && (cx - x) < max_width
        match_start = findnext(query_lower, line_lower, pos)
        if match_start === nothing
            # No more matches — render rest normally
            remaining = line[pos:end]
            if length(remaining) > max_width - (cx - x)
                remaining = remaining[1:max_width-(cx-x)]
            end
            set_string!(buf, cx, y, remaining, base_style)
            break
        else
            # Render text before match
            if first(match_start) > pos
                before = line[pos:first(match_start)-1]
                set_string!(buf, cx, y, before, base_style)
                cx += length(before)
            end
            # Render matched text highlighted
            match_text = line[match_start]
            set_string!(buf, cx, y, match_text, tstyle(:accent, bold = true))
            cx += length(match_text)
            pos = last(match_start) + 1
        end
    end
end

"""
    handle_log_keys!(m::PkgTUIApp, evt::KeyEvent) → Bool
"""
function handle_log_keys!(m::PkgTUIApp, evt::KeyEvent)::Bool
    ls = m.log_state

    # ── Search mode ──
    if ls.search_active
        if evt.key == :escape
            ls.search_active = false
            ls.search_input = TextInput(; label = "  Search: ", focused = false)
            return true
        elseif evt.key == :enter
            ls.search_query = strip(text(ls.search_input))
            ls.search_active = false
            ls.search_input =
                TextInput(; label = "  Search: ", text = ls.search_query, focused = false)
            ls.scroll_offset = 0
            ls.following = false
            return true
        else
            handle_key!(ls.search_input, evt)
            return true
        end
    end

    # ── Normal mode ──
    if evt.key == :char
        c = evt.char
        if c == '/'
            ls.search_active = true
            ls.search_input =
                TextInput(; label = "  Search: ", text = ls.search_query, focused = true)
            return true
        elseif c == 'c'
            empty!(m.log_pane.content)
            ls.scroll_offset = 0
            push_log!(m, "Log cleared.")
            return true
        elseif c == 'G'
            # Go to bottom, resume following
            ls.following = true
            n = length(m.log_pane.content)
            ls.scroll_offset = max(0, n - 10)  # will be clamped in render
            return true
        elseif c == 'g'
            # Go to top
            ls.scroll_offset = 0
            ls.following = false
            return true
        end
    elseif evt.key == :up
        ls.scroll_offset = max(0, ls.scroll_offset - 1)
        ls.following = false
        return true
    elseif evt.key == :down
        ls.scroll_offset += 1
        ls.following = false
        return true
    elseif evt.key == :pageup
        ls.scroll_offset = max(0, ls.scroll_offset - 20)
        ls.following = false
        return true
    elseif evt.key == :pagedown
        ls.scroll_offset += 20
        ls.following = false
        return true
    elseif evt.key == :home
        ls.scroll_offset = 0
        ls.following = false
        return true
    elseif evt.key == :endd
        ls.following = true
        return true
    end

    return false
end
