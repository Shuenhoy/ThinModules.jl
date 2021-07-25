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

end
const ModuleName = Array{Symbol}

struct Context
    root_name::ModuleName
    based::Module
    queue::Queue{Tuple{ModuleName,Expr,String}}
    modules_body::Dict{ModuleName,Expr}
    rev_dependencies::Dict{ModuleName,Set{ModuleName}}
    function Context(root_name::ModuleName, based::Module)
        queue = Queue{Tuple{ModuleName,Expr,String}}()
        modules_body = Dict{ModuleName,Expr}()
        rev_dependencies = Dict{ModuleName,Array{ModuleName}}()
        return new(root_name, based, queue, modules_body, rev_dependencies)
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
    for m in keys(context.modules_body)
        indegree[m] = 0
    end

    for m in values(context.rev_dependencies)
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
    while !isempty(queue)
        m = dequeue!(queue)
        push!(sorts, m)
        if haskey(context.rev_dependencies, m)
            for d in context.rev_dependencies[m]
                indegree[d] -= 1
                if indegree[d] == 0
                    enqueue!(queue, d)
                end
            end
        end
    end
    if !isempty(queue)
        error("Cyclic dependencies")
    end
    return sorts
end

function create_module!(base::Module, name::Symbol)
    return Base.eval(base, Expr(:module, true, name, Expr(:block)))
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

                analysis_block!(context, minclude(to_include_path), module_name, new_args, to_include_path)
            elseif isimport(current)
                for imp in current.args
                    nmodule_name = find_module(context, resolve_import(imp, module_name))
                    if isprefix(context.root_name, nmodule_name)
                        if !haskey(context.rev_dependencies, module_name)
                            context.rev_dependencies[nmodule_name] = Set{ModuleName}()
                        end
                        push!(context.rev_dependencies[nmodule_name], module_name)
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
    analysis_block!(context, def, name, new_args, filename)

    new_block = Expr(:block, new_args...)
    return new_block
end
end