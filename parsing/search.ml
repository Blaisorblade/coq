
(* $Id$ *)

open Pp
open Util
open Names
open Term
open Declarations
open Libobject
open Declare
open Coqast
open Astterm
open Pretty
open Environ
open Pattern
open Printer

(* The functions print_constructors and crible implement the behavior needed
   for the Coq searching commands.
   These functions take as first argument the procedure
   that will be called to treat each entry.  This procedure receives the name
   of the object, the assumptions that will make it possible to print its type,
   and the constr term that represent its type. *)

let print_constructors indsp fn env_ar mip =
  let lc = mind_user_lc mip in
  for i=1 to Array.length lc do
      fn (ConstructRef (indsp,i)) env_ar (lc.(i-1))
  done

let rec head_const c = match kind_of_term c with
  | IsProd (_,_,d) -> head_const d
  | IsLetIn (_,_,_,d) -> head_const d
  | IsApp (f,_)   -> head_const f
  | IsCast (d,_)   -> head_const d
  | _            -> c

let crible (fn : global_reference -> env -> constr -> unit) ref =
  let env = Global.env () in
  let imported = Library.opened_modules() in
  let const = constr_of_reference Evd.empty env ref in 
  let crible_rec sp lobj =
    match object_tag lobj with
      | "VARIABLE" ->
	  (try 
	     let ((idc,_,typ),_,_) = get_variable sp in 
             if (head_const typ) = const then fn (VarRef sp) env typ
	   with Not_found -> (* we are in a section *) ())
      | "CONSTANT" 
      | "PARAMETER" ->
	  let {const_type=typ} = Global.lookup_constant sp in
	  if (head_const typ) = const then fn (ConstRef sp) env typ
      | "INDUCTIVE" -> 
          let mib = Global.lookup_mind sp in 
	  let arities =
	    array_map_to_list 
	      (fun mip ->
		 (Name mip.mind_typename, None, mip.mind_nf_arity))
	      mib.mind_packets in
	  let env_ar = push_rels arities env in
          (match kind_of_term const with 
	     | IsMutInd ((sp',tyi) as indsp,_) -> 
		 if sp=sp' then
		   print_constructors indsp fn env_ar
		     (mind_nth_type_packet mib tyi)
	     | _ -> ())
      | _ -> ()
  in 
  try 
    Library.iter_all_segments true crible_rec 
  with Not_found -> 
    errorlabstrm "search"
      [< pr_global ref; 'sPC; 'sTR "not declared" >]

(* Fine Search. By Yves Bertot. *)

exception No_section_path

let rec head c = 
  let c = strip_outer_cast c in
  match kind_of_term c with
  | IsProd (_,_,c) -> head c
  | _              -> c
      
let constr_to_section_path c = match kind_of_term c with
  | IsConst (sp,_) -> sp
  | _ -> raise No_section_path
      
let xor a b = (a or b) & (not (a & b))

let plain_display ref a c =
  let pc = prterm_env a c in
  let pr = pr_global ref in
  mSG [< hOV 2 [< pr; 'sTR":"; 'sPC; pc >]; 'fNL>]

let filter_by_module (module_list:dir_path list) (accept:bool) 
  (ref:global_reference) (env:env) _ =
  try
    let sp = sp_of_global env ref in
    let sl = dirpath sp in
    let rec filter_aux = function
      | m :: tl -> (not (dirpath_prefix_of m sl)) && (filter_aux tl)
      | [] -> true 
    in
    xor accept (filter_aux module_list)
  with No_section_path -> 
    false

let gref_eq = IndRef (make_path ["Coq";"Init";"Logic"] (id_of_string "eq") CCI, 0)
let gref_eqT = IndRef (make_path ["Coq";"Init";"Logic_Type"] (id_of_string "eqT") CCI, 0)

let mk_rewrite_pattern1 eq pattern =
  PApp (PRef eq, [| PMeta None; pattern; PMeta None |])

let mk_rewrite_pattern2 eq pattern =
  PApp (PRef eq, [| PMeta None; PMeta None; pattern |])

let pattern_filter pat _ a c =
  try 
    try
      Pattern.is_matching pat (head c) 
    with _ -> 
      Pattern.is_matching
	pat (head (Typing.type_of (Global.env()) Evd.empty c))
    with UserError _ -> 
      false

let filtered_search filter_function display_function ref =
  crible 
    (fun s a c -> if filter_function s a c then display_function s a c) 
    ref

let rec id_from_pattern = function
  | PRef gr -> gr
(* should be appear as a PRef (VarRef sp) !!
  | PVar id -> Nametab.locate (make_qualid [] (string_of_id id))
 *)
  | PApp (p,_) -> id_from_pattern p
  | _ -> error "the pattern is not simple enough"
	
let raw_pattern_search extra_filter display_function pat =
  let name = id_from_pattern pat in
  filtered_search 
    (fun s a c -> (pattern_filter pat s a c) & extra_filter s a c) 
    display_function name

let raw_search_rewrite extra_filter display_function pattern =
  filtered_search
    (fun s a c ->
       ((pattern_filter (mk_rewrite_pattern1 gref_eq pattern) s a c) ||
        (pattern_filter (mk_rewrite_pattern2 gref_eq pattern) s a c)) 
       && extra_filter s a c)
    display_function gref_eq;
  filtered_search
    (fun s a c ->
       ((pattern_filter (mk_rewrite_pattern1 gref_eqT pattern) s a c) ||
        (pattern_filter (mk_rewrite_pattern2 gref_eqT pattern) s a c)) 
       && extra_filter s a c)
    display_function gref_eqT

let text_pattern_search extra_filter =
  raw_pattern_search extra_filter plain_display
    
let text_search_rewrite extra_filter =
  raw_search_rewrite extra_filter plain_display

let filter_by_module_from_list = function
  | [], _ -> (fun _ _ _ -> true)
  | l, outside -> filter_by_module l (not outside)

let search_by_head ref inout = 
  filtered_search (filter_by_module_from_list inout) plain_display ref

let search_rewrite pat inout =
  text_search_rewrite (filter_by_module_from_list inout) pat

let search_pattern pat inout =
  text_pattern_search (filter_by_module_from_list inout) pat


