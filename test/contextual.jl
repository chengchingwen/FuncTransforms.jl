module Contextual

using Core: MethodTable
using Core.Compiler: specialize_method
using Base.Meta: isexpr

using FuncTransforms
using FuncTransforms: create_codeinfo, method_by_ftype, lookup_method, walk, resolve, inlineflag!, add_ci_edges!

struct WithCtxGenerator{MT<:Union{Nothing, MethodTable, Vector{MethodTable}}}
    overlay_tables::MT
end

function (g::WithCtxGenerator)(world, source, self, ctx, func, args)
    fsig = Tuple{func, args...}
    overlaymeth = isnothing(g.overlay_tables) ? nothing : lookup_method(fsig, g.overlay_tables, world)
    overlay = !isnothing(overlaymeth)
    dispatchsig = Tuple{typeof(ctxcall), ctx, func, args...}
    dispatchmeth = lookup_method(dispatchsig, nothing, world)
    hasdispatch = !isnothing(dispatchmeth)
    match = method_by_ftype(Tuple{self, ctx, func, args...}, g.overlay_tables, world) # withctx overlaid
    meth = match.method
    caller = specialize_method(match)
    descend = !(hasdispatch || overlay)
    if hasdispatch
        ft = FuncTransform(dispatchsig, world, [:withctx, FA(:__ctx__, 2), FA(:func, 3), VA(:__args__, 3)]; caller)
    elseif overlay
        ft = FuncTransform(fsig, world, [:withctx, :__ctx__, FA(:func, 1), VA(:__args__, 1)];
                           caller, method_tables = g.overlay_tables)
    else
        ft = FuncTransform(fsig, world, [:withctx, :__ctx__, FA(:func, 1), VA(:__args__, 1)]; caller)
    end
    if descend
        witharg = getparg(ft.fi, 1)
        ctxarg = getparg(ft.fi, 2)
    end
    for (ssavalue, code) in FuncInfoIter(ft.fi, 1)
        stmt = code.stmt
        if descend && isexpr(stmt, :call)
            callee = resolve(stmt.args[1])
            if callee isa Core.Builtin || callee isa Type{Core.TypeVar}
                if callee isa typeof(Core._apply_iterate)
                    id = addstmtbefore!(ft.fi, ssavalue, Expr(:call, GlobalRef(Core, :tuple), ctxarg, stmt.args[3]))
                    newstmt = Expr(:call, stmt.args[1], stmt.args[2], witharg, id, stmt.args[4:end]...)
                else
                    newstmt = stmt
                end
            else
                newstmt = Expr(:call, witharg, ctxarg, stmt.args...)
            end
            code.stmt = newstmt
        end
    end
    ci = toCodeInfo(ft)
    @static if VERSION < v"1.12.0-DEV.1531"
        add_ci_edges!(ci, typeof(ctxcall).name.mt, Tuple{typeof(ctxcall), ctx, func, Vararg{Any}})
    else
        add_ci_edges!(ci, Tuple{typeof(ctxcall), ctx, func, Vararg{Any}}, typeof(ctxcall).name.mt)
    end
    return ci
end

abstract type Context end

# for dispatch only, would never be called directly
# behavior default to `withctx(ctx, func, args...)`
ctxcall(ctx::Context, func::Core.Builtin, args...) = func(args...)
ctxcall(ctx::Context, func::typeof(Core._apply_iterate), iter, f, args...) = Core._apply_iterate(iter, withctx, (ctx, f), args...)
ctxcall(ctx::Context, T::Type{Core.TypeVar}, args...) = T(args...)

@eval function withctx(ctx::Context, func, args...)
    $(Expr(:meta, :generated, WithCtxGenerator(nothing)))
    $(Expr(:meta, :generated_only))
end

end
