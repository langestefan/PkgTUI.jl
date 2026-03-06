```@meta
CurrentModule = PkgTUI
```

# PkgTUI

A terminal user interface (TUI) for managing Julia projects using [Pkg.jl](https://pkgdocs.julialang.org/). Built with [Tachikoma.jl](https://github.com/kahliburke/Tachikoma.jl).

## Overview

PkgTUI provides an interactive terminal dashboard for all common package management tasks — installing, removing, updating, searching the registry, exploring dependency trees, resolving conflicts, and profiling compile times — all without leaving your terminal.

## Quick Start

### As a Pkg App (recommended)

```julia
using Pkg
Pkg.Apps.develop(path="/path/to/PkgTUI.jl")
```

Then run from any terminal:

```bash
pkgtui
pkgtui --project=/path/to/project
pkgtui --help
```

### From Julia

```julia
using PkgTUI
pkgtui()                                # active environment
pkgtui(; project="/path/to/MyProject")  # specific project
```

## Tabs

PkgTUI has five main tabs, switched with number keys `1`-`5`:

1. **Installed** — Browse and manage all packages in the current environment. Add, remove, update, pin, or free packages. Filter by name, toggle indirect dependencies.

2. **Updates** — View packages with available updates. Shows ⌃ (can update) and ⌅ (held back) markers. Run dry-run previews. Integrated conflicts panel shows which packages are blocked and why.

3. **Registry** — Search the General registry (13,000+ packages) with fuzzy matching. View package details (version, UUID, repo URL). Install with a single keypress.

4. **Dependencies** — Explore your dependency tree interactively, or switch to a force-directed graph visualization. Run `Pkg.why()` on any dependency to see why it's needed.

5. **Metrics** — Measure disk sizes of all packages. Run compile-time profiling via `Pkg.precompile(; timing=true)`. View results as bar charts and sortable tables.

## Global Keybindings

| Key | Action |
|-----|--------|
| `1`-`5` | Switch tabs |
| `q` / `Esc` | Quit |
| `?` | Help overlay |
| `Ctrl+E` | Switch environment |
| `l` | Toggle log pane |
| `Ctrl+\` | Change theme |

## Contributors

```@raw html
<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
```
