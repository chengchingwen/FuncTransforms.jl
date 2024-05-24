abstract type FuncArgs end
FuncArgs(name::Symbol) = NA(name)
FuncArgs(arg::FuncArgs) = arg
struct NA <: FuncArgs
    name::Symbol
    NA(name; gen = true) = new(gen ? gensym(name) : name)
end
struct FA <: FuncArgs
    name::Symbol
    slotnumber::Int
    FA(name, slotnumber; gen = true) = new(gen ? gensym(name) : name, slotnumber)
end
struct VA <: FuncArgs
    name::Symbol
    drop::Int
    VA(name, drop; gen = true) = new(gen ? gensym(name) : name, drop)
end

struct FuncTransform
    # old info
    meth::Method
    inst::MethodInstance
    ci::CodeInfo
    # transform
    fargs::Vector{FuncArgs}
    fi::FuncInfo
    function FuncTransform(meth::Method, inst::MethodInstance, ci::CodeInfo, fargs = nothing)
        if isnothing(fargs)
            fargs = FuncArgs[FA(name, i) for (i, name) in zip(1:meth.nargs, ci.slotnames)]
        end
        nva = count(arg->arg isa VA, fargs)
        if nva == 1
            !isa(last(fargs), VA) && error("Vararg must be the last argument")
            drop = last(fargs).drop
            any(arg->arg isa FA && arg.slotnumber > drop, fargs) && error("Argument $(arg.name) is reassigned but not dropped")
        elseif nva > 1
            error("can only has 1 Vararg")
        end
        fi = FuncInfo(meth, ci)
        ft = new(meth, inst, ci, map(FuncArgs, fargs), fi)
        updateargs!(ft)
        return ft
    end
end
function FuncTransform(
    @nospecialize(fsig), world, fargs = nothing;
    caller::Union{MethodInstance, Nothing} = nothing,
    method_tables::Union{Nothing, MethodTable, Vector{MethodTable}} = nothing
)
    match = method_by_ftype(fsig, method_tables, world)
    meth = match.method
    inst = Core.Compiler.specialize_method(match)
    ci = get_codeinfo(inst, world)
    Meta.partially_inline!(ci.code, Any[], meth.sig, Any[match.sparams...], 0, 0, :propagate)
    add_backedge!(caller, inst)
    return FuncTransform(meth, inst, ci, fargs)
end

function updateargs!(ft::FuncTransform)
    unseen = BitSet(ft.fi.pargs)
    hasva(ft.fi) && push!(unseen, getva(ft.fi).id)
    for (i, arg) in enumerate(ft.fargs)
        updatearg!(ft, arg, i, unseen)
    end
    @assert isempty(unseen) """arguments [$(join((first(ft.fi.args[i]) for i in unseen), ", "))] not handled."""
    return ft
end
function updatearg!(ft::FuncTransform, arg::NA, i, unseen)
    addparg!(ft.fi, arg.name, i)
    return unseen
end
function updatearg!(ft::FuncTransform, arg::FA, i, unseen)
    id = arg.slotnumber
    if getva(ft.fi).id != id
        deleteparg!(ft.fi, id)
        insertparg!(ft.fi, id, i)
    end
    renamearg!(ft.fi, id, arg.name)
    delete!(unseen, id)
    return unseen
end
function updatearg!(ft::FuncTransform, arg::VA, i, unseen)
    va = getva(ft.fi).id
    !iszero(va) && delete!(unseen, va)
    newva = addva!(ft.fi, arg.name).id
    index = 1
    for id = 1:ft.meth.nargs
        if id == va
            # the number of element the original Vararg should get
            vasize = length(ft.inst.specTypes.parameters) - ft.meth.nargs
            arg2var!(ft.fi, id)
            repackva!(ft.fi, id, newva, index:index+vasize)
        elseif id > arg.drop
            arg2var!(ft.fi, id)
            assignva!(ft.fi, id, newva, index)
            deleteparg!(ft.fi, id)
            index += 1
        elseif id in unseen
            deleteparg!(ft.fi, id)
        end
        delete!(unseen, id)
    end
    return unseen
end

function toCodeInfo(ft::FuncTransform; inline = false, noinline = false, propagate_inbounds = false)
    ci = toCodeInfo(ft.fi, ft.ci; inline, noinline, propagate_inbounds)
    ci.method_for_inference_limit_heuristics = ft.meth
    return ci
end
