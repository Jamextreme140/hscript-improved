package hscript.customclass;

typedef CustomClassDecl = {
    > Expr.ClassDecl,
    var ?imports:Map<String, Array<String>>;
    var ?pkg:Array<String>;
}
