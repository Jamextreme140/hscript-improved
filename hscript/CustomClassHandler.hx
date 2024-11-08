package hscript;

import hscript.Interp.DeclaredVar;
import hscript.utils.UnsafeReflect;
using StringTools;

class CustomClassHandler implements IHScriptCustomConstructor {
	public static var staticHandler = new StaticHandler();

	public var ogInterp:Interp;
	public var name:String;
	public var fields:Array<Expr>;
	public var extend:String;
	public var interfaces:Array<String>;

	public var cl:Class<Dynamic>;

	public function new(ogInterp:Interp, name:String, fields:Array<Expr>, ?extend:String, ?interfaces:Array<String>) {
		this.ogInterp = ogInterp;
		this.name = name;
		this.fields = fields;
		this.extend = extend;
		this.interfaces = interfaces;

		this.cl = extend == null ? TemplateClass : Type.resolveClass('${extend}_HSX');
		if(cl == null)
			ogInterp.error(EInvalidClass(extend));
	}

	public function hnew(args:Array<Dynamic>):Dynamic {
		// TODO: clean this up, it sucks, i hate it
		// TODO: make static vars work correctly

		var _superClass = new CustomClassSuper(cl);
		var _class:IHScriptCustomClassBehaviour = cast _superClass;//Type.createInstance(cl, args);
		var disallowCopy = Type.getInstanceFields(cl);

		// INTERPRETER THING
		var interp = new Interp();

		interp.errorHandler = ogInterp.errorHandler;
		// todo: make it so you can use variables from the same scope as where the class was defined

		//for (key => value in capturedLocals) {
		//	if(!disallowCopy.contains(key)) {
		//		interp.locals.set(key, {r: value, depth: -1});
		//	}
		//}

		for (key => value in ogInterp.variables) {
			if(!disallowCopy.contains(key)) {
				interp.variables.set(key, value);
			}
		}
		for(key => value in ogInterp.customClasses) {
			if(!disallowCopy.contains(key)) {
				interp.customClasses.set(key, value);
			}
		}

		interp.variables.set("super", _superClass);

		for(expr in fields) {
			@:privateAccess
			interp.exprReturn(expr);
		}

		var newFunc = interp.variables.get("new");
		if(newFunc != null) {
			var comparisonMap:Map<String, Dynamic> = [];
			for(key => value in interp.variables) {
				comparisonMap.set(key, value);
			}

			UnsafeReflect.callMethodUnsafe(null, newFunc, args);

			// get only variables that were not set before
			var classVariables = [
				for(key => value in interp.variables)
					if(!comparisonMap.exists(key) || comparisonMap[key] != value)
						key => value
			];
			for(variable => value in classVariables) {
				if(variable == "this" || variable == "super" || variable == "new") continue;
				@:privateAccess
				if(!interp.__instanceFields.contains(variable)) {
					interp.__instanceFields.push(variable);
				}
				if(!_class.__class__fields.contains(variable)) {
					_class.__class__fields.push(variable);
				}
			}
		}

		var comparisonMap:Map<String, Dynamic> = [];
		for(key => value in interp.variables) {
			comparisonMap.set(key, value);
		}

		// get only variables that were not set before
		var classVariables = [
			for(key => value in interp.variables)
				if(!comparisonMap.exists(key) || comparisonMap[key] != value)
					key => value
		];

		//var __capturedLocals = ogInterp.duplicate(ogInterp.locals);
		//var capturedLocals:Map<String, DeclaredVar> = [];
		//for(k=>e in __capturedLocals)
		//	if (e != null && e.depth <= 0)
		//		capturedLocals.set(k, e);

		// CUSTOM CLASS THING
		
		_class.__real_fields = disallowCopy;
		
		// todo: clone static vars, but make it so setting it only sets it on the class
		// todo: clone public vars

		//trace("Before: " + [for(key => value in interp.variables) key]);

		_class.__custom__variables = interp.variables;

		//trace(fields);

		//trace("After: " + [for(key => value in interp.variables) key]);
		
		//for(variable => value in classVariables) {
		//	if(variable == "this" || variable == "super" || variable == "new") continue;
		//	@:privateAccess
		//	if(!interp.__instanceFields.contains(variable)) {
		//		interp.__instanceFields.push(variable);
		//	}
		//}

		_class.__class__fields = [for(key => value in classVariables) key];

		//trace(_class.__class__fields);
		//@:privateAccess
		//trace(interp.__instanceFields);

		_class.__interp = interp;
		_class.__allowSetGet = false;
		interp.scriptObject = _class;

		for(variable => value in interp.variables) {
			if(variable == "this" || variable == "super" || variable == "new") continue;

			if(variable.startsWith("set_") || variable.startsWith("get_")) {
				_class.__allowSetGet = true;
			}
		}

		return _class;
	}

	public function toString():String {
		return name;
	}
}

abstract CustomClassSuper(Class<Dynamic>) from Class<Dynamic> {
	
	public function new(superClass:Class<Dynamic>) {
		this = superClass;
	}

	@:op(a()) public function getConstructNoArgs() {
		return Type.createInstance(this, []);
	}

	@:op(a()) public function getConstruct(...args:Any) {
		return Type.createInstance(this, args.toArray());
	}

	@:op(a.b) public function resolve(value:String) {
		return Reflect.field(this, value);
	}
}

class TemplateClass implements IHScriptCustomClassBehaviour implements IHScriptCustomBehaviour {
	public var __interp:Interp;
	public var __allowSetGet:Bool = true;
	public var __custom__variables:Map<String, Dynamic>;
	public var __real_fields:Array<String>;
	public var __class__fields:Array<String>;

	public function hset(name:String, val:Dynamic):Dynamic {
		if(__allowSetGet && __custom__variables.exists("set_" + name))
			return __callSetter(name, val);
		if (__custom__variables.exists(name)) {
			__custom__variables.set(name, val);
			return val;
		}
		if(__real_fields.contains(name)) {
			UnsafeReflect.setProperty(this, name, val);
			return UnsafeReflect.field(this, name);
		}
		__custom__variables.set(name, val);
		return val;
	}
	public function hget(name:String):Dynamic {
		if(__allowSetGet && __custom__variables.exists("get_" + name))
			return __callGetter(name);
		if (__custom__variables.exists(name))
			return __custom__variables.get(name);

		return UnsafeReflect.getProperty(this, name);
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
}

final class StaticHandler {
	public function new() {}
}