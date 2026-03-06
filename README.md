# PkgTUI

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://langestefan.github.io/PkgTUI.jl/stable)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://langestefan.github.io/PkgTUI.jl/dev)
[![Test workflow status](https://github.com/langestefan/PkgTUI.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/langestefan/PkgTUI.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/langestefan/PkgTUI.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/langestefan/PkgTUI.jl)

A terminal user interface (TUI) for managing Julia projects using [Pkg.jl](https://pkgdocs.julialang.org/). Built with [Tachikoma.jl](https://github.com/kahliburke/Tachikoma.jl).

## Features

- **Installed Packages** — Browse, filter, add, remove, update, pin, and free packages
- **Update Notifications** — See available updates with ⌃/⌅ markers, dry-run previews
- **Registry Explorer** — Search 13,000+ packages with fuzzy matching, view details, one-key install
- **Dependency Visualizer** — Interactive tree view and force-directed graph with `Pkg.why()` integration
- **Dependency Conflicts** — See which packages are held back and what's blocking them
- **Metrics Dashboard** — Disk size bar charts, compile-time profiling via `Pkg.precompile(; timing=true)`
- **Environment Switching** — Switch between Julia environments with `Ctrl+E`
- **Workspace Support** — Detects and displays workspace projects

## Installation

PkgTUI is a [Pkg App](https://pkgdocs.julialang.org/dev/apps/). Install it once and use it from any terminal:

```julia
using Pkg
Pkg.Apps.develop(path="/path/to/PkgTUI.jl")  # local development
# or when registered:
# Pkg.Apps.add("PkgTUI")
```

Then run from your shell:

```bash
pkgtui                          # manage the active environment
pkgtui --project=/path/to/proj  # manage a specific project
pkgtui --help                   # show usage info
```

Or use it directly from Julia:

```julia
using PkgTUI
pkgtui()                                    # active environment
pkgtui(; project="/path/to/MyProject")      # specific project
```

## Keybindings

### Global

| Key | Action |
|-----|--------|
| `1`-`5` | Switch tabs (Installed, Updates, Registry, Dependencies, Metrics) |
| `q` / `Esc` | Quit |
| `?` | Toggle help overlay |
| `Ctrl+E` | Switch environment |
| `l` | Toggle log pane |
| `Ctrl+\` | Change theme |

### Installed Tab

| Key | Action |
|-----|--------|
| `a` | Add a package |
| `r` / `Del` | Remove selected package |
| `u` | Update selected package |
| `U` | Update all packages |
| `p` | Pin selected package |
| `f` | Free selected package |
| `/` | Focus filter input |
| `t` | Toggle indirect dependencies |

### Updates Tab

| Key | Action |
|-----|--------|
| `u` | Update selected |
| `U` | Update all |
| `d` | Dry-run preview |
| `R` | Refresh |
| `c` | Toggle conflicts panel focus |

### Registry Tab

| Key | Action |
|-----|--------|
| `/` | Focus search |
| `Enter` | Install selected package |

### Dependencies Tab

| Key | Action |
|-----|--------|
| `g` | Toggle tree/graph view |
| `w` | Show `Pkg.why()` for selected package |
| `Enter` | Expand/collapse tree node |

### Metrics Tab

| Key | Action |
|-----|--------|
| `s` | Switch size/compile view |
| `r` | Run profiling |

## Requirements

- Julia 1.10+
- A terminal with Unicode support (for ⌃/⌅ markers, box drawing, node markers)

## How to Cite

If you use PkgTUI.jl in your work, please cite using the reference given in [CITATION.cff](https://github.com/langestefan/PkgTUI.jl/blob/main/CITATION.cff).

## Contributing

If you want to make contributions of any kind, please first take a look into our [contributing guide directly on GitHub](docs/src/90-contributing.md) or the [contributing page on the website](https://langestefan.github.io/PkgTUI.jl/dev/90-contributing/).

---

### Contributors

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
