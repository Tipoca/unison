(* $I1: Unison file synchronizer: src/transport.ml $ *)
(* $I2: Last modified by vouillon on Fri, 05 Nov 2004 10:12:27 -0500 $ *)
(* $I3: Copyright 1999-2004 (see COPYING for details) $ *)

open Common
open Lwt

let debug = Trace.debug "transport"

(*****************************************************************************)
(*                              MAIN FUNCTIONS                               *)
(*****************************************************************************)

let fileSize uiFrom uiTo =
  match uiFrom, uiTo with
    _, Updates (File (props, ContentsUpdated (_, _, ress)), _) ->
      (Props.length props, Osx.ressLength ress)
  | Updates (_, Previous (`FILE, props, _, ress)),
    (NoUpdates | Updates (File (_, ContentsSame), _)) ->
      (Props.length props, Osx.ressLength ress)
  | _ ->
      assert false

let maxthreads =
  Prefs.createInt "maxthreads" 20
    "maximum number of simultaneous file transfers"
    ("This preference controls how much concurrency is allowed during"
     ^ " the transport phase.  Normally, it should be set reasonably high "
     ^ "(default is 20) to maximize performance, but when Unison is used "
     ^ "over a low-bandwidth link it may be helpful to set it lower (e.g. "
     ^ "to 1) so that Unison doesn't soak up all the available bandwidth."
    )

let actionReg = Lwt_util.make_region (Prefs.read maxthreads)

(* Logging for a thread: write a message before and a message after the
   execution of the thread. *)
let logLwt (msgBegin: string)
    (t: unit -> 'a Lwt.t)
    (fMsgEnd: 'a -> string)
    : 'a Lwt.t =
  Trace.log msgBegin;
  Lwt.bind (t ()) (fun v ->
    Trace.log (fMsgEnd v);
    Lwt.return v)

(* [logLwtNumbered desc t] provides convenient logging for a thread given a
   description [desc] of the thread [t ()], generate pair of messages of the
   following form in the log:
 *
    [BGN] <desc>
     ...
    [END] <desc>
 **)
let rLogCounter = ref 0
let logLwtNumbered (lwtDescription: string) (lwtShortDescription: string)
    (t: unit -> 'a Lwt.t): 'a Lwt.t =
  let _ = (rLogCounter := (!rLogCounter) + 1; !rLogCounter) in
  logLwt (Printf.sprintf "[BGN] %s\n" lwtDescription) t
    (fun _ ->
      Printf.sprintf "[END] %s\n" lwtShortDescription)

let doAction (fromRoot,toRoot) path fromContents toContents id =
  Lwt_util.resize_region actionReg (Prefs.read maxthreads);
  Lwt_util.run_in_region actionReg 1 (fun () ->
    if not !Trace.sendLogMsgsToStderr then
      Trace.statusDetail (Path.toString path);
    Remote.Thread.unwindProtect (fun () ->
      match fromContents, toContents with
        (`ABSENT, _, _, _), (_, _, _, uiTo) ->
             logLwtNumbered
               ("Deleting " ^ Path.toString path ^
                "\n  from "^ root2string toRoot)
               ("Deleting " ^ Path.toString path)
               (fun () -> Files.delete fromRoot path toRoot path uiTo)
        (* No need to transfer the whole directory/file if there were only
           property modifications on one side.  (And actually, it would be
           incorrect to transfer a directory in this case.) *)
        | (_, (`Unchanged | `PropsChanged), fromProps, uiFrom),
          (_, (`Unchanged | `PropsChanged), toProps, uiTo) ->
            logLwtNumbered
              ("Copying properties for " ^ Path.toString path
               ^ "\n  from " ^ root2string fromRoot ^ "\n  to " ^
               root2string toRoot)
              ("Copying properties for " ^ Path.toString path)
              (fun () ->
                Files.setProp
                  fromRoot path toRoot path fromProps toProps uiFrom uiTo)
        | (`FILE, _, _, uiFrom), (`FILE, _, _, uiTo) ->
            logLwtNumbered
              ("Updating file " ^ Path.toString path ^ "\n  from " ^
               root2string fromRoot ^ "\n  to " ^
               root2string toRoot)
              ("Updating file " ^ Path.toString path)
              (fun () ->
                Files.copy (`Update (fileSize uiFrom uiTo))
                  fromRoot path uiFrom toRoot path uiTo id)
        | (_, _, _, uiFrom), (_, _, _, uiTo) ->
            logLwtNumbered
              ("Copying " ^ Path.toString path ^ "\n  from " ^
               root2string fromRoot ^ "\n  to " ^
               root2string toRoot)
              ("Copying " ^ Path.toString path)
              (fun () -> Files.copy `Copy
                  fromRoot path uiFrom toRoot path uiTo id))
      (fun e -> Trace.log
          (Printf.sprintf
             "Failed: %s\n" (Util.printException e));
        return ()))

let propagate root1 root2 reconItem id showMergeFn =
  let path = reconItem.path in
  match reconItem.replicas with
    Problem p ->
      Trace.log (Printf.sprintf "[ERROR] Skipping %s\n  %s\n"
                   (Path.toString path) p);
      return ()
  | Different(rc1,rc2,dir,_) ->
      match !dir with
        Conflict ->
          Trace.log (Printf.sprintf "[CONFLICT] Skipping %s\n"
                       (Path.toString path));
          return ()
      | Replica1ToReplica2 ->
          doAction (root1, root2) path rc1 rc2 id
      | Replica2ToReplica1 ->
          doAction (root2, root1) path rc2 rc1 id
      | Merge -> 
          begin match (rc1,rc2) with
            (`FILE, _, _, ui1), (`FILE, _, _, ui2) ->
              Files.merge root1 root2 path id ui1 ui2 showMergeFn;
              return ()
          | _ -> assert false
          end 

let transportItem reconItem id showMergeFn =
  let (root1,root2) = Globals.roots() in
  propagate root1 root2 reconItem id showMergeFn

(* ---------------------------------------------------------------------- *)

let months = ["Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"; "Jul"; "Aug"; "Sep";
              "Oct"; "Nov"; "Dec"]

let logStart () =
  Abort.reset ();
  let tm = Util.localtime (Util.time()) in
  let m =
    Printf.sprintf
      "\n\n%s started propagating changes at %02d:%02d:%02d on %02d %s %04d\n"
      (String.uppercase Uutil.myNameAndVersion)
      tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec
      tm.Unix.tm_mday (Safelist.nth months tm.Unix.tm_mon)
      (tm.Unix.tm_year+1900) in
  Trace.log m

let logFinish () =
  let tm = Util.localtime (Util.time()) in
  let m =
    Printf.sprintf
      "%s finished propagating changes at %02d:%02d:%02d on %02d %s %04d\n\n\n"
      (String.uppercase Uutil.myNameAndVersion)
      tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec
      tm.Unix.tm_mday (Safelist.nth months tm.Unix.tm_mon)
      (tm.Unix.tm_year+1900) in
  Trace.log m
