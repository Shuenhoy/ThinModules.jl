module ThinModules
using DataStructures

export @thinmod

macro thinmod(module_def)
    if __module__ == Base.__toplevel__
        modname = [module_def.args[2]]
    else
        basedname = find_based(__module__)

        modname = [basedname..., module_def.args[2]]
    end
    context = Context(modname, __module__)

    enqueue!(context.queue, (modname, module_def.args[3], String(__source__.file::Symbol)))
    while !isempty(context.queue)
        (mod, defs, file) = dequeue!(context.queue)
        context.modules_body[mod] = analysis_module!(context, defs, mod, file)
    end

    sorts = topological_sort(context)

    modules = create_modules_hierarchy!(context)
    for m in sorts
        Base.eval(modules[m], context.modules_body[m])
    end
    for (m, fs) in context.file_dependencies
        for f in fs
            @eval modules[m] Base.include_dependency($f)
        end
    end
end
const ModuleName = Array{Symbol}

struct Context
    root_name::ModuleName
    based::Module
    queue::Queue{Tuple{ModuleName,Expr,String}}
    modules_body::Dict{ModuleName,Expr}
    dependencies::Dict{ModuleName,Set{ModuleName}}
    file_dependencies::Dict{ModuleName,Set{String}}
    function Context(root_name::ModuleName, based::Module)
        queue = Queue{Tuple{ModuleName,Expr,String}}()
        modules_body = Dict{ModuleName,Expr}()
        dependencies = Dict{ModuleName,Array{ModuleName}}()
        file_dependencies = Dict{ModuleName,Array{String}}()
        return new(root_name, based, queue, modules_body, dependencies, file_dependencies)
    end
end

function minclude(path::String)
    return Meta.parseall(read(path, String); filename=path)
end

function find_based(m::Module)
    name = [Base.nameof(m)]
    while Base.nameof(Base.parentmodule(m)) != Base.nameof(m)
        push!(name, Base.nameof(Base.parentmodule(m)))
        m = Base.parentmodule(m)
    end
    reverse!(name)
    return name
end

function topological_sort(context::Context)
    indegree = Dict{ModuleName,Int}()
    rev_deps = rev_dependencies(context)
    for m in keys(context.modules_body)
        indegree[m] = 0
    end

    for m in values(rev_deps)
        for d in m
            indegree[d] += 1
        end
    end
    queue = Queue{ModuleName}()
    sorts = ModuleName[]
    for m in keys(context.modules_body)
        if indegree[m] == 0
            enqueue!(queue, m)
        end
    end

    counts = 0
    while !isempty(queue)
        m = dequeue!(queue)
        counts += 1
        push!(sorts, m)
        if haskey(rev_deps, m)
            for d in rev_deps[m]
                indegree[d] -= 1
                if indegree[d] == 0
                    enqueue!(queue, d)
                end
            end
        end
    end
    if counts != length(keys(context.modules_body))
        error("Cyclic dependencies")
    end
    return sorts
end

function create_module!(base::Module, name::Symbol)
    return @eval base module $name end
end

function create_modules_hierarchy!(context::Context)
    mods = Dict{ModuleName,Module}()
    to_create = sort!(collect(keys(context.modules_body)), by=length)
    mods[to_create[1]] = create_module!(context.based, to_create[1][end])
    for mod in to_create[2:end]
        based = mods[mod[1:end - 1]]
        mods[mod] = create_module!(based, mod[end])
    end
    return mods
end
# >---------------------------- import ---------------------------
function resolve_import(expr::Expr, base::ModuleName)
    if expr.head == :(:) || expr.head == :as
        path = expr.args[1].args
    elseif expr.head == :(.)
        path = expr.args
    else
        error("Invalid import expression")
    end
    if path[1] != :(.)
        return convert.(Symbol, path)
    else
        count = 0
        i = 2
        while path[i] == :(.)
            count += 1
            i += 1
        end
        return [base[1:end - count]..., path[count + 2:end]...]
    end
end

function isimport(expr::Expr)
    return expr.head == :using || expr.head == :import
end

function isprefix(prefix::ModuleName, name::ModuleName)
    return length(prefix) <= length(name) && prefix == name[1:length(prefix)]
end

function find_module(context::Context, mod::ModuleName)
    # This is for `import A.x as y`
    # If we find something is not an existing module, we
    # will find its nearest parent module and add it.

    seen = keys(context.modules_body)
    for i in length(mod):-1:1
        if mod[1:i] ∈ seen
            return mod[1:i]
        end
    end
    error("No such module exists.")
end

function rev_dependencies(context::Context)
    rev_deps = Dict{ModuleName,Set{ModuleName}}()
    for m in keys(context.modules_body)
        rev_deps[m] = Set{ModuleName}()
    end
    for (m, deps) in context.dependencies
        for d in deps
            push!(rev_deps[find_module(context, d)], m)
        end
    end
    return rev_deps
end

# <---------------------------- import ---------------------------


function analysis_block!(context::Context, block::Expr, module_name::ModuleName, new_args::Array{Any}, filename::String)
    i = 1
    while i <= length(block.args)
        current = block.args[i]
        if current isa LineNumberNode
            push!(new_args, current)
        elseif current isa Expr
            if current.head == :call && current.args[1] == :include
                to_include_path = abspath(joinpath(dirname(filename), current.args[2]))
                push!(context.file_dependencies[module_name], to_include_path)
                analysis_block!(context, minclude(to_include_path), module_name, new_args, to_include_path)
            elseif isimport(current)
                for imp in current.args
                    nmodule_name = resolve_import(imp, module_name)
                    if isprefix(context.root_name, nmodule_name)
                        push!(context.dependencies[module_name], nmodule_name)
                    end
                end
                
                push!(new_args, current)
            elseif current.head == :module
                enqueue!(context.queue, ([module_name..., current.args[2]], current.args[3], filename))
            else
                push!(new_args, current)
            end
        end
        i += 1
    end
end

function analysis_module!(context::Context, def::Expr, name::ModuleName, filename::String)
    i = 1
    new_args = Union{Any}[]
    context.file_dependencies[name] = Set{String}()
    context.dependencies[name] = Set{ModuleName}()

    analysis_block!(context, def, name, new_args, filename)

    new_block = Expr(:block, new_args...)
    return new_block
end
end