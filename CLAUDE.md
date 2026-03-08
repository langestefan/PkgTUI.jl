# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PkgTUI.jl is a Terminal User Interface (TUI) for Julia package management, built on `Pkg.jl` and the `Tachikoma.jl` TUI framework. It's distributed as a Julia Pkg App (invoked as `pkgtui` from the terminal). The project requires Julia 1.12+.

## Commands

**Run tests:**
```bash
julia --project=test test/runtests.jl
```

**Run a single test item** (using TestItems.jl):
```julia
# In Julia REPL with TestItemRunner loaded:
using TestItemRunner
@run_package_tests filter=ti->contains(ti.name, "my test name") verbose=true
```

**Format code** (must match `.JuliaFormatter.toml`: 4-space indent, 92-char margin):
```bash
julia -e 'using JuliaFormatter; format(".")'
```

**Run pre-commit hooks:**
```bash
pre-commit run --all-files
```

**Install as Pkg App:**
```bash
julia -e 'using Pkg; Pkg.add("PkgTUI"); Pkg.build("PkgTUI")'
```

## Architecture

### Core Layers

1. **Entry point** (`src/PkgTUI.jl`): Defines the module, sets up the `@tachikoma_app` macro, parses CLI args (`--project`, `--help`), and exports `pkgtui`. Uses `@main` for Pkg App invocation.

2. **Data model** (`src/model.jl`): All state structs — `PackageRow`, `UpdateInfo`, `DryRunEntry`/`DryRunDiff`, and `PkgTUIApp` (the top-level app state container).

3. **Pkg backend** (`src/pkg_backend.jl`): Thin wrappers around `Pkg.jl` APIs — listing packages, checking updates, install/remove/pin operations, registry search, profiling, and dry-run diff generation.

4. **App orchestration** (`src/app.jl`): Main event loop, keyboard input routing, tab/environment switching, view lifecycle management. Calls `init!()`, `update!()` on views.

5. **Views** (`src/views/`): Each tab is a separate view file. All views implement `init!()` and `update!()`. Tachikoma widgets (lists, trees, text boxes) are used throughout.

6. **Precompilation** (`src/precompile.jl`): `PrecompileTools.jl` workload to warm up common code paths for fast startup.

### View Components

| File | Tab | Role |
|------|-----|------|
| `views/layout.jl` | All | Tab bar, pane layout, overall chrome |
| `views/installed.jl` | 1 | Browse/add/remove/pin packages |
| `views/updates.jl` | 2 | Available updates with dry-run previews |
| `views/registry_explorer.jl` | 3 | Fuzzy search over 13K+ registry packages |
| `views/dependencies.jl` | 4 | Interactive dependency tree + `Pkg.why()` |
| `views/metrics_view.jl` | 5 | Disk usage and compile-time charts |
| `views/log_view.jl` | 6 | Live log pane with full-screen mode |
| `views/triage.jl` | — | Install failure diagnostics (largest file, 1206 lines) |
| `views/conflicts.jl` | — | Dependency conflict display |

Registry fuzzy matching logic lives in `src/registry.jl`.

### Testing

Tests use `TestItems.jl` — individual tests are `@testitem` blocks, not traditional `@testset`. The runner is configured via `@run_package_tests` in `test/runtests.jl`. Profiling tests are separated into `test/test-profiling.jl`.

## Code Style

- **Formatter**: JuliaFormatter.jl — 4-space indent, 92-character line margin, Unix line endings. Run before committing.
- **Pre-commit**: Enforces formatting, validates TOML/YAML/JSON/CFF, checks markdown links.
- **Coverage target**: 90% (Codecov). CI runs on Ubuntu and macOS against Julia 1.x (latest).
