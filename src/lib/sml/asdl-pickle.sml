(* asdl-pickle.sml
 *
 * COPYRIGHT (c) 2018 The Fellowship of SML/NJ (http://www.smlnj.org)
 * All rights reserved.
 *)

structure ASDLPickle : ASDL_PICKLE =
  struct

    structure W = Word
    structure W8 = Word8
    structure W8B = Word8Buffer
    structure W8S = Word8VectorSlice

    val << = W.<< and >> = W.>>
    val ++ = W.orb
    val & = W.andb
    val !! = W.notb
    infix 5 << >>
    infix 6 ++
    infix 7 &

    fun toByte w = W8.fromLarge (W.toLarge w)
    fun fromByte b = W.fromLarge (W8.toLarge b)

    fun getByte slice = (case W8S.getItem slice
	   of SOME(b, slice) => (fromByte b, slice)
	    | NONE => raise ASDL.DecodeError
	  (* end case *))

    fun encodeBool (buf, false) = W8B.add1(buf, 0w0)
      | encodeBool (buf, true) = W8B.add1(buf, 0w1)

    fun decodeBool slice = (case W8S.getItem slice
	   of SOME(0w0, slice) => (false, slice)
	    | SOME(0w1, slice) => (true, slice)
	    | _ => raise ASDL.DecodeError
	  (* end case *))

  (* encode an unsigned signed integer.  We assume that the value is in the
   * range 0..2^30 - 1
   *)
    fun encodeUInt (buf, w) = if (w <= 0wx3f)
	    then W8B.add1(buf, toByte w)
	  else if (w <= 0wx3fff)
	    then ( (* two bytes *)
	      W8B.add1(buf, toByte(0wx40 ++ (w >> 0w8)));
	      W8B.add1(buf, toByte w))
	  else if (w <= 0wx3fffff)
	    then ( (* three bytes *)
	      W8B.add1(buf, toByte(0wx80 ++ (w >> 0w16)));
	      W8B.add1(buf, toByte(w >> 0w8));
	      W8B.add1(buf, toByte w))
	    else ( (* four bytes *)
	      W8B.add1(buf, toByte(0wxc0 ++ (w >> 0w24)));
	      W8B.add1(buf, toByte(w >> 0w16));
	      W8B.add1(buf, toByte(w >> 0w8));
	      W8B.add1(buf, toByte w))

    fun decodeUInt slice = let
	  val (b0, slice) = getByte slice
	  val nb = b0 & 0wxc0
	  val res = b0 & 0wx3f
	  in
	    if (nb = 0w0) then (res, slice)
	    else let
	      val (b1, slice) = getByte slice
	      val res = (res << 0w8) + b1
	      in
		if (nb = 0wx40) then (res, slice)
		else let
		  val (b2, slice) = getByte slice
		  val res = (res << 0w8) + b2
		  in
		    if (nb = 0wx80) then (res, slice)
		    else let
		      val (b3, slice) = getByte slice
		      in
			((res << 0w8) + b3, slice)
		      end
		  end
	      end
	  end

  (* encode a signed integer.  We assume that the value is in the range -2^29..2^29 - 1 *)
    fun encodeInt (buf, n) = let
	  val (sign, w) = if (n < 0)
		then (0wx20, W.fromInt(~(n+1)))
		else (0w0, Word.fromInt n)
	  in
	    if (w <= 0wx1f)
	      then W8B.add1(buf, toByte(sign ++ w))
	    else if (w <= 0wx1fff)
	      then ( (* two bytes *)
		W8B.add1(buf, toByte(0wx40 ++ sign ++ (w >> 0w8)));
		W8B.add1(buf, toByte w))
	    else if (w <= 0wx1fffff)
	      then ( (* three bytes *)
		W8B.add1(buf, toByte(0wx80 ++ sign ++ (w >> 0w16)));
		W8B.add1(buf, toByte(w >> 0w8));
		W8B.add1(buf, toByte w))
	      else ( (* four bytes *)
		W8B.add1(buf, toByte(0wxc0 ++ sign ++ (w >> 0w24)));
		W8B.add1(buf, toByte(w >> 0w16));
		W8B.add1(buf, toByte(w >> 0w8));
		W8B.add1(buf, toByte w))
	  end

    fun decodeInt slice = let
	  val (b0, slice) = getByte slice
	  val nb = b0 & 0wxc0
	  val isNeg = (b0 & 0wx20 <> 0w0)
	  val res = b0 & 0wx1f
	  fun return (w, slice) = if (b0 & 0wx20 <> 0w0)
		then (~(Word.toIntX w)-1, slice)
		else (Word.toIntX w, slice)
	  in
	    if (nb = 0w0) then return(res, slice)
	    else let
	      val (b1, slice) = getByte slice
	      val res = (res << 0w8) + b1
	      in
		if (nb = 0wx40) then return(res, slice)
		else let
		  val (b2, slice) = getByte slice
		  val res = (res << 0w8) + b2
		  in
		    if (nb = 0wx80) then return(res, slice)
		    else let
		      val (b3, slice) = getByte slice
		      in
			return((res << 0w8) + b3, slice)
		      end
		  end
	      end
	  end

    fun encodeInteger (buf, i) = raise Fail "FIXME"
    fun decodeInteger slice = raise Fail "FIXME"

    fun encodeString (buf, s) = (
	  encodeUInt(buf, Word.fromInt(size s));
	  W8B.addVec(buf, Byte.stringToBytes s))

    fun decodeString slice = let
	  val (len, slice) = decodeUInt slice
	  val len = W.toIntX len
	  val _ = if W8S.length slice < len then raise ASDL.DecodeError else ()
	  val str = Byte.unpackStringVec(W8S.subslice(slice, 0, SOME len))
	  val rest = W8S.subslice(slice, len, NONE)
	  in
	    (str, rest)
	  end

    fun encodeIdentifier (buf, id) = encodeString (buf, Atom.toString id)

    fun decodeIdentifier slice = let
	  val (s, rest) = decodeString slice
	  in
	    (Atom.atom s, rest)
	  end

  (* utility functions for sum-type tags *)
    fun encodeTag8 (buf, tag) = W8B.add1(buf, toByte tag)
    fun decodeTag8 slice = getByte slice
    fun encodeTag16 (buf, tag) = (
	  W8B.add1(buf, toByte(tag >> 0w8));
	  W8B.add1(buf, toByte tag));
    fun decodeTag16 slice = let
	  val (b0, slice) = getByte slice
	  val (b1, slice) = getByte slice
	  in
	    ((b0 << 0w8) ++ b1, slice)
	  end

  end
