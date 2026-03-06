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

# App orchestration (view, update!, init!, cleanup!)
include("app.jl")

export pkgtui

# ── Pkg App entry point ──────────────────────────────────────────────────────

function (@main)(ARGS)
    project = nothing
    for arg in ARGS
        if startswith(arg, "--project=")
            project = arg[length("--project=")+1:end]
        elseif startswith(arg, "-p=")
            project = arg[length("-p=")+1:end]
        end
    end
    pkgtui(; project=project)
    return 0
end

end
