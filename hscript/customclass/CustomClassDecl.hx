package hscript.customclass;

import hscript.Expr.VarDecl;
import hscript.Expr.FunctionDecl;

@:structInit
class CustomClassDecl {
    public var clsDecl:Expr.ClassDecl;
    /**
	 * Save performance and improve sandboxing by resolving imports at interpretation time.
	 */
    public var imports:Map<String, CustomClassImport>;
    public var pkg:Null<Array<String>> = null;

	public var staticInterp:Interp = new Interp();

	var _cachedStaticFunctions:Map<String, FunctionDecl> = [];
	var _cachedStaticVariables:Map<String, VarDecl> = [];

	public function cacheFields() {
		for(f in clsDecl.fields) {
			if(f.access.contains(AStatic)) {
				switch (f.kind) {
					case KFunction(fn):
						_cachedStaticFunctions.set(f.name, fn);
					case KVar(v):
						_cachedStaticVariables.set(f.name, v);
						if(v.expr != null) {
							var varValue = this.staticInterp.expr(v.expr);
							this.staticInterp.variables.set(f.name, varValue);
						}
				}
			}
		}
	}

	public function callStaticFunction(name:String, ?args:Array<Dynamic>) {
		var func:FunctionDecl = null;
		
		if(_cachedStaticFunctions.exists(name))
			func = _cachedStaticFunctions.get(name);
		else {
			for(f in clsDecl.fields) {
				if(f.name == name && f.access.contains(AStatic)) {
					switch (f.kind) {
						case KFunction(fn):
							func = fn;
						default:
					}
				}
			}
		}

		if(func != null)
			return CustomClass.callStaticFunction(staticInterp, func, args != null ? args : []);

		return null;
	}

	public function getStaticField(name:String):Dynamic {
		var staticVar:VarDecl = null;

		if(_cachedStaticVariables.exists(name)) {
			staticVar = _cachedStaticVariables.get(name);
		}
		else {
			for (f in clsDecl.fields) {
				if (f.name == name && f.access.contains(AStatic)) {
					switch (f.kind) {
						case KVar(v):
							staticVar = v;
						default:
					}
				}
			}
		}

		if(staticVar != null) {
			var varValue:Dynamic = null;
			if(!this.staticInterp.variables.exists(name)) {
				if(staticVar.expr != null) {
					varValue = this.staticInterp.expr(staticVar.expr);
					this.staticInterp.variables.set(name, varValue);
				}
			}
			else {
				varValue = this.staticInterp.variables.get(name);
			}
			return varValue;
		}

		return null;
	}

	private function hasVar(name:String):Bool {
		if(_cachedStaticVariables.exists(name))
			return true;

		for(f in clsDecl.fields) {
			if(f.name == name && f.access.contains(AStatic)) {
				switch (f.kind) {
					case KVar(v):
						return true;
					default:
				}
			}
		}

		return false;
	}

	public function setStaticField(name:String, val:Dynamic):Dynamic {
		if(hasVar(name)) {
			this.staticInterp.variables.set(name, val);
			return val;
		}

		throw "static field '" + name + "' does not exist in custom class '" + this.clsDecl.name + "'";
	}
}

typedef CustomClassImport = {
	var ?name:String;
	var ?pkg:Array<String>;
	var ?fullPath:String; // pkg.pkg.pkg.name
}