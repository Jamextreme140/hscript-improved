package hscript.customclass;

import hscript.Expr.VarDecl;
import hscript.Expr.FunctionDecl;
import hscript.Expr.FieldDecl;

class CustomClass {
	private var _class:CustomClassDecl;
	private var _interp:Interp;

	public var superClass:Dynamic = null;

	public var className(get, null):String;

	private function get_className():String {
		var name = "";
		if (_class.pkg != null) {
			name += _class.pkg.join(".");
		}
		name += _class.name;
		return name;
	}

	public function new(_class:CustomClassDecl, args:Array<Dynamic>) {
		this._class = _class;
		this._interp = new Interp(this);
		buildCaches();

		if (findField("new") != null) {
			callFunction("new", args);
			if (superClass == null && _class.extend != null) {
				@:privateAccess this._interp.error(ECustom("super() not called"));
			}
		} else if (_class.extend != null) {
			createSuperClass(args);
		}
	}

	private function superConstructor(...args:Dynamic) {
		createSuperClass(args.toArray());
	}

	private function createSuperClass(args:Array<Dynamic> = null) {
		if (args == null)
			args = [];

		var extendString = new Printer().typeToString(_class.extend);
		if (_class.pkg != null && extendString.indexOf(".") == -1) {
			extendString = _class.pkg.join(".") + "." + extendString;
		}
		var classDescriptor = Interp.findCustomClassDescriptor(extendString);
		if (classDescriptor != null) {
			var abstractSuperClass:AbstractCustomClass = new CustomClass(classDescriptor, args);
			superClass = abstractSuperClass;
		} else {
			var c = Type.resolveClass(extendString);
			if (c == null) {
				@:privateAccess _interp.error(ECustom("could not resolve super class: " + extendString));
			}
			superClass = Type.createInstance(c, args);
		}
	}

	public function callFunction(name:String, args:Array<Dynamic> = null, publicAccess:Bool = false) {
		var field = findField(name, publicAccess);
		var r:Dynamic = null;

		if (field != null) {
			var fn = findFunction(name);
			var previousValues:Map<String, Dynamic> = [];
			var i = 0;
			for (a in fn.args) {
				var value:Dynamic = null;

				if (args != null && i < args.length) {
					value = args[i];
				} else if (a.value != null) {
					value = _interp.expr(a.value);
				}

				if (_interp.variables.exists(a.name)) {
					previousValues.set(a.name, _interp.variables.get(a.name));
				}
				_interp.variables.set(a.name, value);
				i++;
			}

			r = _interp.execute(fn.body);

			for (a in fn.args) {
				if (previousValues.exists(a.name)) {
					_interp.variables.set(a.name, previousValues.get(a.name));
				} else {
					_interp.variables.remove(a.name);
				}
			}
		} else {
			var fixedArgs = [];
			for (a in args) {
				if ((a is CustomClass)) {
					fixedArgs.push(cast(a, CustomClass).superClass);
				} else {
					fixedArgs.push(a);
				}
			}
			r = Reflect.callMethod(superClass, Reflect.field(superClass, name), fixedArgs);
		}
		return r;
	}

	private function findField(name:String, publicAccess:Bool = false):FieldDecl {
		if (_cachedFieldDecls != null && _cachedFieldDecls.exists(name)) {
			return _cachedFieldDecls.get(name);
		}

		for (f in _class.fields) {
			if (f.name == name) {
				if(f.access.contains(APrivate) && publicAccess) {
					_interp.error(ECustom('Cannot access private field ${name}'));
					return null;
				}
				else 
					return f;
			}
		}
		return null;
	}

	private function findFunction(name:String, publicAccess:Bool = false):FunctionDecl {
		if (_cachedFunctionDecls != null && _cachedFunctionDecls.exists(name)) {
			return _cachedFunctionDecls.get(name);
		}

		for (f in _class.fields) {
			if (f.name == name) {
				switch (f.kind) {
					case KFunction(fn):
						if(f.access.contains(APrivate) && publicAccess) {
							_interp.error(ECustom('Cannot access private field ${name}'));
							return null;
						}
						else
							return fn;
					default:
				}
			}
		}

		return null;
	}

	private function findVar(name:String, publicAccess:Bool = false):VarDecl {
		if (_cachedVarDecls != null && _cachedVarDecls.exists(name)) {
			return _cachedVarDecls.get(name);
		}

		for (f in _class.fields) {
			if (f.name == name) {
				switch (f.kind) {
					case KVar(v):
						if(f.access.contains(APrivate) && publicAccess) {
							_interp.error(ECustom('Cannot access private field ${name}'));
							return null;
						}
						else 
							return v;
					default:
				}
			}
		}

		return null;
	}

	private var _cachedFieldDecls:Map<String, FieldDecl> = null;
	private var _cachedFunctionDecls:Map<String, FunctionDecl> = null;
	private var _cachedVarDecls:Map<String, VarDecl> = null;

	private function buildCaches() {
		_cachedFieldDecls = [];
		_cachedFunctionDecls = [];
		_cachedVarDecls = [];

		for (f in _class.fields) {
			if(f.access.contains(APrivate)) continue; //Only catch non-private variables
			_cachedFieldDecls.set(f.name, f);
			switch (f.kind) {
				case KFunction(fn):
					_cachedFunctionDecls.set(f.name, fn);
				case KVar(v):
					_cachedVarDecls.set(f.name, v);
					if (v.expr != null) {
						var varValue = this._interp.expr(v.expr);
						this._interp.variables.set(f.name, varValue);
					}
			}
		}
	}

	// I can't get what is the purpose of this...
	// This is for the abstract class
	private inline function callFunction0(name:String) {
		return callFunction(name);
	}

	private inline function callFunction1(name:String, arg0:Dynamic) {
		return callFunction(name, [arg0]);
	}

	private inline function callFunction2(name:String, arg0:Dynamic, arg1:Dynamic) {
		return callFunction(name, [arg0, arg1]);
	}

	private inline function callFunction3(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic) {
		return callFunction(name, [arg0, arg1, arg2]);
	}

	private inline function callFunction4(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic) {
		return callFunction(name, [arg0, arg1, arg2, arg3]);
	}

	private inline function callFunction5(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic):Dynamic {
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4]);
	}

	private inline function callFunction6(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic, arg5:Dynamic):Dynamic {
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4, arg5]);
	}

	private inline function callFunction7(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic, arg5:Dynamic,
			arg6:Dynamic):Dynamic {
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4, arg5, arg6]);
	}

	private inline function callFunction8(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic, arg5:Dynamic, arg6:Dynamic,
			arg7:Dynamic):Dynamic {
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7]);
	}
}
