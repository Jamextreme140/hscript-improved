package hscript.customclass;

typedef CustomClassDecl = {
    > Expr.ClassDecl,
    /**
	 * Save performance and improve sandboxing by resolving imports at interpretation time.
	 */
    var ?imports:Map<String, CustomClassImport>;
    var ?pkg:Array<String>;
}

typedef CustomClassImport = {
	var ?name:String;
	var ?pkg:Array<String>;
	var ?fullPath:String; // pkg.pkg.pkg.name
}