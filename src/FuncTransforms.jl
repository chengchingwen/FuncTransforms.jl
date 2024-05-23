module FuncTransforms

export FuncTransform, NA, FA, VA, toCodeInfo, FuncInfo, FuncInfoIter,
    renamearg!, renamevar!, arg2var!, addarg!, addvar!, deletearg!, deletevar!,
    getparg, insertparg!, deleteparg!, addparg!, addva!, getva, setva!,
    firstssavalue, lastssavalue, prevssavalue, nextssavalue,
    replacestmt!, addstmt!, addstmtafter!, addstmtbefore!, insertafter!, insertbefore!,
    repackva!, assignva!

include("utils.jl")
include("funcinfo.jl")
include("functransform.jl")

"""
    abstract type FuncArgs

An abstract type for representing function arguments in a function transformation context for constructing `FuncTransform`.

Subtypes of `FuncArgs` include:
- `NA`: Represents a new argument to be added to the function.
- `FA`: Represents an existing function argument, possibly with modifications.
- `VA`: Specifically denotes a Vararg.
"""
FuncArgs

"""
    NA(name::Symbol; gen = true)

A "New Argument" with `name`. Used to introduce new position argument.
"""
NA

"""
    FA(name::Symbol, slotnumber::Int; gen = true)

A "Function Argument" from the transformed function with old `slotnumber` renamed to `name`.
"""
FA

"""
    VA(name::Symbol, drop::Int; gen = true)

A "VarArg". With `VA`, we can assign the values in this argument to the arguments of the transformed function.
 `drop` would drop the given number of arguments of the transformed function (var"#self#" also counts).
"""
VA

"""
    FuncTransform(sig, world, fargs::Vector{FuncArgs};
        caller::Union{MethodInstance, Nothing} = nothing,
        method_tables::Union{Nothing, MethodTable} = nothing)

Constructs a `FuncTransform` object used to perform transformations on function `sig` of world age `world`.
 `fargs` is used to specific the new function arguments of the new function. If `caller` is provided, it also
 set the backedge accordingly. The transformations should be applied to `FuncTransform(...).fi::FuncInfo` and
 use `toCodeInfo` to get the result.
"""
FuncTransform

"""
    toCodeInfo(fi::Union{FuncInfo, FuncTransform})

Converts a `FuncInfo` or `FuncTransform` into a `Core.CodeInfo`.
"""
toCodeInfo

"""
    FuncInfo(sig, world; method_tables::Union{Nothing, MethodTable} = nothing)

Lookup to `Core.CodeInfo` of a function signature `sig` with specific world age and convert the `Core.CodeInfo` into `FuncInfo`.
"""
FuncInfo

"""
    FuncInfoIter(fi::FuncInfo, start = firstssavalue(fi))

Creates an iterator over the code statements of a function's code block starting from a given SSA value.
"""
FuncInfoIter

"""
    renamearg!(fi::FuncInfo, slot, name::Symbol)

Renames an argument identified by `slot` in `FuncInfo` to the new `name` provided.
"""
renamearg!

"""
    renamevar!(fi::FuncInfo, slot, name::Symbol)

Renames a variable identified by `slot` in `FuncInfo` to the new `name` provided.
"""
renamevar!

"""
    arg2var!(fi::FuncInfo, id::Union{SlotNumber, Int})

Moves an argument identified by `id` from the argument slots to variable slots in `FuncInfo`.
"""
arg2var!

"""
    addarg!(fi::FuncInfo, name::Symbol)

Adds a new argument to `FuncInfo` with the specified `name`. Returns the new `SlotNumber`.
"""
addarg!

"""
    addvar!(fi::FuncInfo, name::Symbol)

Adds a new variable to `FuncInfo` with the specified `name`. Returns the new `SlotNumber`.
"""
addvar!

"""
    deletearg!(fi::FuncInfo, id::Union{SlotNumber, Int})

Deletes an argument from `FuncInfo` identified by `id`.
"""
deletearg!

"""
    deletevar!(fi::FuncInfo, id::Union{SlotNumber, Int})

Deletes a variable from `FuncInfo` identified by `id`.
"""
deletevar!

"""
    getparg(fi::FuncInfo, index::Integer)

Retrieves the `SlotNumber` of the positional argument at the given `index` in `FuncInfo`.
"""
getparg

"""
    insertparg!(fi::FuncInfo, id::Union{SlotNumber, Int}, index::Integer)

Inserts an existing argument identified by `id` into the positional arguments of `FuncInfo` at the specified `index`.
"""
insertparg!

"""
    deleteparg!(fi::FuncInfo, id::Union{SlotNumber, Int})

Removes the positional argument from `FuncInfo` identified by `id`.
"""
deleteparg!

"""
    addparg!(fi::FuncInfo, name::Symbol [, index::Integer])

Adds a new argument to `FuncInfo` with the specified `name`, and insert it to the position arguments.
 If `index` is not provided, insert it to the last non-vararg position. Returns the new `SlotNumber`.
 Equivalent to `addarg!` + `insertparg!`.
"""
addparg!

"""
    addva!(fi::FuncInfo, name::Symbol)

Adds a new argument to `FuncInfo` and sets it as the vararg. Returns the `SlotNumber` of the new argument.
"""
addva!

"""
    getva(fi::FuncInfo)

Returns the `SlotNumber` of the vararg in `FuncInfo`.
"""
getva

"""
    setva!(fi::FuncInfo, id::Union{SlotNumber, Int})

Sets the vararg of `FuncInfo` to the specified `id`.
"""
setva!

"""
    firstssavalue(fi::FuncInfo)

Returns the first SSA value in the code block of `FuncInfo`.
"""
firstssavalue

"""
    lastssavalue(fi::FuncInfo)

Returns the last SSA value in the code block of `FuncInfo`.
"""
lastssavalue

"""
    prevssavalue(fi::FuncInfo, i::Union{SSAValue, Int})

Returns the previous SSA value of the given SSA Value `i` in the code block of `FuncInfo`.
"""
prevssavalue

"""
    nextssavalue(fi::FuncInfo, i::Union{SSAValue, Int})

Returns the next SSA value of the given SSA value `i` in the code block of `FuncInfo`.
"""
nextssavalue

"""
    replacestmt!(fi::FuncInfo, id::Union{SSAValue, Int}, stmt)

Replaces the statement at the given SSA Value `id` in `FuncInfo`'s code block with a new statement.
"""
replacestmt!

"""
    addstmt!(fi::FuncInfo, stmt)

Adds a new statement to `FuncInfo` but not insert into the code block. Returns the new `SSAValue`.
"""
addstmt!

"""
    addstmtafter!(fi::FuncInfo, id::Union{SSAValue, Int}, stmt)

Inserts a new statement after the statement identified by `id` in `FuncInfo`.
 Returns the new `SSAValue` for the inserted statement. Equivalent to `addstmt!` + `insertafter!`.
"""
addstmtafter!

"""
    addstmtbefore!(fi::FuncInfo, id::Union{SSAValue, Int}, stmt)

Inserts a new statement before the statement identified by `id` in `FuncInfo`.
 Returns the new `SSAValue` for the inserted statement. Equivalent to `addstmt!` + `insertbefore!`.
"""
addstmtbefore!

"""
    insertafter!(fi::FuncInfo, id::Union{SSAValue, Int}, stmtid::Union{SSAValue, Int})

Inserts the statement identified by `stmtid` after the statement identified by `id` in `FuncInfo`.
"""
insertafter!

"""
    insertbefore!(fi::FuncInfo, id::Union{SSAValue, Int}, stmtid::Union{SSAValue, Int})

Inserts the statement identified by `stmtid` before the statement identified by `id` in `FuncInfo`.
"""
insertbefore!

"""
    repackva!(fi::FuncInfo, varid::Union{SlotNumber, Int}, vaid::Union{SlotNumber, Int}, indices::Vector{Integer})

Add the code at the beginning of code block that: given the new vararg (`vaid`),
 extract the element at `indices`, pack them as a tuple and assign to the old vararg (`varid`).
"""
repackva!

"""
    assignva!(fi::FuncInfo, varid::Union{SlotNumber, Int}, vaid::Union{SlotNumber, Int}, index::Integer)

Add the code at the beginning of code block that: given the new vararg (`vaid`),
 extract the element at `index and assign to the old argument `varid`.
"""
assignva!

end
