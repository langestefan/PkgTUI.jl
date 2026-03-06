module PkgTUI

using Tachikoma
@tachikoma_app
using Match
import Pkg
using TOML
using UUIDs

# Data types and model
include("model.jl")

# Pkg.jl backend wrappers
include("pkg_backend.jl")

# Registry search
include("registry.jl")

# Views
include("views/layout.jl")
include("views/installed.jl")
include("views/updates.jl")
include("views/registry_explorer.jl")
include("views/dependencies.jl")
include("views/conflicts.jl")
include("views/metrics_view.jl")
include("views/triage.jl")
include("views/log_view.jl")

# App orchestration (view, update!, init!, cleanup!)
include("app.jl")

export pkgtui

# ── Pkg App entry point ──────────────────────────────────────────────────────

function (@main)(ARGS)
    project = nothing
    for arg in ARGS
        if arg in ("--help", "-h")
            println("PkgTUI — Terminal UI for Julia package management")
            println()
            println("Usage: pkgtui [options]")
            println()
            println("Options:")
            println("  --project=<path>   Activate a specific Julia project")
            println("  -p=<path>          Short form of --project")
            println("  --help, -h         Show this help message")
            println()
            println("Keybindings:")
            println(
                "  1-6      Switch tabs (Installed, Updates, Registry, Dependencies, Metrics, Log)",
            )
            println("  q/Esc    Quit")
            println("  ?        Show help overlay")
            println("  Ctrl+E   Switch environment")
            println("  l        Toggle log pane")
            return 0
        elseif startswith(arg, "--project=")
            project = arg[length("--project=")+1:end]
        elseif startswith(arg, "-p=")
            project = arg[length("-p=")+1:end]
        end
    end
    pkgtui(; project = project)
    return 0
end

end
