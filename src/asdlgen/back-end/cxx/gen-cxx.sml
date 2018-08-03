(* gen-cxx.sml
 *
 * COPYRIGHT (c) 2018 The Fellowship of SML/NJ (http://www.smlnj.org)
 * All rights reserved.
 *
 * Generate the C++ view of the ASDL modules.
 *)

structure GenCxx : sig

    val gen : {src : string, dir : string, stem : string, modules : AST.module list} -> unit

  end = struct

    structure Cons = ASDL.Constr
    structure CL = CLang

    type code = {
	hxx : CL.decl list,
	cxx : CL.decl list
      }

  (* include directives to include in the .hxx and .cxx files *)
    val hxxIncls = CL.D_Verbatim[
	    "#include \"asdl/asdl.hxx\"\n",
	  ]
    val cxxIncls = CL.D_Verbatim[
	    "#include \"@HXX_FILENAME@\"\n",
	  ]

  (* output C++ declarations to a file *)
    fun output (src, outFile, dcls) = let
	  val outS = TextIO.openOut outFile
(* FIXME: output width is a command-line option! *)
	  val ppStrm = TextIOPP.openOut {dst = outS, wid = Options.lineWidth()}
	  in
	    List.app
	      (fn dcl => (PrintAsCxx.output (ppStrm, dcl)))
		(genHeader (src, outFile) :: dcls);
	    TextIOPP.closeStream ppStrm;
	    TextIO.closeOut outS
	  end

  (* generate a file using the given code generator *)
    fun genFile codeGen (src, outFile, modules) =
	  output (src, outFile, List.map codeGen modules)

  (* generate C++ code for the given list of modules using the "Cxx" view *)
    fun gen {src, dir, stem, modules} = let
	  val basePath = OS.Path.joinDirFile{dir=dir, file=stem}
	  fun cxxFilename name = OS.Path.joinBaseExt{base=name, ext=SOME "cxx"}
	  fun hxxFilename name = OS.Path.joinBaseExt{base=name, ext=SOME "hxx"}
	  in
	  (* generate the header file *)
	    genFile GenTypes.gen (src, hxxFilename basePath, modules);
	  (* generate the pickler implementation *)
	    genFile GenPickler.gen (src, cxxFilename(basePath ^ "-pickle"), modules)
	  end

  end
