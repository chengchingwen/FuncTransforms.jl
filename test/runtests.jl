using FuncTransforms
using Test

include("contextual.jl")

macro isinferred(ex)
    esc(quote
        try
            @inferred $ex
            true
        catch err
            @error err
            isa(err, ErrorException) ? false : rethrow(err)
        end
    end)
end
macro resultshow(a, val, ex)
    expr_str = sprint(Base.show_unquoted, ex)
    expr = Symbol(expr_str)
    linfo = findfirst("=# ", expr_str)
    if !isnothing(linfo)
	expr_str = expr_str[last(linfo)+1:end]
    end
    return quote
	@time $(esc(ex))
	print($expr_str)
	print(" = ")
	$expr = collect($(esc(a)))[]
	println($expr)
	@test $expr ≈ $val
    end
end

@testset "FuncTransforms.jl" begin
    @testset "Contextual" begin
        using .Contextual
        using .Contextual: withctx, Context
        struct Sin2Cos <: Context end
        foo(x) = sin(2 * x) / 2
        bar(a, x) = (a[1] = foo(x); return)
        baz(a, x) = (withctx(Sin2Cos(), bar, a, x); return)
        qux(a, x) = (a[1] = withctx(Sin2Cos(), sin, x); return)
        a_cpu = Float32[0]
        println("\nbefore:")
        @resultshow a_cpu sin(2 * 0.7) / 2 withctx(Sin2Cos(), bar, a_cpu, 0.7)
        @resultshow a_cpu sin(2 * 0.7) / 2 baz(a_cpu, 0.7)
        @resultshow a_cpu sin(0.3) qux(a_cpu, 0.3)
        Contextual.ctxcall(::Sin2Cos, ::typeof(sin), x) = cos(x)
        println("\nafter:")
        @resultshow a_cpu cos(2 * 0.7) / 2 withctx(Sin2Cos(), bar, a_cpu, 0.7)
        @resultshow a_cpu cos(2 * 0.7) / 2 baz(a_cpu, 0.7)
        @resultshow a_cpu cos(0.3) qux(a_cpu, 0.3)
        Contextual.ctxcall(::Sin2Cos, ::typeof(sin), x) = tan(x)
        println("\nredefine:")
        @resultshow a_cpu tan(2 * 0.7) / 2 withctx(Sin2Cos(), bar, a_cpu, 0.7)
        @resultshow a_cpu tan(2 * 0.7) / 2 baz(a_cpu, 0.7)
        @resultshow a_cpu tan(0.3) qux(a_cpu, 0.3)
        ms = methods(Contextual.ctxcall, Tuple{Sin2Cos, typeof(sin), Any})
        while length(ms) != 0
            Base.delete_method(ms[1])
            ms = methods(Contextual.ctxcall, Tuple{Sin2Cos, typeof(sin), Any})
        end
        println("\ndelete:")
        @resultshow a_cpu sin(2 * 0.7) / 2 withctx(Sin2Cos(), bar, a_cpu, 0.7)
        @resultshow a_cpu sin(2 * 0.7) / 2 baz(a_cpu, 0.7)
        @resultshow a_cpu sin(0.3) qux(a_cpu, 0.3)
        Contextual.ctxcall(ctx::Sin2Cos, ::typeof(foo), x) = sin(x) + withctx(ctx, cos, x)
        Contextual.ctxcall(ctx::Sin2Cos, ::typeof(cos), x) = tan(x)
        println("\nafter2:")
        @resultshow a_cpu sin(0.7) + tan(0.7) withctx(Sin2Cos(), bar, a_cpu, 0.7)
        @resultshow a_cpu sin(0.7) + tan(0.7) baz(a_cpu, 0.7)
        @resultshow a_cpu sin(0.3) qux(a_cpu, 0.3)
        Contextual.ctxcall(ctx::Sin2Cos, ::typeof(foo), x) = sin(x) + cos(x)
        println("\nredefine2:")
        @resultshow a_cpu sin(0.7) + cos(0.7) withctx(Sin2Cos(), bar, a_cpu, 0.7)
        @resultshow a_cpu sin(0.7) + cos(0.7) baz(a_cpu, 0.7)
        @resultshow a_cpu sin(0.3) qux(a_cpu, 0.3)

        @test @isinferred withctx(Sin2Cos(), x->hcat(x,x)[1], [8,9,99])
        @test @isinferred withctx(Sin2Cos(), sort!, [3,1,2])
        @test withctx(Sin2Cos(), sort!, [3,1,2]) == [1,2,3]
    end
end
