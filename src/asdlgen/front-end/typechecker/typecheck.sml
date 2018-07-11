(* typecheck.sml
 *
 * COPYRIGHT (c) 2018 The Fellowship of SML/NJ (http://www.smlnj.org)
 * All rights reserved.
 *)

structure Typecheck : sig

    val check : {
	    includes : Parser.file list,
	    file : Parser.file
	  } -> {
	    modules : AST.module list
(* some other stuff too *)
	  }

  end = struct

    structure PT = ParseTree

    fun markCxt ((errStrm, _), span) = (errStrm, span)

    fun withMark (cxt, env, {span, tree}) = (markCxt(cxt, span), env, tree)
    fun withMark' (cxt, {span, tree}) = (markCxt(cxt, span), tree)

    datatype token = S of string | A of Atom.atom | I of {tree : Atom.atom, span : Error.span}

    fun err ((errStrm, span), toks) = let
	  fun tok2str (S s) = s
	    | tok2str (A a) = Atom.toString a
	    | tok2str (I{tree, ...}) = Atom.toString tree
	  in
	    Error.errorAt(errStrm, span, List.map tok2str toks)
	  end

  (* a bogus type to return when there is an error *)
    val bogusTypeId = AST.TypeId.new (Atom.atom "**bogus**")
    val bogusType = AST.BaseTy bogusTypeId

  (* check for duplicate names in a list of named values *)
    fun anyDups getName = let
	  fun test a = let val a' = getName a in fn b => Atom.same(a', getName b) end
	  fun chk [] = NONE
	    | chk (x::xs) = if List.exists (test x) xs
		then SOME x
		else chk xs
	  in
	    chk
	  end

  (* check a top-level definition (module, primitive module, or view) *)
    fun checkTop (cxt, env, PT.D_Mark m) =
	  checkTop (withMark (cxt, env, m))
      | checkTop (cxt, env, PT.D_Module{name, imports, decls}) = (
	  case Env.findModule(env, #tree name)
	   of SOME _ => (
		err (markCxt(cxt, #span name), [S "module '", I name, S "' is already defined"]);
		NONE)
	    | NONE => checkModule (cxt, env, #tree name, imports, decls)
	  (* end case *))
      | checkTop (cxt, env, PT.D_Primitive{name, exports}) = (
	  case Env.findModule(env, #tree name)
	   of SOME _ => (
		err (markCxt(cxt, #span name), [S "module '", I name, S "' is already defined"]);
		NONE)
	    | NONE => checkPrimModule (cxt, env, #tree name, exports)
	  (* end case *))
      | checkTop (cxt, env, PT.D_View{name, entries}) = raise Fail "FIXME: view"

    and checkModule (cxt, gEnv, name, imports, decls) = let
	  val id = AST.ModuleId.new name
	  in
	    Env.withModule (gEnv, id, fn env => let
	      val _ = List.app (fn im => checkImport(cxt, gEnv, env, im)) imports
	      val declsRef = ref[]
	      val module = AST.Module{
		      isPrim = false,
		      id = id,
		      decls = declsRef
		    }
	      val decls = List.mapPartial (fn dcl => checkTyDecl (cxt, env, dcl)) decls
	      in
		declsRef := decls;
		AST.ModuleId.bind(id, module);
		SOME module
	      end)
	  end

  (* typecheck a module's import declaration, where `gEnv` is the global environment
   * where we look up imports and `env` is the environment where we add them.
   *)
    and checkImport (cxt, gEnv, env, PT.Import_Mark{span, tree}) =
	  checkImport (markCxt(cxt, span), gEnv, env, tree)
      | checkImport (cxt, gEnv, env, PT.Import{module, alias}) = (
	  case Env.findModule (gEnv, #tree module)
	   of SOME id => (case alias
		 of NONE => Env.addImport(env, #tree module, id)
		  | SOME m => Env.addImport(env, #tree m, id)
		(* end case *))
	    | NONE => err (markCxt(cxt, #span module), [S "unknown module '", I module, S "'"])
	  (* end case *))

  (* typecheck a type declaration in a module.  Things to check for:
   *	- multiple definitions of same type name
   *	- multiple definitions of constructor names
   *	- enumeration types
   *)
    and checkTyDecl (cxt, env, tyDcl) = let
	  in
	    case tyDcl
	     of PT.TD_Mark m => checkTyDecl (withMark (cxt, env, m))
	      | PT.TD_Sum{name, attribs, cons} => raise Fail "FIXME"
	      | PT.TD_Product{name, fields} => raise Fail "FIXME"
	    (* end case *)
	  end

  (* check a list of fields (including checking for duplicate field names).  The
   * `attribs` list is a list of previously checked attributes (for sum types).
   *)
    and checkFields (cxt, env, attribs, fields) = let
	  fun chkField (cxt, PT.Field_Mark m) = chkField (withMark' (cxt, m))
	    | chkField (cxt, PT.Field{module, typ, tycon, label}) = raise Fail "FIXME"
	  in
	    attribs @ List.map (fn fld => chkField (cxt, fld)) fields
	  end

  (* check a type expression, where the module name and tycon are optional *)
    and checkTy (cxt, env, module, typ : PT.id, tycon) = let
	  fun chkTy modId = (case Env.findType (env, modId, #tree typ)
		 of SOME ty => (case tycon
		       of NONE => AST.Typ ty
			| SOME PT.Optional => AST.OptTy ty
			| SOME PT.Sequence => AST.SeqTy ty
			| SOME PT.Shared => AST.SharedTy ty
		      (* end case *))
		  | NONE => (
		      err (cxt, [
			  S "unknown type '",
			  case modId
			   of SOME id => S(AST.ModuleId.nameOf id ^ ".")
			    | _ => S ""
			  (* end case *),
			  I typ, S "'"
			]);
		      AST.Typ bogusType)
		(* end case *))
	  in
	    case module
	     of SOME{span, tree} => (case Env.findModule(env, tree)
		   of NONE => (
			err (markCxt(cxt, span), [S "unknown module '", A tree, S "'"]);
			AST.Typ bogusType)
		    | someId => chkTy someId
		  (* end case *))
	      | NONE => chkTy NONE
	    (* end case *)
	  end

    and checkPrimModule (cxt, gEnv, name, exports) = let
	  val id = AST.ModuleId.new name
	  in
	    Env.withModule (gEnv, id, fn env => let
	      val declsRef = ref[]
	      val module = AST.Module{
		      isPrim = true,
		      id = id,
		      decls = declsRef
		    }
(* check for duplicate exports *)
	      fun checkExport ({span, tree}, dcls) = let
		    val tyId = AST.TypeId.new tree
		    in
		      AST.TyDcl{id = tyId, def = ref AST.PrimTy, owner = module} :: dcls
		    end
	      val decls = List.foldr checkExport [] exports
	      in
		declsRef := decls;
		AST.ModuleId.bind(id, module);
		SOME module
	      end)
	  end

    (* typechecker for an ASDL specification *)
    fun check { includes, file } = let
	  val env = Env.new()
	(* check an include file *)
	  fun checkInclude {name, errStrm, decls} =
		List.app (fn dcl => ignore (checkTop ((errStrm, (0, 0)), env, dcl))) decls
	(* check the ASDL specification file *)
	  val modules = let
		val {name, errStrm, decls} = file
		fun chk dcl = checkTop ((errStrm, (0, 0)), env, dcl)
		in
		  List.mapPartial chk decls
		end
	  in {
	    modules = modules
(* FIXME: what about the views? *)
	  } end

  end