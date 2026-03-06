"""
    Registry search backend for PkgTUI.

Provides functions to search the Julia General registry for packages.
Uses `Pkg.Registry` public API.
"""

import Pkg
using UUIDs

"""
    build_registry_index() → Vector{RegistryPackage}

Use `Pkg.Registry.reachable_registries()` to build an index of available packages.
This is an expensive operation — call once and cache the result.
"""
function build_registry_index()::Vector{RegistryPackage}
    index = RegistryPackage[]

    for reg in Pkg.Registry.reachable_registries()
        for (uuid, entry) in reg.pkgs
            pkg = RegistryPackage(name = entry.name, uuid = uuid)

            # Load detailed info (repo, versions) lazily
            try
                info = Pkg.Registry.registry_info(entry)
                pkg.repo = info.repo

                vers = info.version_info
                if !isempty(vers)
                    latest = maximum(keys(vers))
                    pkg.latest_version = string(latest)
                end
            catch
                # If registry_info fails, we still have name + uuid
            end

            push!(index, pkg)
        end
    end

    sort!(index; by = p -> lowercase(p.name))
    return index
end

"""
    search_registry(index::Vector{RegistryPackage}, query::String;
                    max_results::Int=100) → Vector{RegistryPackage}

Search the registry index by fuzzy substring match on package name.
Returns at most `max_results` matches, sorted by relevance.
"""
function search_registry(
    index::Vector{RegistryPackage},
    query::AbstractString;
    max_results::Int = 100,
)::Vector{RegistryPackage}
    isempty(query) && return first(index, min(max_results, length(index)))

    q = lowercase(query)
    results = Tuple{RegistryPackage,Int}[]

    for pkg in index
        name_lower = lowercase(pkg.name)

        # Exact match → highest priority
        if name_lower == q
            push!(results, (pkg, 0))
            # Starts with query → high priority
        elseif startswith(name_lower, q)
            push!(results, (pkg, 1))
            # Contains query → medium priority
        elseif occursin(q, name_lower)
            push!(results, (pkg, 2))
            # Fuzzy: check if all query chars appear in order
        elseif fuzzy_match(name_lower, q)
            push!(results, (pkg, 3))
        end
    end

    sort!(results; by = r -> (r[2], lowercase(r[1].name)))
    return [r[1] for r in first(results, max_results)]
end

"""
    fuzzy_match(text, query) → Bool

Check if all characters from `query` appear in `text` in order.
"""
function fuzzy_match(text::AbstractString, query::AbstractString)::Bool
    ti = 1
    for qc in query
        found = false
        while ti <= length(text)
            if text[ti] == qc
                ti += 1
                found = true
                break
            end
            ti += 1
        end
        !found && return false
    end
    return true
end

"""
    fetch_package_versions(pkg_name::String) → Vector{String}

Look up all available versions for a package from reachable registries.
Returns version strings sorted in descending order (newest first).
"""
function fetch_package_versions(pkg_name::String)::Vector{String}
    for reg in Pkg.Registry.reachable_registries()
        for (_, entry) in reg.pkgs
            if entry.name == pkg_name
                try
                    info = Pkg.Registry.registry_info(entry)
                    vers = info.version_info
                    if !isempty(vers)
                        return [string(v) for v in sort(collect(keys(vers)); rev = true)]
                    end
                catch
                end
            end
        end
    end
    return String[]
end
