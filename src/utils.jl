using Core: CodeInfo, MethodTable, MethodInstance, SSAValue, SlotNumber, NewvarNode, ReturnNode, GotoNode, GotoIfNot, PhiNode
using Base.Meta: isexpr

create_codeinfo(argnames, body; kws...) = create_codeinfo(argnames, nothing, body; kws...)
create_codeinfo(mod::Module, argnames, body; kws...) = create_codeinfo(mod, argnames, nothing, body; kws...)
create_codeinfo(argnames, spnames, body; kws...) = create_codeinfo(@__MODULE__, argnames, spnames, body; kws...)
function create_codeinfo(mod::Module, argnames, spnames, body; inline = false)
    # argnames: `Vector{Symbol}` representing the variable names, starts with `Symbol("#self#")`.
    # spnames: the variable names in `where {...}`
    @assert isexpr(body, :block) "body should be `Expr(:block, ...)`."
    if inline # insert inline tag to body
        body = Expr(:block, Expr(:meta, :inline), body.args...)
    end
    expr = Expr(:lambda, argnames, Expr(Symbol("scope-block"), body))
    if !isnothing(spnames)
        expr = Expr(Symbol("with-static-parameters"), expr, spnames...)
    end
    ci = ccall(:jl_expand, Any, (Any, Any), expr, mod) # expand macrocall and return code_info
    ci.inlineable = true
    return ci
end

walk(fn, x, guard) = fn(x)
walk(fn, x::SSAValue, guard) = fn(x)
walk(fn, x::SlotNumber, guard) = fn(x)
walk(fn, x::NewvarNode, guard) = NewvarNode(walk(fn, x.slot, guard))
walk(fn, x::ReturnNode, guard) = ReturnNode(walk(fn, x.val, guard))
walk(fn, x::GotoNode, guard) = GotoNode(walk(fn, SSAValue(x.label), guard).id)
walk(fn, x::GotoIfNot, guard) = GotoIfNot(walk(fn, x.cond, guard), walk(fn, SSAValue(x.dest), guard).id)
walk(fn, x::Expr, guard) = Expr(x.head, walk(fn, x.args, guard)...)
walk(fn, x::Vector, guard) = Core.Compiler.anymap(el -> walk(fn, el, guard), x)
walk(fn, x::PhiNode, guard) = PhiNode(map(i->Int32(walk(fn, SSAValue(Int(i)), guard).id), x.edges), walk(fn, x.values, guard))
walk(fn, x) = walk(fn, x, nothing)

resolve(x) = x
resolve(gr::GlobalRef) = getproperty(gr.mod, gr.name)

function lookup_method(@nospecialize(fsig::Type), @nospecialize(mt::Union{Nothing, MethodTable}), world)
    matches = Base._methods_by_ftype(fsig, mt, -1, world)
    return !isnothing(matches) && !isempty(matches) ? only(matches) : nothing
end
function lookup_method(@nospecialize(fsig::Type), @nospecialize(method_tables::Vector{MethodTable}), world)
    for mt in method_tables
        matches = Base._methods_by_ftype(fsig, mt, -1, world)
        !isnothing(matches) && !isempty(matches) && return only(matches)
    end
    return nothing
end
function method_by_ftype(@nospecialize(fsig::Type), @nospecialize(mt::Union{MethodTable, Vector{MethodTable}}), world)
    meth = lookup_method(fsig, mt, world)
    return isnothing(meth) ? only(Base._methods_by_ftype(fsig, -1, world)) : meth
end
method_by_ftype(@nospecialize(fsig::Type), @nospecialize(::Nothing), world) = only(Base._methods_by_ftype(fsig, -1, world))

function get_codeinfo(inst::MethodInstance, world)
    ci = Core.Compiler.retrieve_code_info(inst, world)
    isnothing(ci) && error("Could not get codeinfo for ", inst)
    return copy(ci)
end

# `func` is not directly called, so we need to set the backedges manually so that change of `func`
#  trigger recompilation. On Julia below v1.11, GPUCompiler use a callback for invalidations, but the callback
#  might not be set for `func`, so we add our callback to trigger the callback of the caller.
function add_backedge!(caller::Union{MethodInstance, Nothing}, inst::MethodInstance)
    isnothing(caller) && return
    @static if VERSION < v"1.11.0-DEV.1552"
        callercallback!(caller, inst)
    end
    ccall(:jl_method_instance_add_backedge, Cvoid, (Any, Any, Any), inst, nothing, caller)
    return
end
@static if VERSION < v"1.11.0-DEV.1552"
    struct CallerCallback
        caller::MethodInstance
    end
    function (callback::CallerCallback)(replaced::MethodInstance, max_world,
                                        seen::Set{MethodInstance} = Set{MethodInstance}())
        push!(seen, replaced)
        # run callback of caller
        caller = callback.caller
        isdefined(caller, :callbacks) || return
        for cb in caller.callbacks
            cb(caller, max_world, seen)
        end
        return
    end
    function callercallback!(caller::Union{MethodInstance, Nothing}, inst::MethodInstance)
        isnothing(caller) && return
        cb = CallerCallback(caller)
        hascallbacks = isdefined(inst, :callbacks)
        if hascallbacks
            callbacks = inst.callbacks
            isnothing(findfirst(==(cb), callbacks)) || return
            push!(callbacks, cb)
        else
            inst.callbacks = Any[cb]
        end
        return
    end
end
