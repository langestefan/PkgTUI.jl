# PkgTUI.jl

[![Test](https://github.com/langestefan/PkgTUI.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/langestefan/PkgTUI.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/langestefan/PkgTUI.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/langestefan/PkgTUI.jl)

PkgTUI brings a full-featured terminal interface to [Pkg.jl](https://pkgdocs.julialang.org/), built with [Tachikoma.jl](https://github.com/kahliburke/Tachikoma.jl). Browse packages, check for updates, explore the registry, visualize dependencies, and profile compile times — all without leaving the terminal.

<div align="center">
<img src="demo.svg" alt="PkgTUI demo" width="800">
</div>

## Installation

PkgTUI is a [Pkg App](https://pkgdocs.julialang.org/dev/apps/). Install once, use from any terminal:

```julia
using Pkg
Pkg.Apps.add(url="https://github.com/langestefan/PkgTUI.jl")
```

Or with a single command:

```bash
julia --project -e 'using Pkg; Pkg.Apps.add(url="https://github.com/langestefan/PkgTUI.jl")'
```

Then invoke with:

```bash
pkgtui                          # active environment
pkgtui --project=/path/to/proj  # specific project
pkgtui --help                   # usage info
```

Or from Julia directly:

```julia
using PkgTUI
pkgtui()
pkgtui(; project="/path/to/MyProject")
```

> [!IMPORTANT]
> You need to manually make ~/.julia/bin available on the PATH environment.
> The path to the julia executable used is the same as the one used to install the app.
> If this julia installation gets removed, you might need to reinstall the app. See the
> [Pkg App documentation](https://pkgdocs.julialang.org/dev/apps/) for more details.

## Features

### Installed Packages

Browse all packages in your environment with full CRUD operations. Filter by name, toggle indirect dependencies, and see pinned/tracked status at a glance.

| Key | Action |
|-----|--------|
| `a` | Add package |
| `r` / `Del` | Remove |
| `u` | Update selected |
| `U` | Update all |
| `p` | Pin |
| `f` | Free |
| `/` | Filter |
| `t` | Toggle indirect deps |

### Update Notifications

See available updates with **⌃** (compatible) and **⌅** (breaking) markers. Preview changes before committing with dry-run diffs, and view dependency conflicts that hold packages back.

| Key | Action |
|-----|--------|
| `u` | Update selected |
| `U` | Update all |
| `d` | Dry-run preview |
| `R` | Refresh |
| `c` | Toggle conflicts panel |

### Registry Explorer

Search 13,000+ registered packages with fuzzy matching. View descriptions, repo URLs, and available versions — install with a single keypress.

| Key | Action |
|-----|--------|
| `/` | Search |
| `Enter` | Install |

### Dependency Visualizer

Explore your dependency tree interactively. Use `Pkg.why()` integration to understand why a package is in your environment.

| Key | Action |
|-----|--------|
| `g` | Toggle tree/graph view |
| `w` | `Pkg.why()` for selected package |
| `Enter` | Expand/collapse node |

### Metrics Dashboard

Bar charts of disk usage per package and compile-time profiling via `Pkg.precompile(; timing=true)`. Sort by size, compile time, or name.

| Key | Action |
|-----|--------|
| `s` | Switch size/compile view |
| `r` | Run profiling |

### More

- **Environment Switching** — `Ctrl+E` to switch between Julia environments
- **Workspace Support** — auto-detects and displays workspace sub-projects
- **Live Log Pane** — toggle with `l`, or switch to the full-screen Log tab (`6`)
- **Install Triage** — detailed failure diagnostics with compat analysis
- **Themes** — cycle through themes with `Ctrl+\`
- **Help Overlay** — press `?` anywhere for context-sensitive keybindings

## Global Keybindings

| Key | Action |
|-----|--------|
| `1`–`6` | Switch tabs (Installed, Updates, Registry, Dependencies, Metrics, Log) |
| `q` / `Esc` | Quit |
| `?` | Help overlay |
| `Ctrl+E` | Switch environment |
| `l` | Toggle log pane |
| `Ctrl+\` | Change theme |

## Requirements

- **Julia 1.12+**
- A terminal with Unicode support
