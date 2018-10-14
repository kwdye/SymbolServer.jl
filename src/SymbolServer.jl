module SymbolServer

export SymbolServerProcess
export getstore

using Serialization, Pkg

include("clientprocess/from_static_lint.jl")

mutable struct SymbolServerProcess
    process::Base.Process

    function SymbolServerProcess(;environment=nothing, depot=nothing)
        jl_cmd = joinpath(Sys.BINDIR, Base.julia_exename())
        client_process_script = joinpath(@__DIR__, "clientprocess", "clientprocess_main.jl")

        env_to_use = copy(ENV)

        if depot!==nothing
            if depot==""
                delete!(env_to_use, "JULIA_DEPOT_PATH")
            else
                env_to_use["JULIA_DEPOT_PATH"] = depot
            end
        end

        p = if environment===nothing
            open(Cmd(`$jl_cmd $client_process_script`, env=env_to_use), read=true, write=true)
        else
            open(Cmd(`$jl_cmd --project=$environment $client_process_script`, dir=environment, env=env_to_use), read=true, write=true)
        end
    
        return new(p)
    end
end

function request(server::SymbolServerProcess, message::Symbol, payload)
    serialize(server.process, (message, payload))
    ret_val = deserialize(server.process)
    return ret_val
end

function save_store_to_disc(store, file)
    io = open(file, "w")
    serialize(io, store)
    close(io)
end

function load_store_from_disc(file)
    io = open(file)
    store = deserialize(io)
    close(io)
    return store
end

# Public API

function getstore(server::SymbolServerProcess)
    depot = deepcopy(corepackages)
    storedir = abspath(joinpath(@__DIR__, "..", "store"))
    installed_pkgs_in_env = get_installed_packages_in_env(server)
    all_pkgs_in_env = get_all_packages_in_env(server)

    for (pkg_name, uuid) in installed_pkgs_in_env
        if isfile(joinpath(storedir, "$uuid.jstore"))
            depot[pkg_name] = load_store_from_disc(joinpath(storedir, "$uuid.jstore"))
        else
            load_package(server, (pkg_name => uuid))
            if isfile(joinpath(storedir, "$uuid.jstore"))
                depot[pkg_name] = load_store_from_disc(joinpath(storedir, "$uuid.jstore"))
            end
        end
    end
    for (pkg_name, uuids) in all_pkgs_in_env
        pkg_name in keys(depot) && continue 
        uuid = first(uuids) # will need fix for multiple package versions within an env
        if isfile(joinpath(storedir, "$uuid.jstore"))
            depot[pkg_name] = load_store_from_disc(joinpath(storedir, "$uuid.jstore"))
        else
            # search for uuid within installed_pkgs_in_env dependencies
        end
    end
    
    return depot
end

function Base.kill(s::SymbolServerProcess)
    kill(s.process)
end

function get_installed_packages_in_env(server::SymbolServerProcess)
    status, payload = request(server, :get_installed_packages_in_env, nothing)
    if status == :success
        return payload
    else
        error(payload)
    end
end

function get_all_packages_in_env(server::SymbolServerProcess)
    status, payload = request(server, :get_all_packages_in_env, nothing)
    if status == :success
        return payload
    else
        error(payload)
    end
end

function load_package(server::SymbolServerProcess, pkg)
    status, payload = request(server, :load_package, pkg)
    if status == :success
        return payload
    else
        error(payload)
    end
end

const corepackages = load_core()["packages"]

end # module
