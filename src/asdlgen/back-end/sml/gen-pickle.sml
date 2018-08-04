(* gen-pickle.sml
 *
 * COPYRIGHT (c) 2018 The Fellowship of SML/NJ (http://www.smlnj.org)
 * All rights reserved.
 *
 * Generate the pickling code for the SML view
 *)

structure GenPickle : sig

  (* generate the signature for the pickler structure *)
    val genSig : AST.module -> SML.top_decl

  (* generate the pickler structure *)
    val genStr : AST.module -> SML.top_decl

  end = struct

    structure PT = PrimTypes
    structure V = SMLView
    structure ModV = V.Module
    structure TyV = V.Type
    structure ConV = V.Constr
    structure E = Encoding
    structure S = SML

  (***** Signature generation *****)

    fun genSig (AST.Module{isPrim=false, id, decls}) = let
	  val typeModName = ModV.getName id
	  val sigName = Util.sigName(ModV.getPickleName id, NONE)
	  val specs = List.foldr (genSpec typeModName) [] (!decls)
	  in
	    S.SIGtop(sigName, S.BASEsig specs)
	  end
      | genSig _ = raise Fail "genSig: unexpected primitive module"

  (* generate the encoder/decoder specifications for a type *)
    and genSpec modName (AST.TyDcl{id, ...}, specs) = let
	  val ty = S.CONty([], TyV.getName id)
	  val bufTy = S.CONty([], "Word8Buffer.buf")
	  val vecTy = S.CONty([], "Word8Vector.vector")
	  val sliceTy = S.CONty([], "Word8VectorSlice.slice")
	  val unitTy = S.CONty([], "unit")
	(* encoder *)
	  val encTy = S.FUNty(S.TUPLEty[bufTy, ty], unitTy)
	  val encSpc = S.VALspec(TyV.getEncoder id, encTy)
	(* decoder *)
	  val decTy = S.FUNty(sliceTy, S.TUPLEty[ty, sliceTy])
	  val decSpc = S.VALspec(TyV.getDecoder id, decTy)
	  in
	    encSpc :: decSpc :: specs
	  end

  (***** Structure generation *****)

  (* generate a simple application *)
    fun funApp (f, args) = S.appExp(S.IDexp f, S.tupleExp args)
  (* pairs *)
    fun pairPat (a, b) = S.TUPLEpat[a, b]
    fun pairExp (a, b) = S.TUPLEexp[a, b]

    fun genStr (AST.Module{isPrim=false, id, decls}) = let
	  val typeModName = ModV.getName id
	  val pickleModName = ModV.getPickleName id
	  val sigName = Util.sigName(pickleModName, NONE)
	  fun genGrp (dcls, dcls') = S.FUNdec(List.foldr genType [] dcls) :: dcls'
	  val decls = List.foldr genGrp [] (SortDecls.sort (!decls))
	  val decls = S.VERBdec[Fragments.pickleUtil] :: decls
	  in
	    S.STRtop(pickleModName, SOME(false, S.IDsig sigName), S.BASEstr decls)
	  end
      | genStr _ = raise Fail "genStr: unexpected primitive module"

    and genType (dcl, fbs) = let
	  val (id, encoding) = E.encoding dcl
	  val name = TyV.getName id
	  in
	    genEncoder (TyV.getEncoder id, encoding) ::
	    genDecoder (TyV.getDecoder id, encoding) ::
	      fbs
	  end

    and genEncoder (encName, encoding) = let
	  val bufV = S.IDexp "buf"
	  fun baseEncode (NONE, tyId) = TyV.getEncoder tyId
	    | baseEncode (SOME modId, tyId) = concat[
		  ModV.getPickleName modId, ".", TyV.getEncoder tyId
		]
	  fun gen (arg, E.SWITCH(ncons, rules)) = let
	      (* determine the "type" of the tag *)
		val tagTyId = if (ncons <= 256) then PT.tag8TyId
		      else if (ncons <= 65536) then PT.tag16TyId
		      else raise Fail "too many constructors"
		in
		  S.caseExp(arg, List.map (genRule tagTyId) rules)
		end
	    | gen (arg, E.TUPLE tys) = let
		fun encode (i, ty) = gen (S.selectExp(Int.toString i, arg), ty)
		in
		  S.SEQexp(List.mapi encode tys)
		end
	    | gen (arg, E.RECORD fields) = let
		fun encode (lab, ty) = gen (S.selectExp(lab, arg), ty)
		in
		  S.SEQexp(List.map encode fields)
		end
	    | gen (arg, E.OPTION ty) =
		S.appExp(
		  funApp ("encode_option", [S.IDexp(baseEncode ty)]),
		  pairExp(bufV, arg))
	    | gen (arg, E.SEQUENCE ty) =
		S.appExp(
		  funApp ("encode_list", [S.IDexp(baseEncode ty)]),
		  pairExp(bufV, arg))
	    | gen (arg, E.SHARED ty) = raise Fail "shared types not supported yet"
	    | gen (arg, E.BASE ty) = funApp (baseEncode ty, [bufV, arg])
	  and genRule tagTyId (tag, conId, optArg) = let
		val encTag = funApp(
		      baseEncode(SOME PT.primTypesId, tagTyId),
		      [bufV, S.NUMexp("0w" ^ Int.toString tag)])
		val conName = ConV.getName conId
		in
		  case optArg
		   of NONE => (S.IDpat conName, encTag)
		    | SOME(E.TUPLE tys) => let
			val args = List.mapi (fn (i, _) => "x"^Int.toString i) tys
			val pat = S.CONpat(
			      conName,
			      S.tuplePat(List.map S.IDpat args))
			val exp = S.SEQexp(encTag :: ListPair.map gen' (args, tys))
			in
			  (pat, exp)
			end
		    | SOME(E.RECORD flds) => let
			val pat = S.CONpat(
			      conName,
			      S.RECORDpat{
				  fields = List.map (fn fld => (#1 fld, S.IDpat(#1 fld))) flds,
				  flex = false
				})
			val exp = S.SEQexp(encTag :: List.map gen' flds)
			in
			  (pat, exp)
			end
		    | SOME ty => (S.CONpat(conName, S.IDpat "x"), S.SEQexp[encTag, gen'("x", ty)])
		  (* end case *)
		end
	  and gen' (x, ty) = gen (S.IDexp x, ty)
	  in
	    S.simpleFB(encName, ["buf", "obj"], gen(S.IDexp "obj", encoding))
	  end

    and genDecoder (decName, encoding) = let
	  val sliceP = S.IDpat "slice"
	  val sliceV = S.IDexp "slice"
	  fun baseDecode (NONE, tyId) = TyV.getDecoder tyId
	    | baseDecode (SOME modId, tyId) = concat[
		  ModV.getPickleName modId, ".", TyV.getDecoder tyId
		]
	  fun gen (E.SWITCH(ncons, rules)) = let
	      (* determine the "type" of the tag *)
		val tagTyId = if (ncons <= 256) then PT.tag8TyId
		      else if (ncons <= 65536) then PT.tag16TyId
		      else raise Fail "too many constructors"
		val decodeTag = funApp(
		      baseDecode(SOME PT.primTypesId, tagTyId),
		      [sliceV])
		val dfltRule = (S.WILDpat, S.raiseExp(S.IDexp "ASDL.DecodeError"))
		in
		  S.caseExp(decodeTag, List.map genRule rules @ [dfltRule])
		end
	    | gen (E.TUPLE tys) = genTuple (tys, fn x => x)
	    | gen (E.RECORD fields) = genRecord (fields, fn x => x)
	    | gen (E.OPTION ty) =
		S.appExp(
		  funApp ("decode_option", [S.IDexp(baseDecode ty)]),
		  sliceV)
	    | gen (E.SEQUENCE ty) =
		S.appExp(
		  funApp ("decode_list", [S.IDexp(baseDecode ty)]),
		  sliceV)
	    | gen (E.SHARED ty) = raise Fail "shared types not supported yet"
	    | gen (E.BASE ty) = funApp (baseDecode ty, [sliceV])
	  and genRule (tag, conId, optArg) = let
		val conName = ConV.getName conId
		val pat = pairPat(S.NUMpat("0w"^Int.toString tag), sliceP)
		in
		  case optArg
		   of NONE => (pat, pairExp(S.IDexp conName, sliceV))
		    | SOME(E.TUPLE tys) =>
			(pat, genTuple(tys, fn x => S.appExp(S.IDexp conName, x)))
		    | SOME(E.RECORD fields) =>
			(pat, genRecord(fields, fn x => S.appExp(S.IDexp conName, x)))
		    | SOME ty => (pat, gen ty)
		  (* end case *)
		end
	  and genTuple (tys, k) = let
		val xs = List.mapi (fn (i, _) => "x"^Int.toString i) tys
		val decs = ListPair.map
		      (fn (x, ty) => S.VALdec(pairPat(S.IDpat x, sliceP), gen ty))
			(xs, tys)
		in
		  S.LETexp(decs, pairExp (k(S.TUPLEexp(List.map S.IDexp xs)), sliceV))
		end
	  and genRecord (fields, k) = let
		val decs = List.map
		      (fn (lab, ty) => S.VALdec(pairPat(S.IDpat lab, sliceP), gen ty))
			fields
		val fields = List.map (fn (lab, _) => (lab, S.IDexp lab)) fields
		in
		  S.LETexp(decs, pairExp (k(S.RECORDexp fields), sliceV))
		end
	  in
	    S.simpleFB(decName, ["slice"], gen encoding)
	  end

  end
