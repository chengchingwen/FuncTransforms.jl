using Core.Compiler: IR_FLAG_NULL, IR_FLAG_INBOUNDS, IR_FLAG_INLINE, IR_FLAG_NOINLINE
using Base: SLOT_USED

const SlotFlagType = eltype(fieldtype(CodeInfo, :slotflags))
const SSAFlagType = eltype(fieldtype(CodeInfo, :ssaflags))
const CodeLocType = eltype(fieldtype(CodeInfo, :codelocs))

const SlotID = Union{Int, SlotNumber}
const SSAID = Union{Int, SSAValue}
_id(id::Int) = id
_id(slotnumber::SlotNumber) = slotnumber.id
_id(ssavalue::SSAValue) = ssavalue.id

mutable struct Slot
    name::Symbol
    flag::SlotFlagType
end
Slot(name::Symbol) = Slot(name, SLOT_USED)
_slot(val::Slot) = (val.name, val.flag)
_slot(val) = val

struct Slots
    name2id::Dict{Symbol, Any}
    id2nameflag::Dict{Int, Slot}
end
Slots() = Slots(Dict{Symbol, Any}(), Dict{Int, Slot}())
function getunique(slots::Slots, name::Symbol)
    id = slots.name2id[name]
    id isa Int || error("multiple slot with same name, use slot id directly.")
    return id
end
getslot(slots::Slots, id::SlotID) = slots.id2nameflag[_id(id)]
getslot(slots::Slots, name::Symbol) = slots.id2nameflag[getunique(slots, name)]
setslot!(slots::Slots, id::SlotID, slot::Slot) = slots.id2nameflag[_id(id)] = slot
Base.length(slots::Slots) = length(slots.id2nameflag)
Base.getindex(slots::Slots, id::SlotID) = _slot(getslot(slots, id))
Base.getindex(slots::Slots, name::Symbol) = getunique(slots, name)
Base.haskey(slots::Slots, id::SlotID) = haskey(slots.id2nameflag, _id(id))
Base.haskey(slots::Slots, name::Symbol) = haskey(slots.name2id, name)
Base.get(slots::Slots, id::SlotID, default) = _slot(get(slots.id2nameflag, _id(id), default))
Base.get(slots::Slots, name::Symbol, default) = haskey(slots.name2id, name) ? getunique(slots, name) : default
function Base.delete!(slots::Slots, name::Symbol)
    id = getunique(slots, name)
    delete!(slots.name2id, name)
    delete!(slots.id2nameflag, id)
    return slots
end
function _deleteid!(slots::Slots, name::Symbol, id::SlotID)
    id = _id(id)
    ids = slots.name2id[name]
    if ids isa Int
        ids == id && delete!(slots.name2id, name)
    else
        delete!(ids, id)
    end
end
function _pushid!(slots::Slots, name::Symbol, id::SlotID)
    id = _id(id)
    if haskey(slots, name)
        ids = slots.name2id[name]
        if ids isa Int
            slots.name2id[name] = BitSet((ids, id))
        else
            push!(ids, id)
        end
    else
        slots.name2id[name] = id
    end
end
function Base.delete!(slots::Slots, id::SlotID)
    id = _id(id)
    name, _ = slots[id]
    delete!(slots.id2nameflag, id)
    _deleteid!(slots, name, id)
    return slots
end
function Base.setindex!(slots::Slots, @nospecialize(_nameflag::Union{Tuple{Symbol, Integer}, Symbol}), id::SlotID)
    hasflag = _nameflag isa Tuple
    nameflag = hasflag ? _nameflag : (_nameflag,)
    name = nameflag[1]
    id = _id(id)
    if haskey(slots, id)
        slot = getslot(slots, id)
        _deleteid!(slots, slot.name, id)
        _pushid!(slots, name, id)
        slot.name = nameflag[1]
        hasflag && (slot.flag = nameflag[2])
    else
        slot = Slot(nameflag...)
        _pushid!(slots, name, id)
        setslot!(slots, id, slot)
    end
    return _slot(slot)
end
function Base.iterate(slots::Slots, state...)
    iter = iterate(slots.id2nameflag, state...)
    isnothing(iter) && return nothing
    kv, nstate = iter
    id, slot = kv
    (; name, flag) = slot
    return (id, name, flag), nstate
end
function rename!(slots::Slots, name2::Symbol, name::Symbol)
    @assert haskey(slots, name2) "renamed slot($name2) not exist"
    return rename!(slots, slots[name2], name)
end
function rename!(slots::Slots, id::SlotID, name::Symbol)
    id = _id(id)
    @assert get(slots, name, id) == id "renamed slot($id) to an existing name \"$name\""
    @assert haskey(slots, id) "renamed slot($id) not exist"
    slot = getslot(slots, id)
    name2 = slot.name
    slots[id] = name
    return name2
end

mutable struct PrevNext
    prev::Int
    next::Int
end
mutable struct Code
    stmt::Any
    flag::SSAFlagType
    loc::CodeLocType
end
Code(@nospecialize(stmt::Any), flag::Integer) = Code(stmt, flag, zero(CodeLocType))
Code(@nospecialize(stmt::Any)) = Code(stmt, IR_FLAG_NULL)
_code(val::Code) = (val.stmt, val.flag, val.loc)
_code(val) = val

struct CodeBlock
    id2stmtflagloc::Dict{Int, Code}
    order::Dict{Int, PrevNext}
    linetable::Any
end
CodeBlock(linetable) = CodeBlock(Dict{Int, Code}(), Dict{Int, PrevNext}(), linetable)
getcode(codes::CodeBlock, id::SSAID) = codes.id2stmtflagloc[_id(id)]
setcode!(codes::CodeBlock, id::SSAID, code::Code) = codes.id2stmtflagloc[_id(id)] = code
getorder(codes::CodeBlock, id::SSAID) = codes.order[_id(id)]
getnext(codes::CodeBlock, id::SSAID) = codes.order[_id(id)].next
getprev(codes::CodeBlock, id::SSAID) = codes.order[_id(id)].prev
setorder!(codes::CodeBlock, id::SSAID, order::NTuple{2, Int}) = codes.order[_id(id)] = PrevNext(order...)
function setnext!(codes::CodeBlock, id::SSAID, next::SSAID)
    order = getorder(codes, id)
    next2 = order.next
    order.next = _id(next)
    return next2
end
function setprev!(codes::CodeBlock, id::SSAID, prev::SSAID)
    order = getorder(codes, id)
    prev2 = order.prev
    order.prev = _id(prev)
    return prev2
end
Base.length(codes::CodeBlock) = length(codes.order)
Base.getindex(codes::CodeBlock, id::SSAID) = _code(getcode(codes, id))
Base.haskey(codes::CodeBlock, id::SSAID) = haskey(codes.id2stmtflagloc, _id(id))
Base.get(codes::CodeBlock, id::SSAID, default) = _code(get(codes.id2stmtflagloc, _id(id), default))
function Base.delete!(codes::CodeBlock, id::SSAID)
    id = _id(id)
    delete!(codes.id2stmtflagloc, id)
    delete!(codes.order, id)
    return codes
end
function _setindex!(codes::CodeBlock, @nospecialize(stmtflagloc::Tuple), id::SSAID)
    if haskey(codes, id)
        code = getcode(codes, id)
        code.stmt = stmtflagloc[1]
        length(stmtflagloc) > 1 && (code.flag = stmtflagloc[2])
        length(stmtflagloc) > 2 && (code.loc = stmtflagloc[3])
    else
        code = Code(stmtflagloc...)
        setcode!(codes, id, code)
    end
    return _code(code)
end
Base.setindex!(codes::CodeBlock, @nospecialize(stmtflagloc::Tuple{Any, Integer, Integer}), id::SSAID) =  _setindex!(codes, stmtflagloc, id)
Base.setindex!(codes::CodeBlock, @nospecialize(stmtflag::Tuple{Any, Integer}), id::SSAID) = _setindex!(codes, stmtflag, id)
Base.setindex!(codes::CodeBlock, @nospecialize(stmt::Tuple{Any}), id::SSAID) = _setindex!(codes, stmt, id)

struct CodeIter
    codes::CodeBlock
    start::Int
end
CodeIter(codes::CodeBlock, start::SSAValue) = CodeIter(codes, _id(start))
function Base.iterate(iter::CodeIter, ssavalue = iter.start)
    !haskey(iter.codes.order, ssavalue) && return nothing
    nextssa = getnext(iter.codes, ssavalue)
    return ((ssavalue, iter.codes[ssavalue]...), ssavalue == nextssa ? 0 : nextssa)
end

# In FuncInfo, we give the id of `SlotNumber`/`SSAValue` a different meaning as the unique id instead of index.
#  This make it easier to modify the code without worrying the shift of id. The correct id/index will be reassigned
#  when generating new CodeInfo.
mutable struct FuncInfo
    pargs::Vector{Int} # position of args w/o vararg
    va::Int # vararg id
    first::Int
    last::Int
    args::Slots
    vars::Slots
    codes::CodeBlock
end
function FuncInfo(meth::Method, ci::CodeInfo)
    args = Slots()
    vars = Slots()
    nargs = meth.nargs
    isva = meth.isva
    pargs = collect(1:nargs - isva)
    va = isva ? nargs : 0
    for (slotnumber, (name, flag)) in enumerate(zip(ci.slotnames, ci.slotflags))
        (slotnumber <= nargs ? args : vars)[slotnumber] = (name, flag)
    end
    codes = CodeBlock(ismutable(ci.linetable) ? copy(ci.linetable) : ci.linetable)
    for (ssavalue, code_flag_loc) in enumerate(zip(ci.code, ci.ssaflags, ci.codelocs))
        codes[ssavalue] = code_flag_loc
    end
    ssavalues = length(ci.code)
    for ssavalue in 1:ssavalues
        prev = ssavalue == 1 ? 1 : ssavalue - 1
        next = ssavalue == ssavalues ? ssavalues : ssavalue + 1
        setorder!(codes, ssavalue, (prev, next))
    end
    return FuncInfo(pargs, va, min(ssavalues, 1), ssavalues, args, vars, codes)
end
function FuncInfo(
    @nospecialize(fsig), world; method_tables::Union{Nothing, MethodTable, Vector{MethodTable}} = nothing
)
    match = method_by_ftype(fsig, method_tables, world)
    meth = match.method
    inst = Core.Compiler.specialize_method(match)
    ci = get_codeinfo(inst, world)
    Meta.partially_inline!(ci.code, Any[], meth.sig, Any[match.sparams...], 0, 0, :propagate)
    return FuncInfo(meth, ci)
end

newslotnumber(fi::FuncInfo) = length(fi.args) + length(fi.vars) + 1
newssavalue(fi::FuncInfo) = length(fi.codes.id2stmtflagloc) + 1

Base.getindex(fi::FuncInfo, slotnumber::SlotNumber) = haskey(fi.args, id) ? fi.args[id] : fi.vars[id]
Base.getindex(fi::FuncInfo, ssavalue::SSAValue) = fi.codes[id]

renamearg!(fi::FuncInfo, slot, name::Symbol) = rename!(fi.args, slot, name)
renamevar!(fi::FuncInfo, slot, name::Symbol) = rename!(fi.vars, slot, name)
arg2var!(fi::FuncInfo, name::Symbol) = arg2var!(fi, fi.args[name])
function arg2var!(fi::FuncInfo, id::SlotID)
    id = _id(id)
    @assert haskey(fi.args, id) "arg slot($id) not exist"
    name, flag = fi.args[id]
    delete!(fi.args, id)
    addvar!(fi, name, flag, id)
end
function addarg!(fi::FuncInfo, name::Symbol, flag::Integer = SLOT_USED, id::SlotID = newslotnumber(fi))
    id = _id(id)
    fi.args[id] = (name, flag)
    return SlotNumber(id)
end
function addvar!(fi::FuncInfo, name::Symbol, flag::Integer = SLOT_USED, id::SlotID = newslotnumber(fi))
    id = _id(id)
    fi.vars[id] = (name, flag)
    return SlotNumber(id)
end
deletearg!(fi::FuncInfo, id::SlotID) = deletearg!(fi, first(fi.args[id]))
function deletearg!(fi::FuncInfo, name::Symbol)
    id = fi.args[name]
    _deleteslot!(fi.args, id, name)
    return SlotNumber(id)
end
deletevar!(fi::FuncInfo, id::SlotID) = deletevar!(fi, first(fi.vars[id]))
function deletevar!(fi::FuncInfo, name::Symbol)
    id = fi.varsyms[name]
    _deleteslot!(fi.vars, id, name)
    return SlotNumber(id)
end

getparg(fi::FuncInfo, index::Integer) = SlotNumber(fi.pargs[index])
insertparg!(fi::FuncInfo, name::Symbol, index::Integer) = insertparg!(fi, fi.args[name], index)
function insertparg!(fi::FuncInfo, id::SlotID, index::Integer)
    id = _id(id)
    @assert haskey(fi.args, id)
    insert!(fi.pargs, index, id)
    return SlotNumber(id)
end
deleteparg!(fi::FuncInfo, name::Symbol) = deleteparg!(fi, fi.args[name])
function deleteparg!(fi::FuncInfo, id::SlotID)
    id = _id(id)
    index = findfirst(==(id), fi.pargs)
    @assert !isnothing(index) "id $id not found in position arguments"
    deletepargat!(fi, index)
end
deletepargat!(fi::FuncInfo, index::Integer) = SlotNumber(popat!(fi.pargs, index))
addparg!(fi::FuncInfo, name::Symbol, index::Integer = length(fi,pargs) + 1) = insertparg!(fi, addarg!(fi, name), index)

hasva(fi::FuncInfo) = !iszero(fi.va)
function addva!(fi::FuncInfo, name::Symbol, flag::Integer = SLOT_USED, id::SlotID = newslotnumber(fi))
    id = addarg!(fi, name, flag, id)
    return setva!(fi, id)
end
getva(fi::FuncInfo) = SlotNumber(fi.va)
function setva!(fi::FuncInfo, id::SlotID)
    id = _id(id)
    fi.va = id
    return SlotNumber(id)
end

firstssavalue(fi::FuncInfo) = fi.first
lastssavalue(fi::FuncInfo) = fi.last
prevssavalue(fi::FuncInfo, i::SSAID) = getorder(fi.codes, i).prev
nextssavalue(fi::FuncInfo, i::SSAID) = getorder(fi.codes, i).next
function ithssavalue(fi::FuncInfo, i)
    ssavalues = length(fi.codes)
    rev = i > div(ssavalues, 2)
    ssavalue = (rev ? lastssavalue : firstssavalue)(fi)
    for _ = 1:(rev ? ssavalues - i : i)
        ssavalue = (rev ? prevssavalue : nextssavalue)(fi, ssavalue)
    end
    return ssavalue
end

function replacestmt!(fi::FuncInfo, id::SSAID, stmtflagloc...)
    id = _id(id)
    @assert haskey(fi.codes, id) "ssa($id) not found in codes"
    fi.codes[id] = stmtflagloc
end
function addstmt!(fi::FuncInfo, @nospecialize(stmt::Any), flag::Integer = IR_FLAG_NULL, loc::Integer = zero(CodeLocType), id::SSAID = newssavalue(fi))
    id = _id(id)
    fi.codes[id] = (stmt, flag, loc)
    return SSAValue(id)
end
addstmtafter!(fi::FuncInfo, id::SSAID, @nospecialize(stmt::Any), flag::Integer = IR_FLAG_NULL,
              loc::Integer = zero(CodeLocType), stmtid::SSAID = newssavalue(fi)) =
                  insertafter!(fi, id, addstmt!(fi, stmt, flag, loc, stmtid))
addstmtbefore!(fi::FuncInfo, id::SSAID, @nospecialize(stmt::Any), flag::Integer = IR_FLAG_NULL,
               loc::Integer = zero(CodeLocType), stmtid::SSAID = newssavalue(fi)) =
                   insertbefore!(fi, id, addstmt!(fi, stmt, flag, loc, stmtid))

function insertafter!(fi::FuncInfo, id::SSAID, stmtid::SSAID)
    # id -> next => id -> stmtid -> next
    id = _id(id)
    stmtid = _id(stmtid)
    next = setnext!(fi.codes, id, stmtid)
    if next == id # last
        setorder!(fi.codes, stmtid, (id, stmtid))
        fi.last = stmtid
    else
        setorder!(fi.codes, stmtid, (id, next))
        setprev!(fi.codes, next, stmtid)
    end
    return SSAValue(stmtid)
end
function insertbefore!(fi::FuncInfo, id::SSAID, stmtid::SSAID)
    # prev -> id => prev -> stmtid -> id
    id = _id(id)
    stmtid = _id(stmtid)
    prev = setprev!(fi.codes, id, stmtid)
    if prev == id # first
        setorder!(fi.codes, stmtid, (stmtid, id))
        fi.first = stmtid
    else
        setorder!(fi.codes, stmtid, (prev, id))
        setnext!(fi.codes, prev, stmtid)
    end
    return SSAValue(stmtid)
end

function repackva!(fi::FuncInfo, varid::SlotID, vaid::SlotID, indices)
    var = SlotNumber(_id(varid))
    va = SlotNumber(_id(vaid))
    stmts = SSAValue[]
    for index in indices
        stmt = Expr(:call, GlobalRef(Core, :getfield), va, index, true)
        push!(stmts, addstmt!(fi, stmt))
    end
    vastmt = Expr(:(=), var, Expr(:call, GlobalRef(Core, :tuple), stmts...))
    push!(stmts, addstmt!(fi, vastmt))
    for id in Iterators.reverse(stmts)
        insertbefore!(fi, firstssavalue(fi), id)
    end
    return last(stmts)
end
function assignva!(fi::FuncInfo, varid::SlotID, vaid::SlotID, index)
    var = SlotNumber(_id(varid))
    va = SlotNumber(_id(vaid))
    stmt = Expr(:(=), var, Expr(:call, GlobalRef(Core, :getfield), va, index, true))
    addstmtbefore!(fi, firstssavalue(fi), stmt)
end

FuncInfoIter(fi::FuncInfo, start::SSAID = firstssavalue(fi)) = CodeIter(fi.codes, _id(start))

function toCodeInfo(fi::FuncInfo, ci::Union{CodeInfo, Nothing} = nothing; inline = false)
    fargs = Symbol[]
    slotnames = Any[]
    slotflags = UInt8[]
    slotremap = Dict{Int, Int}()
    for (slotnumber, id) in enumerate(fi.pargs)
        name, flag = fi.args[id]
        push!(fargs, name)
        push!(slotnames, name)
        push!(slotflags, flag)
        slotremap[id] = slotnumber
    end
    if hasva(fi)
        id = getva(fi).id
        name, flag = fi.args[id]
        push!(fargs, name)
        push!(slotnames, name)
        push!(slotflags, flag)
        slotremap[id] = length(slotremap) + 1
    end
    offset = length(slotremap)
    for (i, (id, name, flag)) in enumerate(fi.vars)
        push!(slotnames, name)
        push!(slotflags, flag)
        slotremap[id] = offset + i
    end
    if isnothing(ci)
        ci = create_codeinfo(fargs, Expr(:block); inline)
    else
        ci = copy(ci)
    end
    code = Any[]
    ssaflags = UInt8[]
    codelocs = fieldtype(CodeInfo, :codelocs)()
    ssaremap = Dict{Int, Int}()
    ssavalues = length(fi.codes)
    for (ssavalue, (id, stmt, flag, loc)) in enumerate(FuncInfoIter(fi))
        push!(code, stmt)
        push!(ssaflags, flag)
        push!(codelocs, loc)
        ssaremap[id] = ssavalue
    end
    for (ssavalue, stmt) in enumerate(code)
        newstmt = walk(stmt) do x
            if x isa SlotNumber
                id = get(slotremap, _id(x), nothing)
                isnothing(id) && error("slot id $id used in code but not found in the output")
                return SlotNumber(id)
            elseif x isa SSAValue
                id = get(ssaremap, _id(x), nothing)
                isnothing(id) && error("ssa id $id used in code but not found in the output")
                return SSAValue(id)
            else
                return x
            end
        end
        @inbounds code[ssavalue] = newstmt
    end
    ci.slotnames = slotnames
    ci.slotflags = slotflags
    ci.code = code
    ci.ssaflags = ssaflags
    ci.ssavaluetypes = ssavalues
    ci.codelocs = codelocs
    ci.linetable = fi.codes.linetable
    return ci
end
