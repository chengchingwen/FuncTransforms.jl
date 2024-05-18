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

end
