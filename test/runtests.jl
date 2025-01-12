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
        @time $(string("1st ", expr_str)) $(esc(ex))
	$expr = collect($(esc(a)))[]
        @time $(string("2nd ", expr_str)) $(esc(ex))
	print($expr_str)
	print(" = ")
	println($expr)
	@test $expr ≈ $val
    end
end

@testset "FuncTransforms.jl" begin
    function f(::Type{T}, ::Type, a, b, c, d...) where T
        z = sum(d)
        return a + b + c + z
    end
    fi = FuncInfo(Tuple{typeof(f), Type{Int}, Type{Float32}, Int, Int, Int, Int, Int}, Base.get_world_counter())
    @test length(fi.pargs) == 6 # "self", "unused", "unused, :a, :b, :c
    @test FuncTransforms.hasva(fi)
    @test length(fi.args) == 7 # pargs + va
    @test length(fi.vars) == 1
    @test haskey(fi.args, :a)
    @test haskey(fi.args, :d)
    @test !haskey(fi.args, :T)
    @test !haskey(fi.args, :z)
    @test !haskey(fi.vars, :a)
    @test haskey(fi.vars, :z)

    ci = FuncTransforms.create_codeinfo(@__MODULE__, [], quote end; inline = true)
    @test ci.inlining == 1
    @test !ci.propagate_inbounds
    ci = FuncTransforms.create_codeinfo(@__MODULE__, [], quote end; propagate_inbounds = true)
    @test ci.inlining == 1
    @test ci.propagate_inbounds
    ci = FuncTransforms.create_codeinfo(@__MODULE__, [], quote end; noinline = true)
    @test ci.inlining == 2
    @test !ci.propagate_inbounds
    @test_throws AssertionError FuncTransforms.create_codeinfo(@__MODULE__, [], quote end; noinline = true, inline = true)
    @test_throws AssertionError FuncTransforms.create_codeinfo(@__MODULE__, [], quote end; noinline = true, propagate_inbounds = true)

    @testset "Contextual" begin
        using .Contextual
        using .Contextual: withctx, Context
        struct Sin2Cos <: Context end
        foo(x) = sin(2 * x) / 2
        bar(a, x) = (@inbounds a[1] = foo(x); return)
        baz(a, x) = (withctx(Sin2Cos(), bar, a, x); return)
        qux(a, x) = (@inbounds a[1] = withctx(Sin2Cos(), sin, x); return)
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
        Base.delete_method(first(methods(Contextual.ctxcall, Tuple{Sin2Cos, typeof(sin), Any})))
        @static isdefined(Core, Symbol("@latestworld")) && Core.@latestworld
        @static if VERSION < v"1.12.0-DEV"
            println("\ndelete:")
            @resultshow a_cpu sin(2 * 0.7) / 2 withctx(Sin2Cos(), bar, a_cpu, 0.7)
            @resultshow a_cpu sin(2 * 0.7) / 2 baz(a_cpu, 0.7)
            @resultshow a_cpu sin(0.3) qux(a_cpu, 0.3)
        else
            println("\ndelete0:")
            @resultshow a_cpu cos(2 * 0.7) / 2 withctx(Sin2Cos(), bar, a_cpu, 0.7)
            @resultshow a_cpu cos(2 * 0.7) / 2 baz(a_cpu, 0.7)
            @resultshow a_cpu cos(0.3) qux(a_cpu, 0.3)
            Base.delete_method(first(methods(Contextual.ctxcall, Tuple{Sin2Cos, typeof(sin), Any})))
            @static isdefined(Core, Symbol("@latestworld")) && Core.@latestworld
            println("\ndelete1:")
            @resultshow a_cpu sin(2 * 0.7) / 2 withctx(Sin2Cos(), bar, a_cpu, 0.7)
            @resultshow a_cpu sin(2 * 0.7) / 2 baz(a_cpu, 0.7)
            @resultshow a_cpu sin(0.3) qux(a_cpu, 0.3)
        end
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
