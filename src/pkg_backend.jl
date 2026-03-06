"""
    Pkg.jl backend wrappers for PkgTUI.

All functions are designed to be called inside `spawn_task!` — they accept an
`IOBuffer` for capturing Pkg output and return plain data structures. Never
mutate the model directly from these functions.
"""

import Pkg
using UUIDs
using TOML

# ──────────────────────────────────────────────────────────────────────────────
# Project / Environment
# ──────────────────────────────────────────────────────────────────────────────

"""
    fetch_project_info() → ProjectInfo

Return information about the currently active project/environment.
"""
function fetch_project_info()::ProjectInfo
    proj = Pkg.project()
    info = ProjectInfo(
        name = proj.name,
        uuid = proj.uuid,
        version = proj.version === nothing ? nothing : string(proj.version),
        is_package = proj.ispackage,
        path = proj.path,
        dep_count = length(proj.dependencies),
    )

    # Detect workspace
    if proj.path !== nothing
        project_dir = dirname(proj.path)
        project_toml = proj.path
        if isfile(project_toml)
            toml = TOML.parsefile(project_toml)
            if haskey(toml, "workspace")
                info.is_workspace = true
                ws = toml["workspace"]
                if haskey(ws, "projects") && ws["projects"] isa Vector
                    info.workspace_projects = string.(ws["projects"])
                end
            end
        end
    end

    return info
end

"""
    fetch_environment_list() → Vector{String}

Return a list of known environment paths (load path + workspace projects).
"""
function fetch_environment_list()::Vector{String}
    envs = String[]

    # Current load path entries
    for p in Base.load_path()
        if p != "@" && p != "@stdlib"
            expanded = Base.load_path_expand(p)
            if expanded !== nothing && isdir(dirname(expanded))
                push!(envs, expanded)
            end
        end
    end

    # Active project
    proj = Pkg.project()
    if proj.path !== nothing
        push!(envs, proj.path)
    end

    return unique(envs)
end

# ──────────────────────────────────────────────────────────────────────────────
# Installed Packages
# ──────────────────────────────────────────────────────────────────────────────

"""
    fetch_installed(io::IOBuffer) → Vector{PackageRow}

Fetch all installed packages from the active environment using `Pkg.dependencies()`.
"""
function fetch_installed(io::IOBuffer)::Vector{PackageRow}
    deps = Pkg.dependencies()
    rows = PackageRow[]

    for (uuid, info) in deps
        row = PackageRow(
            name = info.name,
            uuid = uuid,
            version = info.version === nothing ? nothing : string(info.version),
            is_direct_dep = info.is_direct_dep,
            is_pinned = info.is_pinned,
            is_tracking_path = info.is_tracking_path,
            is_tracking_repo = info.is_tracking_repo,
            is_tracking_registry = info.is_tracking_registry,
            source = info.source,
            dependencies = collect(values(info.dependencies)),
        )
        push!(rows, row)
    end

    sort!(rows; by = r -> (r.is_direct_dep ? 0 : 1, lowercase(r.name)))
    return rows
end

# ──────────────────────────────────────────────────────────────────────────────
# Add / Remove / Update
# ──────────────────────────────────────────────────────────────────────────────

"""
    add_package(name::String, io::IOBuffer; version::Union{String, Nothing}=nothing) → String

Add a package by name, optionally at a specific version. Returns a status message.
"""
function add_package(
    name::String,
    io::IOBuffer;
    version::Union{String,Nothing} = nothing,
)::String
    try
        if version !== nothing
            Pkg.add(; name = name, version = version, io = io)
        else
            Pkg.add(name; io = io)
        end
        ver_str = version !== nothing ? "@$version" : ""
        return "Package '$name'$ver_str added successfully."
    catch e
        return "Error in add: $(sprint(showerror, e))"
    end
end

"""
    remove_package(name::String, io::IOBuffer) → String

Remove a package by name. Returns a status message.
"""
function remove_package(name::String, io::IOBuffer)::String
    Pkg.rm(name; io = io)
    return "Package '$name' removed successfully."
end

"""
    update_package(name::String, io::IOBuffer) → String

Update a specific package. Returns a status message.
"""
function update_package(name::String, io::IOBuffer)::String
    Pkg.update(name; io = io)
    return "Package '$name' updated successfully."
end

"""
    update_all(io::IOBuffer) → String

Update all packages. Returns a status message.
"""
function update_all(io::IOBuffer)::String
    Pkg.update(; io = io)
    return "All packages updated."
end

"""
    pin_package(name::String, io::IOBuffer; version::Union{VersionNumber, Nothing}=nothing) → String

Pin a package to its current version, or to a specific version if provided.
"""
function pin_package(
    name::String,
    io::IOBuffer;
    version::Union{VersionNumber,Nothing} = nothing,
)::String
    if version !== nothing
        Pkg.pin(; name = name, version = version, io = io)
        return "Package '$name' pinned to v$version."
    else
        Pkg.pin(name; io = io)
        return "Package '$name' pinned."
    end
end

"""
    free_package(name::String, io::IOBuffer) → String

Free a pinned package or stop tracking a path.
"""
function free_package(name::String, io::IOBuffer)::String
    Pkg.free(name; io = io)
    return "Package '$name' freed."
end

# ──────────────────────────────────────────────────────────────────────────────
# Update Status & Dry Run
# ──────────────────────────────────────────────────────────────────────────────

"""
    fetch_outdated(io::IOBuffer) → (Vector{UpdateInfo}, String)

Capture `Pkg.status(; outdated=true)` output and parse it to find packages
that have updates available. Returns parsed info and raw output.
"""
function fetch_outdated(io::IOBuffer)::Tuple{Vector{UpdateInfo},String}
    buf = IOBuffer()
    Pkg.status(; outdated = true, mode = Pkg.PKGMODE_MANIFEST, io = buf)
    raw = String(take!(buf))

    updates = UpdateInfo[]
    for line in split(raw, '\n')
        stripped = strip(line)
        isempty(stripped) && continue

        # Parse lines like:
        #  ⌃ [uuid] PackageName v1.0.0 [<v2.0.0], (<v3.0.0)
        #  ⌅ [uuid] PackageName v1.0.0 (<v2.0.0) [compat]
        #  ⌅ [uuid] PackageName v1.0.0 (<v2.0.0): BlockerPkg

        can_update = true
        if startswith(stripped, '⌃')
            can_update = true
        elseif startswith(stripped, '⌅')
            can_update = false
        else
            continue
        end

        # Extract package name. Pattern: marker [uuid] Name vX.Y.Z ...
        m = match(r"[⌃⌅]\s+\[[\da-f]+\]\s+(\S+)\s+v(\S+)\s*(.*)", stripped)
        if m === nothing
            # Try without UUID: marker Name vX.Y.Z ...
            m = match(r"[⌃⌅]\s+(\S+)\s+v(\S+)\s*(.*)", stripped)
        end
        m === nothing && continue

        name = m.captures[1]
        current_ver = m.captures[2]
        rest = m.captures[3] !== nothing ? strip(m.captures[3]) : ""

        latest_compat = nothing
        latest_avail = nothing
        blocker = nothing

        # Parse [<vX.Y.Z] — latest compatible
        mc = match(r"\[<v([\d.]+)\]", rest)
        if mc !== nothing
            latest_compat = mc.captures[1]
        end

        # Parse (<vX.Y.Z) — latest available
        ma = match(r"\(<v([\d.]+)\)", rest)
        if ma !== nothing
            latest_avail = ma.captures[1]
        end

        # Parse : BlockerName — what's blocking
        mb = match(r":\s+(\S+)", rest)
        if mb !== nothing
            blocker = mb.captures[1]
        end

        # [compat] means project compat is the blocker
        if occursin("[compat]", rest)
            blocker = something(blocker, "[compat]")
        end

        push!(
            updates,
            UpdateInfo(
                name = name,
                current_version = current_ver,
                latest_compatible = latest_compat,
                latest_available = latest_avail,
                blocker = blocker,
                can_update = can_update,
            ),
        )
    end

    return (updates, raw)
end

"""
    dry_run_update(io::IOBuffer) → String

Show what `Pkg.update` would change without actually updating.
Captures the status diff.
"""
function dry_run_update(io::IOBuffer)::String
    buf = IOBuffer()
    Pkg.status(; outdated = true, mode = Pkg.PKGMODE_PROJECT, io = buf)
    return String(take!(buf))
end

# ──────────────────────────────────────────────────────────────────────────────
# Why (dependency path)
# ──────────────────────────────────────────────────────────────────────────────

"""
    why_package(name::String, io::IOBuffer) → String

Call `Pkg.why(name)` and return the captured output showing the dependency path.
"""
function why_package(name::String, io::IOBuffer)::String
    buf = IOBuffer()
    Pkg.why(name; io = buf)
    return String(take!(buf))
end

# ──────────────────────────────────────────────────────────────────────────────
# Precompile profiling
# ──────────────────────────────────────────────────────────────────────────────

"""
    run_precompile_profiling(pkg_names::Vector{String}) → Vector{Tuple{String, Float64}}

Measure **load times** for the given packages by loading each in a fresh
Julia subprocess.  Returns [(name, seconds), ...] sorted by time descending.

When `pkg_names` is empty, falls back to direct project dependencies.
"""
function run_precompile_profiling(pkg_names::Vector{String})::Vector{Tuple{String,Float64}}
    proj = Pkg.project()
    proj_dir = proj.path !== nothing ? dirname(proj.path) : nothing
    proj_dir === nothing && return Tuple{String,Float64}[]

    names = if isempty(pkg_names)
        collect(keys(proj.dependencies))
    else
        pkg_names
    end
    isempty(names) && return Tuple{String,Float64}[]

    timings = _measure_load_times(names, proj_dir)
    sort!(timings; by = last, rev = true)
    return timings
end

"""
    _measure_load_times(names, proj_dir) → Vector{Tuple{String, Float64}}

Spawn a separate Julia subprocess **per package** so that shared transitive
dependencies don't deflate subsequent measurements.  Runs up to 8 subprocesses
in parallel via `asyncmap` for speed.
"""
function _measure_load_times(names::Vector{String}, proj_dir::AbstractString)::Vector{Tuple{String,Float64}}
    # Each subprocess measures a single package in isolation.
    # Use a unique marker prefix so we can filter out noisy Pkg/CondaPkg output.
    script = raw"""
    try
        sym = Symbol(ARGS[1])
        t = @elapsed Base.require(Main, sym)
        println("__PKGTUI_TIMING__\t", ARGS[1], "\t", t)
    catch e
        println("__PKGTUI_TIMING__\t", ARGS[1], "\t", 0.0)
    end
    """

    julia_cmd = Base.julia_cmd()

    # Launch one subprocess per package, up to 8 concurrently.
    results = asyncmap(names; ntasks = min(8, length(names))) do name
        try
            cmd = `$julia_cmd --project=$proj_dir --startup-file=no -e $script -- $name`
            output = read(cmd, String)
            # Find our marker line in the (possibly noisy) output
            for raw_line in split(output, '\n')
                line = strip(String(raw_line))
                if startswith(line, "__PKGTUI_TIMING__\t")
                    parts = split(line, '\t')
                    if length(parts) == 3
                        secs = tryparse(Float64, parts[3])
                        secs !== nothing && return (String(parts[2]), secs)
                    end
                end
            end
        catch
            # Subprocess failed for this package — skip
        end
        return nothing
    end

    timings = Tuple{String,Float64}[]
    for r in results
        r !== nothing && push!(timings, r)
    end

    return timings
end

# ──────────────────────────────────────────────────────────────────────────────
# Disk size measurement
# ──────────────────────────────────────────────────────────────────────────────

"""
    measure_disk_sizes(packages::Vector{PackageRow}) → Vector{PackageMetrics}

Measure the on-disk size of each installed package by walking its source directory.
"""
function measure_disk_sizes(packages::Vector{PackageRow})::Vector{PackageMetrics}
    metrics = PackageMetrics[]
    for pkg in packages
        size_bytes = Int64(0)
        if pkg.source !== nothing && isdir(pkg.source)
            try
                for (root, dirs, files) in walkdir(pkg.source)
                    for f in files
                        fp = joinpath(root, f)
                        if isfile(fp)
                            size_bytes += filesize(fp)
                        end
                    end
                end
            catch
                # Permission errors etc — just use 0
            end
        end
        push!(
            metrics,
            PackageMetrics(
                name = pkg.name,
                disk_size_bytes = size_bytes,
                is_direct = pkg.is_direct_dep,
            ),
        )
    end
    sort!(metrics; by = m -> m.disk_size_bytes, rev = true)
    return metrics
end

# ──────────────────────────────────────────────────────────────────────────────
# Dependency graph construction
# ──────────────────────────────────────────────────────────────────────────────

"""
    build_dependency_tree(packages::Vector{PackageRow}) → TreeNode

Build a TreeView-compatible tree from installed packages. Direct dependencies
are root nodes; their transitive deps become children.
"""
function build_dependency_tree(packages::Vector{PackageRow})::TreeNode
    pkg_map = Dict(p.uuid => p for p in packages)

    function make_node(uuid::UUID, visited::Set{UUID})::Union{TreeNode,Nothing}
        uuid in visited && return nothing
        !haskey(pkg_map, uuid) && return nothing
        push!(visited, uuid)
        pkg = pkg_map[uuid]
        label = pkg.version !== nothing ? "$(pkg.name) v$(pkg.version)" : pkg.name

        children = TreeNode[]
        for dep_uuid in pkg.dependencies
            child = make_node(dep_uuid, copy(visited))
            child !== nothing && push!(children, child)
        end
        sort!(children; by = n -> n.label)
        return TreeNode(label, children)
    end

    # Root nodes are direct dependencies
    direct = filter(p -> p.is_direct_dep, packages)
    sort!(direct; by = p -> lowercase(p.name))

    root_children = TreeNode[]
    for pkg in direct
        node = make_node(pkg.uuid, Set{UUID}())
        node !== nothing && push!(root_children, node)
    end

    return TreeNode("Dependencies", root_children)
end

"""
    build_graph_layout(packages::Vector{PackageRow}) → (Vector{GraphNode}, Vector{GraphEdge})

Create nodes and edges for force-directed graph visualization.
"""
function build_graph_layout(
    packages::Vector{PackageRow},
)::Tuple{Vector{GraphNode},Vector{GraphEdge}}
    nodes = GraphNode[]
    edges = GraphEdge[]
    uuid_set = Set(p.uuid for p in packages)

    # Create nodes with random initial positions
    for (i, pkg) in enumerate(packages)
        angle = 2π * i / length(packages)
        r = 30.0 + 10.0 * rand()
        push!(
            nodes,
            GraphNode(
                name = pkg.name,
                uuid = pkg.uuid,
                x = 50.0 + r * cos(angle),
                y = 20.0 + r * sin(angle) * 0.5,
                is_direct = pkg.is_direct_dep,
            ),
        )
    end

    # Create edges
    for pkg in packages
        for dep_uuid in pkg.dependencies
            if dep_uuid in uuid_set
                push!(edges, GraphEdge(from = pkg.uuid, to = dep_uuid))
            end
        end
    end

    return (nodes, edges)
end

"""
    step_force_layout!(nodes::Vector{GraphNode}, edges::Vector{GraphEdge};
                       width=100.0, height=40.0)

One iteration of force-directed graph layout.
"""
function step_force_layout!(
    nodes::Vector{GraphNode},
    edges::Vector{GraphEdge};
    width::Float64 = 100.0,
    height::Float64 = 40.0,
)
    n = length(nodes)
    n == 0 && return

    uuid_idx = Dict(node.uuid => i for (i, node) in enumerate(nodes))

    # Repulsive forces between all node pairs
    repulsion = 500.0
    for i = 1:n
        for j = (i+1):n
            dx = nodes[i].x - nodes[j].x
            dy = nodes[i].y - nodes[j].y
            dist = max(sqrt(dx^2 + dy^2), 0.1)
            force = repulsion / dist^2
            fx = force * dx / dist
            fy = force * dy / dist
            nodes[i].vx += fx
            nodes[i].vy += fy
            nodes[j].vx -= fx
            nodes[j].vy -= fy
        end
    end

    # Attractive forces along edges
    attraction = 0.01
    for edge in edges
        i = get(uuid_idx, edge.from, 0)
        j = get(uuid_idx, edge.to, 0)
        (i == 0 || j == 0) && continue
        dx = nodes[j].x - nodes[i].x
        dy = nodes[j].y - nodes[i].y
        dist = max(sqrt(dx^2 + dy^2), 0.1)
        force = attraction * dist
        fx = force * dx / dist
        fy = force * dy / dist
        nodes[i].vx += fx
        nodes[i].vy += fy
        nodes[j].vx -= fx
        nodes[j].vy -= fy
    end

    # Center gravity
    gravity = 0.05
    cx, cy = width / 2, height / 2
    for node in nodes
        node.vx += gravity * (cx - node.x)
        node.vy += gravity * (cy - node.y)
    end

    # Apply velocities with damping
    damping = 0.85
    for node in nodes
        node.vx *= damping
        node.vy *= damping
        node.x = clamp(node.x + node.vx, 2.0, width - 2.0)
        node.y = clamp(node.y + node.vy, 2.0, height - 2.0)
    end
end
