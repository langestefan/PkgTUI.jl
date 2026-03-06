"""
    Metrics tab view — disk size and load time visualization.
"""

"""
    render_metrics_tab(m::PkgTUIApp, area::Rect, buf::Buffer)

Render the "Metrics" tab with size/compile charts and tables.
"""
function render_metrics_tab(m::PkgTUIApp, area::Rect, buf::Buffer)
    st = m.metrics

    # Layout: summary | chart + table | hints
    rows = split_layout(Layout(Vertical, [Fixed(3), Fill(), Fixed(1)]), area)

    # ── Summary bar ──
    summary_inner = render(
        Block(
            title = st.view_mode == :size ? "Disk Size Metrics" : "Load Time Metrics",
            border_style = tstyle(:border),
        ),
        rows[1],
        buf,
    )

    if !isempty(st.metrics)
        total_size = sum(m.disk_size_bytes for m in st.metrics)
        total_compile = sum(m.compile_time_seconds for m in st.metrics)
        direct_count = count(m -> m.is_direct, st.metrics)

        summary =
            "$(length(st.metrics)) packages │ " *
            "$(direct_count) direct │ " *
            "Total disk: $(format_bytes(total_size)) │ " *
            "Total load: $(format_time(total_compile))"

        set_string!(buf, summary_inner.x + 1, summary_inner.y, summary, tstyle(:text))
    elseif st.loading || st.profiling
        msg = st.profiling ? "Profiling load times..." : "Measuring disk sizes..."
        set_string!(
            buf,
            summary_inner.x + 1,
            summary_inner.y,
            msg,
            tstyle(:text_dim, italic = true),
        )
    else
        set_string!(
            buf,
            summary_inner.x + 1,
            summary_inner.y,
            "Press [r] to run profiling, or switch to Installed tab first",
            tstyle(:text_dim),
        )
    end

    # ── Chart + table ──
    content = rows[2]
    if st.profiling
        render_profiling_progress(m, content, buf)
    elseif !isempty(st.metrics)
        # Horizontal split: bar chart | table
        cols = split_layout(Layout(Horizontal, [Percent(40), Fill()]), content)
        render_metrics_chart(st, cols[1], buf)
        render_metrics_table(st, cols[2], buf)
    else
        inner = render(Block(border_style = tstyle(:border)), content, buf)
        set_string!(
            buf,
            inner.x + 2,
            inner.y + 1,
            "No metrics data. Press [r] to measure.",
            tstyle(:text_dim),
        )
    end

    # ── Hints ──
    render(
        StatusBar(
            left = [
                Span("  ↑↓ scroll ", tstyle(:text_dim)),
                Span("[s]witch size/load ", tstyle(:accent)),
                Span("[r]un profiling ", tstyle(:accent)),
            ],
            right = [
                Span(
                    st.view_mode == :size ? "Size View " : "Load Time View ",
                    tstyle(:text_dim),
                ),
            ],
        ),
        rows[3],
        buf,
    )
end

"""Render the bar chart of top packages by size or compile time."""
function render_metrics_chart(st::MetricsState, area::Rect, buf::Buffer)
    inner = render(
        Block(
            title = st.view_mode == :size ? "Top by Disk Size" : "Top by Load Time",
            border_style = tstyle(:border),
        ),
        area,
        buf,
    )

    display_metrics = sort(
        st.metrics;
        by = m -> st.view_mode == :size ? m.disk_size_bytes : m.compile_time_seconds,
        rev = true,
    )

    # Take top N that fit
    n = min(length(display_metrics), inner.height - 1)
    top_n = first(display_metrics, n)
    isempty(top_n) && return

    entries = if st.view_mode == :size
        [BarEntry(m.name, Float64(m.disk_size_bytes) / 1024.0) for m in top_n]
    else
        # Clamp to 0 so errored packages (-1.0) don't produce negative bars
        [BarEntry(m.name, max(0.0, m.compile_time_seconds * 1000.0)) for m in top_n]
    end

    render(BarChart(entries; block = Block()), inner, buf)
end

"""Render the sortable metrics table."""
function render_metrics_table(st::MetricsState, area::Rect, buf::Buffer)
    inner = render(Block(title = "All Packages", border_style = tstyle(:border)), area, buf)

    # Sort the metrics
    sorted = sort(st.metrics; by = m -> begin
        if st.sort_by == :size
            m.disk_size_bytes
        elseif st.sort_by == :compile
            m.compile_time_seconds
        else
            lowercase(m.name)
        end
    end, rev = st.sort_desc)

    # Header
    y = inner.y
    x = inner.x + 1
    h_style = tstyle(:title, bold = true)
    set_string!(buf, x, y, "Name", h_style)
    set_string!(buf, x + 25, y, "Disk Size", h_style)
    set_string!(buf, x + 38, y, "Load", h_style)
    set_string!(buf, x + 48, y, "Type", h_style)
    y += 1
    for bx = inner.x:(inner.x+inner.width-1)
        set_char!(buf, bx, y, '─', tstyle(:border))
    end
    y += 1

    # Available rows for data
    visible_rows = inner.height - 2  # minus header + separator
    total = length(sorted)

    # Clamp scroll and selection
    st.selected = clamp(st.selected, 1, max(1, total))
    max_offset = max(0, total - visible_rows)
    st.scroll_offset = clamp(st.scroll_offset, 0, max_offset)

    # Ensure selected row is visible
    if st.selected - 1 < st.scroll_offset
        st.scroll_offset = st.selected - 1
    elseif st.selected - 1 >= st.scroll_offset + visible_rows
        st.scroll_offset = st.selected - visible_rows
    end

    # Rows
    for i in 1:visible_rows
        idx = i + st.scroll_offset
        idx > total && break
        m = sorted[idx]
        is_selected = idx == st.selected

        name_style = if is_selected
            tstyle(:accent, bold = true)
        elseif m.is_direct
            tstyle(:primary)
        else
            tstyle(:text_dim)
        end
        val_style = is_selected ? tstyle(:accent) : tstyle(:text)
        type_style = if is_selected
            tstyle(:accent, bold = true)
        elseif m.is_direct
            tstyle(:success)
        else
            tstyle(:text_dim)
        end

        # Selection indicator
        prefix = is_selected ? "▶ " : "  "
        set_string!(buf, x - 1, y, prefix, name_style)
        set_string!(buf, x + 1, y, m.name, name_style)
        set_string!(buf, x + 25, y, format_bytes(m.disk_size_bytes), val_style)
        set_string!(buf, x + 38, y, format_time(m.compile_time_seconds), val_style)
        set_string!(
            buf,
            x + 48,
            y,
            m.is_direct ? "direct" : "indirect",
            type_style,
        )
        y += 1
    end

    # Scroll indicator
    if total > visible_rows
        pct = round(Int, 100.0 * (st.scroll_offset + visible_rows) / total)
        pos_str = "$(min(pct, 100))% ($(total))"
        set_string!(buf, inner.x + inner.width - length(pos_str) - 1,
            inner.y + inner.height - 1, pos_str, tstyle(:text_dim))
    end
end

"""Render profiling progress."""
function render_profiling_progress(m::PkgTUIApp, area::Rect, buf::Buffer)
    inner = render(Block(title = "Profiling...", border_style = tstyle(:accent)), area, buf)

    # Simple progress indicator
    y = inner.y + div(inner.height, 2) - 1
    set_string!(
        buf,
        inner.x + 2,
        y,
        "Measuring package load times...",
        tstyle(:accent, bold = true),
    )

    progress = m.metrics.profile_progress
    gauge_area = Rect(inner.x + 2, y + 2, inner.width - 4, 1)
    if gauge_area.width > 0
        render(
            Gauge(
                progress;
                filled_style = tstyle(:primary),
                empty_style = tstyle(:text_dim, dim = true),
                tick = m.tick,
            ),
            gauge_area,
            buf,
        )
    end

    set_string!(
        buf,
        inner.x + 2,
        y + 4,
        "This may take a while. Loading each package in a fresh process.",
        tstyle(:text_dim),
    )
end

# ──────────────────────────────────────────────────────────────────────────────
# Metrics tab key handling
# ──────────────────────────────────────────────────────────────────────────────

"""
    handle_metrics_keys!(m::PkgTUIApp, evt::KeyEvent) → Bool
"""
function handle_metrics_keys!(m::PkgTUIApp, evt::KeyEvent)::Bool
    st = m.metrics

    if evt.key == :char
        c = evt.char
        if c == 's'
            st.view_mode = st.view_mode == :size ? :compile : :size
            st.sort_by = st.view_mode == :size ? :size : :compile
            return true
        elseif c == 'r'
            if !st.profiling
                start_profiling!(m)
            end
            return true
        end
    elseif evt.key == :up
        st.selected = max(1, st.selected - 1)
        return true
    elseif evt.key == :down
        st.selected = min(length(st.metrics), st.selected + 1)
        return true
    elseif evt.key == :pageup
        st.selected = max(1, st.selected - 20)
        return true
    elseif evt.key == :pagedown
        st.selected = min(length(st.metrics), st.selected + 20)
        return true
    elseif evt.key == :home
        st.selected = 1
        return true
    elseif evt.key == :endd
        st.selected = length(st.metrics)
        return true
    end

    return false
end

"""Start the full profiling pipeline: disk sizes → compile times."""
function start_profiling!(m::PkgTUIApp)
    st = m.metrics
    st.profiling = true
    st.profile_progress = 0.0
    push_log!(m, "Starting dependency profiling...")

    # First: measure disk sizes
    spawn_task!(m.tq, :measure_sizes) do
        packages = m.installed.packages
        metrics = measure_disk_sizes(packages)
        metrics
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Formatting helpers
# ──────────────────────────────────────────────────────────────────────────────

"""Format bytes as human-readable string."""
function format_bytes(bytes::Int64)::String
    if bytes < 1024
        return "$(bytes) B"
    elseif bytes < 1024^2
        return "$(round(bytes / 1024; digits=1)) KB"
    elseif bytes < 1024^3
        return "$(round(bytes / 1024^2; digits=1)) MB"
    else
        return "$(round(bytes / 1024^3; digits=2)) GB"
    end
end

"""Format seconds as milliseconds string."""
function format_time(seconds::Float64)::String
    if seconds < 0.0
        return "err"       # package failed to load in isolation
    elseif seconds == 0.0
        return "—"          # not measured
    else
        ms = seconds * 1000.0
        if ms < 1.0
            return "< 1 ms"
        elseif ms < 10.0
            return "$(round(ms; digits=2)) ms"
        elseif ms < 100.0
            return "$(round(ms; digits=1)) ms"
        else
            return "$(round(Int, ms)) ms"
        end
    end
end
