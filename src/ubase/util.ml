(* $I1: Unison file synchronizer: src/ubase/util.ml $ *)
(* $I2: Last modified by bcpierce on Sat, 27 Nov 2004 09:22:40 -0500 $ *)
(* $I3: Copyright 1999-2004 (see COPYING for details) $ *)

(*****************************************************************************)
(*                        CASE INSENSITIVE COMPARISON                        *)
(*****************************************************************************)
let nocase_cmp a b =
  let alen = String.length a in
  let blen = String.length b in
  let minlen = if alen<blen then alen else blen in
  let rec loop i =
    if i>=minlen then compare alen blen
    else
      let c =
        compare (Char.lowercase(String.get a i)) (Char.lowercase(String.get b i)) in
      if c<>0 then c else loop (i+1) in
  loop 0
let nocase_eq a b = (0 = (nocase_cmp a b))


(*****************************************************************************)
(*                        PRE-BUILT MAP AND SET MODULES                      *)
(*****************************************************************************)

module StringMap =
  Map.Make(struct
    type t = string
    let compare = compare
  end)

module StringSet =
  Set.Make(struct
    type t = string
    let compare = compare
  end)

let stringSetFromList l =
  Safelist.fold_right StringSet.add l StringSet.empty

(*****************************************************************************)
(*                    Debugging / error messages                             *)
(*****************************************************************************)

let infos = ref ""

let clear_infos () =
  if !infos <> "" then begin
    print_string "\r";
    print_string (String.make (String.length !infos) ' ');
    print_string "\r";
    flush stdout
  end
let show_infos () =
  if !infos <> "" then begin print_string !infos; flush stdout end
let set_infos s =
  if s <> !infos then begin clear_infos (); infos := s; show_infos () end

let msg f =
  clear_infos (); Uprintf.eprintf (fun () -> flush stderr; show_infos ()) f

let msg : ('a, out_channel, unit) format -> 'a = msg

(*****************************************************************************)
(*                  GLOBAL DEBUGGING SWITCH                                  *)
(*****************************************************************************)

let debugPrinter = ref None

let debug s th =
  match !debugPrinter with
    None -> assert false
  | Some p -> p s th

(* This should be set by the UI to a function that can be used to warn users *)
let warnPrinter = ref None

(* The rest of the program invokes this function to warn users.              *)
let warn message =
  match !warnPrinter with
    None -> ()
  | Some p -> p message

(*****************************************************************************)
(*                    EXCEPTION HANDLING                                     *)
(*****************************************************************************)

exception Fatal of string
exception Transient of string

let encodeException m kind e =
  let reraise s =
    match kind with
      `Fatal     -> raise (Fatal s)
    | `Transient -> raise (Transient s)
  in
  let kindStr =
    match kind with
      `Fatal     -> "Fatal"
    | `Transient -> "Transient"
  in
  match e with
    Unix.Unix_error(err,fnname,param) ->
      let s =   "Error in " ^ m ^ ":\n"
              ^ (Unix.error_message err)
              ^ " [" ^ fnname ^ "(" ^ param ^ ")]" in
      debug "exn"
        (fun() -> msg "Converting a Unix error to %s:\n%s\n" kindStr s);
      reraise s
  | Transient(s) ->
      debug "exn" (fun() ->
        if kind = `Fatal then
          msg "In %s: Converting a Transient error to %s:\n%s\n" m kindStr s
        else
          msg "In %s: Propagating Transient error\n" m);
      reraise s
  | Not_found ->
      let s = "Not_found raised in " ^ m
              ^ " (this indicates a bug!)" in
      debug "exn"
        (fun() -> msg "Converting a Not_found to %s:\n%s\n" kindStr s);
      reraise s
  | Sys_error(s) ->
      let s = "Error in " ^ m ^ ":\n" ^ s in
      debug "exn"
        (fun() -> msg "Converting a Sys_error to %s:\n%s\n" kindStr s);
      reraise s
  | Sys_blocked_io ->
      let s = "Blocked IO error in " ^ m in
      debug "exn"
        (fun() -> msg "Converting a Sys_blocked_io to %s:\n%s\n" kindStr s);
      reraise s
  | _ ->
      raise e

let convertUnixErrorsToExn m f n e =
  try f()
  with
    Unix.Unix_error(err,fnname,param) ->
      let s =   "Error in " ^ m ^ ":\n"
              ^ (Unix.error_message err)
              ^ " [" ^ fnname ^ "(" ^ param ^ ")]" in
      debug "exn"
        (fun() -> msg "Converting a Unix error to %s:\n%s\n" n s);
      raise (e s)
  | Transient(s) ->
      debug "exn" (fun() ->
        if n="Fatal" then
          msg "In %s: Converting a Transient error to %s:\n%s\n" m n s
        else
          msg "In %s: Propagating Transient error\n" m);
      raise (e s)
  | Not_found ->
      let s = "Not_found raised in " ^ m
              ^ " (this indicates a bug!)" in
        debug "exn" (fun() -> msg "Converting a Not_found to %s:\n%s\n" n s);
        raise (e s)
  | End_of_file ->
      let s = "End_of_file exception raised in " ^ m
              ^ " (this indicates a bug!)" in
        debug "exn" (fun() -> msg "Converting an End_of_file to %s:\n%s\n" n s);
        raise (e s)
  | Sys_error(s) ->
      let s = "Error in " ^ m ^ ":\n" ^ s in
      debug "exn" (fun() -> msg "Converting a Sys_error to %s:\n%s\n" n s);
      raise (e s)
  | Sys_blocked_io ->
      let s = "Blocked IO error in " ^ m in
      debug "exn" (fun() -> msg "Converting a Sys_blocked_io to %s:\n%s\n"
                     n s);
      raise (e s)

let convertUnixErrorsToFatal m f =
  convertUnixErrorsToExn m f "Fatal" (fun str -> Fatal(str))

let convertUnixErrorsToTransient m f =
  convertUnixErrorsToExn m f "Transient" (fun str -> Transient(str))

let unwindProtect f cleanup =
  try
    f ()
  with
    Transient _ as e ->
      debug "exn" (fun () -> msg "Exception caught by unwindProtect\n");
      convertUnixErrorsToFatal "unwindProtect" (fun()-> cleanup e);
      raise e

let finalize f cleanup =
  try
    let res = f () in
    cleanup ();
    res
  with
    Transient _ as e ->
      debug "exn" (fun () -> msg "Exception caught by finalize\n");
      convertUnixErrorsToFatal "finalize" cleanup;
      raise e

type confirmation =
   Succeeded
 | Failed of string

let ignoreTransientErrors thunk =
  try
    thunk()
  with
    Transient(s) -> ()

(* Safe version of Unix getenv -- raises a comprehensible error message if
   called with an env variable that doesn't exist                            *)
let safeGetenv var =
  convertUnixErrorsToFatal
    "querying environment"
    (fun () ->
       try Unix.getenv var
       with Not_found ->
         raise (Fatal ("Environment variable " ^ var ^ " not found")))

(*****************************************************************************)
(*                         OS TYPE                                           *)
(*****************************************************************************)

let osType =
  match Sys.os_type with
    "Win32" | "Cygwin" -> `Win32
  | "Unix"             -> `Unix
  | other              -> raise (Fatal ("Unkown OS: " ^ other))

let isCygwin = (Sys.os_type = "Cygwin")

(*****************************************************************************)
(*                      MISCELLANEOUS                                        *)
(*****************************************************************************)

let monthname n =
  Safelist.nth
    ["Jan";"Feb";"Mar";"Apr";"May";"Jun";"Jul";"Aug";"Sep";"Oct";"Nov";"Dec"]
    n

let localtime f =
  convertUnixErrorsToTransient "localtime" (fun()-> Unix.localtime f)

let time () =
  convertUnixErrorsToTransient "time" Unix.time

let time2string timef =
  let time = localtime timef in
  Printf.sprintf
    "%2d:%.2d on %2d %3s, %4d"
    time.Unix.tm_hour
    time.Unix.tm_min
    time.Unix.tm_mday
    (monthname time.Unix.tm_mon)
    (time.Unix.tm_year + 1900)

let percentageOfTotal current total =
  (int_of_float ((float current) *. 100.0 /. (float total)))

let percent2string p = Printf.sprintf "%3d%%" (truncate (max 0. (min 100. p)))

let extractValueFromOption = function
    None -> raise (Fatal "extractValueFromOption failed")
  | Some(v) -> v

let option2string (prt: 'a -> string) = function
    Some x -> prt x
  | None   -> "N.A."

(*****************************************************************************)
(*                    String utility functions                               *)
(*****************************************************************************)

let truncateString string length =
  let actualLength = String.length string in
  if actualLength <= length then string^(String.make (length - actualLength) ' ')
  else if actualLength < 3 then string
  else (String.sub string 0 (length - 3))^ "..."

let findsubstring s1 s2 =
  let l1 = String.length s1 in
  let l2 = String.length s2 in
  let rec loop i =
    if i+l1 > l2 then None
    else if s1 = String.sub s2 i l1 then Some(i)
    else loop (i+1)
  in loop 0

let rec replacesubstring s fromstring tostring =
  match findsubstring fromstring s with
    None -> s
  | Some(i) ->
      let before = String.sub s 0 i in
      let afterpos = i + (String.length fromstring) in
      let after = String.sub s afterpos ((String.length s) - afterpos) in
      before ^ tostring ^ (replacesubstring after fromstring tostring)

let startswith s1 s2 =
  let l1 = String.length s1 in
  let l2 = String.length s2 in
  if l1 < l2 then false else
    let rec loop i =
      if i>=l2 then true
      else if s1.[i] <> s2.[i] then false
      else loop (i+1)
    in loop 0

let endswith s1 s2 =
  let l1 = String.length s1 in
  let l2 = String.length s2 in
  let offset = l1 - l2 in
  if l1 < l2 then false else
    let rec loop i =
      if i>=l2 then true
      else if s1.[i+offset] <> s2.[i] then false
      else loop (i+1)
    in loop 0

let concatmap sep f l =
  String.concat sep (Safelist.map f l)

let rec trimWhitespace s =
  let l = String.length s in
  if l=0 then s
  else if s.[0]=' ' || s.[0]='\t' || s.[0]='\n' || s.[0]='\r' then
    trimWhitespace (String.sub s 1 (l-1))
  else if s.[l-1]=' ' || s.[l-1]='\t' || s.[l-1]='\n' || s.[l-1]='\r' then
    trimWhitespace (String.sub s 0 (l-1))
  else
    s

let splitIntoWords (s:string) (c:char) =
  let rec inword acc start pos =
    if pos >= String.length(s) || s.[pos] = c then
      betweenwords ((String.sub s start (pos-start)) :: acc) pos
    else inword acc start (pos+1)
  and betweenwords acc pos =
    if pos >= (String.length s) then (Safelist.rev acc)
    else if s.[pos]=c then betweenwords acc (pos+1)
    else inword acc pos pos
  in betweenwords [] 0

let rec splitIntoWordsByString s sep =
  match findsubstring sep s with
    None -> [s]
  | Some(i) ->
      let before = String.sub s 0 i in
      let afterpos = i + (String.length sep) in
      let after = String.sub s afterpos ((String.length s) - afterpos) in
      before :: (splitIntoWordsByString after sep)

let padto n s = s ^ (String.make (max 0 (n - String.length s)) ' ')

(*****************************************************************************)
(*              Building pathnames in the user's home dir                    *)
(*****************************************************************************)

let fileInHomeDir n =
  if (osType = `Unix) || isCygwin then
    Filename.concat (safeGetenv "HOME") n
  else if osType = `Win32 then
    let dirString =
      try Unix.getenv "UNISON" (* Use UNISON dir if it is set *)
      with Not_found ->
      try Unix.getenv "HOME" (* Windows 9x with Cygwin HOME set *)
      with Not_found ->
      try Unix.getenv "USERPROFILE" (* Windows NT/2K standard *)
      with Not_found ->
      "c:/" (* Default *) in
    Filename.concat dirString n
  else
    assert false (* osType can't be anything else *)

(*****************************************************************************)
(*           "Upcall" for building pathnames in the .unison dir              *)
(*****************************************************************************)

let fileInUnisonDirFn = ref None

let supplyFileInUnisonDirFn f = fileInUnisonDirFn := Some(f)

let fileInUnisonDir n =
   match !fileInUnisonDirFn with
     None -> assert false
   | Some(f) -> f n
