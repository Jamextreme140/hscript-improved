package hscript.customclass;

import hscript.Expr;
import hscript.Expr.VarDecl;
import hscript.Expr.FunctionDecl;
import hscript.Expr.FieldDecl;

using Lambda;
using StringTools;

class CustomClass implements IHScriptCustomClassBehaviour implements IHScriptCustomBehaviour{
	public var __interp:Interp;
	public var __custom__variables:Map<String, Dynamic>;
	public var __allowSetGet:Bool;
	public var __real_fields:Array<String>;
	public var __class__fields:Array<String>;

	public var superClass:IHScriptCustomClassBehaviour = null;
	public var superConstructor(default, null):Dynamic;

	public var className(get, null):String;

	private var __class:CustomClassDecl;

	private function get_className():String {
		var name = "";
		if (__class.pkg != null) {
			name += __class.pkg.join(".");
		}
		name += __class.name;
		return name;
	}

	public function new(__class:CustomClassDecl, args:Array<Dynamic>) {
		this.__class = __class;
		this.__interp = new Interp(this);
		buildImports();
		buildCaches();
		buildSuperConstructor();

		if (findField("new") != null) {
			callFunction("new", args);
			if (superClass == null && __class.extend != null) {
				@:privateAccess this.__interp.error(ECustom("super() not called"));
			}
		} else if (__class.extend != null) {
			createSuperClass(args);
		}
	}

	private function buildSuperConstructor() {
		superConstructor = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
			createSuperClass(args);
		});
	}

	private function createSuperClass(args:Array<Dynamic> = null) {
		if (args == null)
			args = [];

		var extendString = new Printer().typeToString(__class.extend);
		if (__class.pkg != null && extendString.indexOf(".") == -1) {
			extendString = __class.pkg.join(".") + "." + extendString;
		}
		var classDescriptor = Interp.findCustomClassDescriptor(extendString);
		if (classDescriptor != null) {
			var abstractSuperClass:CustomClass = new CustomClass(classDescriptor, args);
			superClass = abstractSuperClass;
		} else {
			var c = Type.resolveClass('${extendString}_HSX');
			if (c == null) {
				@:privateAccess __interp.error(ECustom("could not resolve super class: " + extendString));
			}
			superClass = Type.createInstance(c, args);
			setCustomClass();
		}
	}

	private function setCustomClass() {
		var disallowCopy = Type.getInstanceFields(Type.getClass(superClass));

		superClass.__interp = this.__interp;
		superClass.__custom__variables = this.__interp.variables;

		superClass.__real_fields = disallowCopy; // Predefined class fields

		var comparisonMap:Map<String, Dynamic> = [];
		for (key => value in this.__interp.variables) {
			comparisonMap.set(key, value);
		}

		// get only variables that were not set before
		var classVariables = [
			for(key => value in this.__interp.variables)
				if(!comparisonMap.exists(key) || comparisonMap[key] != value)
					key => value
		];

		superClass.__class__fields = [for (key => value in classVariables) key];

		superClass.__allowSetGet = false;
		for(variable => value in this.__interp.variables) {
			if(variable == "this" || variable == "super" || variable == "new") continue;

			if(variable.startsWith("set_") || variable.startsWith("get_")) {
				superClass.__allowSetGet = true;
			}
		}
	}

	public function callFunction(name:String, args:Array<Dynamic> = null) {
		var field = findField(name);
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
					value = __interp.expr(a.value);
				}

				if (__interp.variables.exists(a.name)) {
					previousValues.set(a.name, __interp.variables.get(a.name));
				}
				__interp.variables.set(a.name, value);
				i++;
			}

			r = __interp.execute(fn.body);

			for (a in fn.args) {
				if (previousValues.exists(a.name)) {
					__interp.variables.set(a.name, previousValues.get(a.name));
				} else {
					__interp.variables.remove(a.name);
				}
			}
		} else {
			var fixedArgs = [];
			// OVERRIDE CHANGE: Use _HX_SUPER__ when calling superclass
			var fixedName = '_HX_SUPER__${name}';
			for (a in args) {
				if ((a is CustomClass)) {
					fixedArgs.push(cast(a, CustomClass).superClass);
				} else {
					fixedArgs.push(a);
				}
			}
			var superFn = Reflect.field(superClass, fixedName);
			if(superFn == null) {
				this.__interp.error(ECustom('Error while calling function super.${name}(): EInvalidAccess'
					+ '\n'
					+ 'InvalidAccess error: Super function "${name}" does not exist! Define it or call the correct superclass function.'));
			}
			r = Reflect.callMethod(superClass, superFn, fixedArgs);
		}
		return r;
	}

	private function findField(name:String):FieldDecl {
		if (_cachedFieldDecls != null && _cachedFieldDecls.exists(name)) {
			return _cachedFieldDecls.get(name);
		}

		for (f in __class.fields) {
			if (f.name == name) {
				return f;
			}
		}
		return null;
	}

	private function findFunction(name:String):FunctionDecl {
		if (_cachedFunctionDecls != null && _cachedFunctionDecls.exists(name)) {
			return _cachedFunctionDecls.get(name);
		}

		for (f in __class.fields) {
			if (f.name == name) {
				switch (f.kind) {
					case KFunction(fn):
						return fn;
					default:
				}
			}
		}

		return null;
	}

	private function findVar(name:String):VarDecl {
		if (_cachedVarDecls != null && _cachedVarDecls.exists(name))
		{
			return _cachedVarDecls.get(name);
		}

		for (f in __class.fields) {
			if (f.name == name) {
				switch (f.kind) {
					case KVar(v):
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

		for (f in __class.fields) {
			_cachedFieldDecls.set(f.name, f);
			switch (f.kind) {
				case KFunction(fn):
					_cachedFunctionDecls.set(f.name, fn);
					if(fn.body != null) {
						var isOverride:Bool = f.access.find((f:FieldAccess) -> return f == AOverride) != null;
						#if hscriptPos
						var e:Expr = {
							e: ExprDef.EFunction(fn.args, fn.body, f.name, fn.ret, false, false, isOverride, false, false, false),
							pmin: 0,
							pmax: 0,
							origin: "",
							line: 0
						};
						#else
						var e = Expr.EFunction(fn.args, fn.body, f.name, fn.ret, false, false, isOverride, false, false, false);
						#end
						this.__interp.expr(e);
					}
				case KVar(v):
					_cachedVarDecls.set(f.name, v);
					#if hscriptPos
					var e:Expr = {
						e: ExprDef.EVar(f.name, v.type, v.expr, false, false, false, false, false),
						pmin: 0,
						pmax: 0,
						origin: "",
						line: 0
					};
					#else
					var e = Expr.EVar(f.name, v.type, v.expr, false, false, false, false, false);
					#end
					this.__interp.expr(e);
					//Unnecessary since passing the expression sets the variable automatically
					/*
					if (v.expr != null) {
						var varValue = this.__interp.expr(v.expr);
						this.__interp.variables.set(f.name, varValue);
					}
					*/
			}
		}
	}

	private function buildImports() {
		// TODO: implement Alias imports
		var i:Int = 0;
		for(_import in __class.imports) {
			var importedClass = _import.join(".");
			if(Interp.customClassDescriptorExist(importedClass))
				continue;
			#if hscriptPos
			var e:Expr = {
				e: ExprDef.EImport(importedClass),
				pmin: 0,
				pmax: 0,
				origin: "",
				line: i
			};
			#else
			var e = Expr.EImport(importedClass);
			#end
			this.__interp.expr(e);
			i++;
		}
		
	}

	public function hget(name:String):Dynamic {
		return resolveField(name);
	}
	
	
	public function hset(name:String, val:Dynamic):Dynamic {
		switch (name) {
			case _:
				if (this.findVar(name) != null) {
					this.__interp.variables.set(name, val);
					return val;
				} else if (Reflect.hasField(this.superClass, name)) {
					Reflect.setProperty(this.superClass, name, val);
					return val;
				} else if (this.superClass != null && (this.superClass is CustomClass)) {
					var superScriptClass:CustomClass = cast(this.superClass, CustomClass);
					try {
						return superScriptClass.hset(name, val);
					} catch (e:Dynamic) {}
				} else {
					var superField = Type.getInstanceFields(Type.getClass(this.superClass)).find((f) -> return f == name);

					if(superField != null) {
						if(__allowSetGet)
							Reflect.setProperty(this.superClass, superField, val);
						else 
							Reflect.setField(this.superClass, superField, val);
						return val;
					}
				}
		}

		if (this.superClass == null) {
			throw "field '" + name + "' does not exist in script class '" + this.className + "'";
		} else {
			throw "field '" + name + "' does not exist in script class '" + this.className + "' or super class '"
				+ Type.getClassName(Type.getClass(this.superClass)) + "'";
		}
	}

	public function __callGetter(name:String):Dynamic {
		__allowSetGet = false;
		var v = __custom__variables.get("get_" + name)();
		__allowSetGet = true;
		return v;
	}

	public function __callSetter(name:String, val:Dynamic):Dynamic {
		__allowSetGet = false;
		var v = __custom__variables.get("set_" + name)(val);
		__allowSetGet = true;
		return v;
	}

	private function resolveField(name:String):Dynamic {
		switch (name) {
			case "superClass":
				return this.superClass;
			case "createSuperClass":
				return this.createSuperClass;
			case "findFunction":
				return this.findFunction;
			case "callFunction":
				return this.callFunction;
			default:
				if (this.findFunction(name) != null) {
					var fn = this.findFunction(name);
					var nargs = 0;
					if (fn.args != null) {
						nargs = fn.args.length;
					}
					// TODO: figure out how to optimize this. Macros???
					switch (nargs) {
						case 0: return this.callFunction0.bind(name);
						case 1: return this.callFunction1.bind(name, _);
						case 2: return this.callFunction2.bind(name, _, _);
						case 3: return this.callFunction3.bind(name, _, _, _);
						case 4: return this.callFunction4.bind(name, _, _, _, _);
						#if neko
						case _: @:privateAccess this.__interp.error(ECustom("only 4 params allowed in script class functions (.bind limitation)"));
						#else
						case 5: return this.callFunction5.bind(name, _, _, _, _, _);
						case 6: return this.callFunction6.bind(name, _, _, _, _, _, _);
						case 7: return this.callFunction7.bind(name, _, _, _, _, _, _, _);
						case 8: return this.callFunction8.bind(name, _, _, _, _, _, _, _, _);
						case _: @:privateAccess this.__interp.error(ECustom("only 8 params allowed in script class functions (.bind limitation)"));
						#end
					}
				} else if (this.findVar(name) != null) {
					var v = this.findVar(name);

					var varValue:Dynamic = null;
					if (!this.__interp.variables.exists(name)) {
						if (v.expr != null) {
							varValue = this.__interp.expr(v.expr);
							this.__interp.variables.set(name, varValue);
						}
					} else {
						varValue = this.__interp.variables.get(name);
					}
					return varValue;
				} else if (Reflect.isFunction(Reflect.getProperty(this.superClass, name))) {
					return Reflect.getProperty(this.superClass, name);
				} else if (Reflect.hasField(this.superClass, name)) {
					return Reflect.field(this.superClass, name);
				} else if (this.superClass != null && (this.superClass is CustomClass)) {
					var superScriptClass:CustomClass = cast(this.superClass, CustomClass);
					try {
						return superScriptClass.hget(name);
					} catch (e:Dynamic) {}
				} else {
					var superField = Type.getInstanceFields(Type.getClass(this.superClass)).find((f) -> return f == name);

					if(superField != null) {
						return Reflect.getProperty(this.superClass, superField);
					}
				}
		}

		if (this.superClass == null) {
			throw "field '" + name + "' does not exist in script class '" + this.className + "'";
		} else {
			throw "field '" + name + "' does not exist in script class '" + this.className + "' or super class '"
				+ Type.getClassName(Type.getClass(this.superClass)) + "'";
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
