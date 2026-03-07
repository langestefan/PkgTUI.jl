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
    dry_run_update(io::IOBuffer) → DryRunDiff

Simulate `Pkg.update` in a temporary copy of the current environment
and return a structured diff of manifest changes.
"""
function dry_run_update(io::IOBuffer)::DryRunDiff
    ctx = Pkg.Types.Context()
    proj_dir = dirname(ctx.env.project_file)
    project_file = ctx.env.project_file
    manifest_file = ctx.env.manifest_file

    if !isfile(project_file)
        return DryRunDiff(error = "No Project.toml found")
    end

    # Parse the old manifest for version comparison
    old_versions = Dict{String,String}()
    if isfile(manifest_file)
        old_manifest = TOML.parsefile(manifest_file)
        # Manifest format: julia_version header + deps section (or flat)
        deps = get(old_manifest, "deps", old_manifest)
        for (name, entries) in deps
            entries isa Vector || continue
            for entry in entries
                entry isa Dict || continue
                if haskey(entry, "version")
                    old_versions[name] = string(entry["version"])
                end
            end
        end
    end

    entries = DryRunEntry[]
    try
        mktempdir() do tmpdir
            # Copy project and manifest files
            cp(project_file, joinpath(tmpdir, "Project.toml"))
            if isfile(manifest_file)
                cp(manifest_file, joinpath(tmpdir, "Manifest.toml"))
            end

            # Activate temp env, resolve & update
            Pkg.activate(tmpdir; io = io)
            try
                Pkg.update(; io = io)

                # Parse the new manifest
                new_manifest_file = joinpath(tmpdir, "Manifest.toml")
                new_versions = Dict{String,String}()
                if isfile(new_manifest_file)
                    new_manifest = TOML.parsefile(new_manifest_file)
                    new_deps = get(new_manifest, "deps", new_manifest)
                    for (name, ents) in new_deps
                        ents isa Vector || continue
                        for entry in ents
                            entry isa Dict || continue
                            if haskey(entry, "version")
                                new_versions[name] = string(entry["version"])
                            end
                        end
                    end
                end

                # Compute diff
                all_names = sort(collect(union(keys(old_versions), keys(new_versions))))
                for name in all_names
                    has_old = haskey(old_versions, name)
                    has_new = haskey(new_versions, name)
                    if has_old && has_new
                        ov = old_versions[name]
                        nv = new_versions[name]
                        if ov != nv
                            kind =
                                VersionNumber(nv) > VersionNumber(ov) ? :upgraded :
                                :downgraded
                            push!(
                                entries,
                                DryRunEntry(
                                    name = name,
                                    kind = kind,
                                    old_version = ov,
                                    new_version = nv,
                                ),
                            )
                        end
                    elseif has_new && !has_old
                        push!(
                            entries,
                            DryRunEntry(
                                name = name,
                                kind = :added,
                                new_version = new_versions[name],
                            ),
                        )
                    elseif has_old && !has_new
                        push!(
                            entries,
                            DryRunEntry(
                                name = name,
                                kind = :removed,
                                old_version = old_versions[name],
                            ),
                        )
                    end
                end
            finally
                # Re-activate original environment
                Pkg.activate(proj_dir; io = io)
            end
        end
    catch e
        return DryRunDiff(error = sprint(showerror, e))
    end

    return DryRunDiff(entries = entries)
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
    run_precompile_profiling(proj_dir, dep_names) → Vector{Tuple{String, Float64}}

Measure **load times** for each direct project dependency by loading it
in a fresh Julia subprocess.  Returns [(name, seconds), ...] sorted by
time descending.

Only direct dependencies are timed — transitive deps are loaded
naturally as part of loading the direct dep, which is the user-relevant
metric.

**Important:** `Pkg.project()` must be called on the *main thread* and
the results passed in here, because this function typically runs inside
a `spawn_task!` where the Pkg project state may not be available.
"""
function run_precompile_profiling(
    proj_dir::AbstractString,
    dep_names::Vector{String},
)::Vector{Tuple{String,Float64}}
    isempty(dep_names) && return Tuple{String,Float64}[]

    timings = _measure_load_times(dep_names, proj_dir)
    sort!(timings; by = last, rev = true)
    return timings
end

"""
    _measure_load_times(names, proj_dir) → Vector{Tuple{String, Float64}}

Spawn a separate Julia subprocess **per package** so that shared transitive
dependencies don't deflate subsequent measurements.  Runs up to 8 subprocesses
in parallel via `asyncmap` for speed.
"""
function _measure_load_times(
    names::Vector{String},
    proj_dir::AbstractString,
)::Vector{Tuple{String,Float64}}
    # Each subprocess measures a single package in isolation.
    # Use a unique marker prefix so we can filter out noisy Pkg/CondaPkg output.
    # Use -1.0 as sentinel for packages that fail to load (to distinguish from
    # "not measured" which stays at the default 0.0).
    script = raw"""
    try
        sym = Symbol(ARGS[1])
        t = @elapsed Base.require(Main, sym)
        println("__PKGTUI_TIMING__\t", ARGS[1], "\t", t)
    catch e
        println("__PKGTUI_TIMING__\t", ARGS[1], "\t", -1.0)
    end
    """

    julia_cmd = Base.julia_cmd()

    # Build a clean environment for subprocesses:
    # CRITICAL: remove JULIA_LOAD_PATH — when PkgTUI runs as a Pkg App or
    # under Pkg.test(), the parent sets JULIA_LOAD_PATH to a restricted value
    # that omits @stdlib.  The subprocess inherits this, causing
    # `Base.require` to fail for packages that ARE in the project manifest.
    # By clearing it, the subprocess uses the default load path
    # (@, @v#.#, @stdlib) with --project= correctly setting @.
    clean_env = Dict(k => v for (k, v) in ENV if k != "JULIA_LOAD_PATH")

    # Launch one subprocess per package, up to 8 concurrently.
    # CRITICAL: redirect stderr to devnull — without this, subprocess stderr
    # (CondaPkg messages, precompilation output, deprecation warnings) fills
    # the pipe buffer (~64KB) and the subprocess deadlocks.  The parent only
    # reads stdout via `read(cmd, String)`, so stderr is never drained.
    results = asyncmap(names; ntasks = min(8, length(names))) do name
        try
            raw_cmd = setenv(
                `$julia_cmd --project=$proj_dir --startup-file=no -e $script -- $name`,
                clean_env,
            )
            cmd = pipeline(raw_cmd; stderr = devnull)
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
            # Subprocess crashed (OOM, segfault, etc.) — skip
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
