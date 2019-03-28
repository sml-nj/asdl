(* sml-view.sml
 *
 * COPYRIGHT (c) 2018 The Fellowship of SML/NJ (http://www.smlnj.org)
 * All rights reserved.
 *
 * The "Sml" view.
 *)

structure SMLView : sig

    val view : View.t

    structure File : VIEW_FILE_BASE

    structure Module : sig
	include VIEW_MODULE_BASE
      (* name of pickler signature *)
        val getPickleSigName : AST.ModuleId.t -> string
      (* name of pickler module *)
	val getPickleName : AST.ModuleId.t -> string
      (* name of pickle-io module *)
	val getIOName : AST.ModuleId.t -> string
      (* name of S-expression pickle module *)
        val getSExpName : AST.ModuleId.t -> string
      end

    structure Type : VIEW_TYPE_BASE

    structure Constr : VIEW_CONSTR_BASE

  end = struct

    structure CV = CommonView
    structure PN = PropNames
    structure PTy = PrimTypes

    structure ViewBase = ViewBaseFn (
      struct
	val viewName = "Sml"
	val template =  {
		fileProps = #fileProps CV.template,
		moduleProps =
		  CV.prop(PN.pickler_name, false) ::
		  CV.prop(PN.io_name, false) ::
		  #moduleProps CV.template,
		typeProps = #typeProps CV.template,
		consProps = #consProps CV.template
	      }
(* FIXME: add conversion to camlCase *)
	fun mkFunName {operation, ty} = String.concat[operation, "_", ty]
      end)

    open ViewBase

    structure Module =
      struct
	open ViewBase.Module

	local
	  fun getModName (prop, suffix) modId = (
		case View.getOptValue prop (view, View.Module modId)
		 of NONE => getName modId ^ suffix
		  | SOME[name] => name
		  | _ => raise Fail("unexpected multiple values for "^Atom.toString prop)
		(* end case *))
	in
        val getPickleSigName = getModName (PN.pickler_name, "Pickle")
	val getPickleName = getModName (PN.pickler_name, "Pickle")
	val getIOName = getModName (PN.io_name, "PickleIO")
	val getSExpName = getModName (PN.sexp_pickle_name, "SExpPickleIO")
	end (* local *)

      end

  (* the default header template *)
    val header =
	  "(* @FILENAME@\n\
	  \ *\n\
	  \ * Generated from @SRCFILE@ by asdlgen.\n\
	  \ *)\n"

  (* set the default header property *)
    val () = let
	  val SOME prop = View.findProp(view, View.File, Atom.atom "header")
	  in
	    View.Prop.setValue(prop, header)
	  end

  (* set the default properties for the ASDL primitive types *)
    val () = let
	    fun set (id, propName, name) = let
		  val SOME prop = View.findProp(view, View.Type id, propName)
		  in
		    View.Prop.setValue(prop, name)
		  end
	    in
	      List.app set [
		  (PTy.boolTyId,	PN.name,	"bool"),
		  (PTy.boolTyId,	PN.encoder,	"encodeBool"),
		  (PTy.boolTyId,	PN.decoder,	"decodeBool"),
		  (PTy.boolTyId,	PN.writer,	"writeBool"),
		  (PTy.boolTyId,	PN.reader,	"readBool"),
		  (PTy.intTyId,		PN.name,	"int"),
		  (PTy.intTyId,		PN.encoder,	"encodeInt"),
		  (PTy.intTyId,		PN.decoder,	"decodeInt"),
		  (PTy.intTyId,		PN.writer,	"writeInt"),
		  (PTy.intTyId,		PN.reader,	"readInt"),
		  (PTy.uintTyId,	PN.name,	"word"),
		  (PTy.uintTyId,	PN.encoder,	"encodeUInt"),
		  (PTy.uintTyId,	PN.decoder,	"decodeUInt"),
		  (PTy.uintTyId,	PN.writer,	"writeUInt"),
		  (PTy.uintTyId,	PN.reader,	"readUInt"),
		  (PTy.integerTyId,	PN.name,	"IntInf.int"),
		  (PTy.integerTyId,	PN.encoder,	"encodeInteger"),
		  (PTy.integerTyId,	PN.decoder,	"decodeInteger"),
		  (PTy.integerTyId,	PN.writer,	"writeInteger"),
		  (PTy.integerTyId,	PN.reader,	"readInteger"),
		  (PTy.identifierTyId,	PN.name,	"Atom.atom"),
		  (PTy.identifierTyId,	PN.encoder,	"encodeIdentifier"),
		  (PTy.identifierTyId,	PN.decoder,	"decodeIdentifier"),
		  (PTy.identifierTyId,	PN.writer,	"writeIdentifier"),
		  (PTy.identifierTyId,	PN.reader,	"readIdentifier"),
		  (PTy.stringTyId,	PN.name,	"string"),
		  (PTy.stringTyId,	PN.encoder,	"encodeString"),
		  (PTy.stringTyId,	PN.decoder,	"decodeString"),
		  (PTy.stringTyId,	PN.writer,	"writeString"),
		  (PTy.stringTyId,	PN.reader,	"readString"),
		  (PTy.tag8TyId,	PN.encoder,	"encodeTag8"),
		  (PTy.tag8TyId,	PN.decoder,	"decodeTag8"),
		  (PTy.tag8TyId,	PN.writer,	"writeTag8"),
		  (PTy.tag8TyId,	PN.reader,	"readTag8"),
		  (PTy.tag16TyId,	PN.encoder,	"encodeTag16"),
		  (PTy.tag16TyId,	PN.decoder,	"decodeTag16"),
		  (PTy.tag16TyId,	PN.writer,	"writeTag16"),
		  (PTy.tag16TyId,	PN.reader,	"readTag16")
		]
	    end

  (* set the default names for the ASDL primitive-types module *)
    val () = let
	    val primMod = View.Module PrimTypes.primTypesId
	    fun set (propName, name) = let
		  val SOME prop = View.findProp(view, primMod, propName)
		  in
		    View.Prop.setValue(prop, name)
		  end
	    in
	      List.app set [
		  (PN.name,		"ASDL"),
		  (PN.pickler_name,	"ASDLPickle"),
		  (PN.io_name,		"ASDLPickleIO")
		]
	    end

  end
