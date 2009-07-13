(* Unison file synchronizer: src/uigtk2.ml *)
(* Copyright 1999-2009, Benjamin C. Pierce 

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*)


open Common
open Lwt

module Private = struct

let debug = Trace.debug "ui"

let myNameCapitalized = String.capitalize Uutil.myName

(**********************************************************************
                           LOW-LEVEL STUFF
 **********************************************************************)

(**********************************************************************
 Some message strings (build them here because they look ugly in the
 middle of other code.
 **********************************************************************)

let tryAgainMessage =
  Printf.sprintf
"You can use %s to synchronize a local directory with another local directory,
or with a remote directory.

Please enter the first (local) directory that you want to synchronize."
myNameCapitalized

(* ---- *)

let helpmessage = Printf.sprintf
"%s can synchronize a local directory with another local directory, or with
a directory on a remote machine.

To synchronize with a local directory, just enter the file name.

To synchronize with a remote directory, you must first choose a protocol
that %s will use to connect to the remote machine.  Each protocol has
different requirements:

1) To synchronize using SSH, there must be an SSH client installed on
this machine and an SSH server installed on the remote machine.  You
must enter the host to connect to, a user name (if different from
your user name on this machine), and the directory on the remote machine
(relative to your home directory on that machine).

2) To synchronize using RSH, there must be an RSH client installed on
this machine and an RSH server installed on the remote machine.  You
must enter the host to connect to, a user name (if different from
your user name on this machine), and the directory on the remote machine
(relative to your home directory on that machine).

3) To synchronize using %s's socket protocol, there must be a %s
server running on the remote machine, listening to the port that you
specify here.  (Use \"%s -socket xxx\" on the remote machine to
start the %s server.)  You must enter the host, port, and the directory
on the remote machine (relative to the working directory of the
%s server running on that machine)."
myNameCapitalized myNameCapitalized myNameCapitalized myNameCapitalized myNameCapitalized myNameCapitalized myNameCapitalized

(**********************************************************************
 Font preferences
 **********************************************************************)

let fontMonospaceMediumPango = lazy (Pango.Font.from_string "monospace")

(**********************************************************************
 Unison icon
 **********************************************************************)

(* This does not work with the current version of Lablgtk, due to a bug
let icon =
  GdkPixbuf.from_data ~width:48 ~height:48 ~has_alpha:true
    (Gpointer.region_of_string Pixmaps.icon_data)
*)
let icon =
  let p = GdkPixbuf.create ~width:48 ~height:48 ~has_alpha:true () in
  Gpointer.blit
    (Gpointer.region_of_string Pixmaps.icon_data) (GdkPixbuf.get_pixels p);
  p

(*********************************************************************
  UI state variables
 *********************************************************************)

type stateItem = { mutable ri : reconItem;
                   mutable bytesTransferred : Uutil.Filesize.t;
                   mutable bytesToTransfer : Uutil.Filesize.t;
                   mutable whatHappened : (Util.confirmation * string option) option}
let theState = ref [||]

let current = ref None

(* ---- *)

let currentWindow = ref None

let grabFocus t =
  match !currentWindow with
    Some w -> t#set_transient_for (w#as_window);
              w#misc#set_sensitive false
  | None   -> ()

let releaseFocus () =
  begin match !currentWindow with
    Some w -> w#misc#set_sensitive true
  | None   -> ()
  end

(*********************************************************************
  Lock management
 *********************************************************************)

let busy = ref false

let getLock f =
  if !busy then
    Trace.status "Synchronizer is busy, please wait.."
  else begin
    busy := true; f (); busy := false
  end

(**********************************************************************
  Miscellaneous
 **********************************************************************)

let sync_action = ref None

let last = ref (0.)

let gtk_sync forced =
  let t = Unix.gettimeofday () in
  if !last = 0. || forced || t -. !last > 0.05 then begin
    last := t;
    begin match !sync_action with
      Some f -> f ()
    | None   -> ()
    end;
    while Glib.Main.iteration false do () done
  end

(**********************************************************************
                      CHARACTER SET TRANSCODING
***********************************************************************)

(* Transcodage from Microsoft Windows Codepage 1252 to Unicode *)

(* Unison currently uses the "ASCII" Windows filesystem API.  With
   this API, filenames are encoded using a proprietary character
   encoding.  This encoding depends on the Windows setup, but in
   Western Europe, the Windows Codepage 1252 is usually used.
   GTK, on the other hand, uses the UTF-8 encoding.  This code perform
   the translation from Codepage 1252 to UTF-8.  A call to [transcode]
   should be wrapped around every string below that might contain
   non-ASCII characters. *)

let code =
  [| 0x0020; 0x0001; 0x0002; 0x0003; 0x0004; 0x0005; 0x0006; 0x0007;
     0x0008; 0x0009; 0x000A; 0x000B; 0x000C; 0x000D; 0x000E; 0x000F;
     0x0010; 0x0011; 0x0012; 0x0013; 0x0014; 0x0015; 0x0016; 0x0017;
     0x0018; 0x0019; 0x001A; 0x001B; 0x001C; 0x001D; 0x001E; 0x001F;
     0x0020; 0x0021; 0x0022; 0x0023; 0x0024; 0x0025; 0x0026; 0x0027;
     0x0028; 0x0029; 0x002A; 0x002B; 0x002C; 0x002D; 0x002E; 0x002F;
     0x0030; 0x0031; 0x0032; 0x0033; 0x0034; 0x0035; 0x0036; 0x0037;
     0x0038; 0x0039; 0x003A; 0x003B; 0x003C; 0x003D; 0x003E; 0x003F;
     0x0040; 0x0041; 0x0042; 0x0043; 0x0044; 0x0045; 0x0046; 0x0047;
     0x0048; 0x0049; 0x004A; 0x004B; 0x004C; 0x004D; 0x004E; 0x004F;
     0x0050; 0x0051; 0x0052; 0x0053; 0x0054; 0x0055; 0x0056; 0x0057;
     0x0058; 0x0059; 0x005A; 0x005B; 0x005C; 0x005D; 0x005E; 0x005F;
     0x0060; 0x0061; 0x0062; 0x0063; 0x0064; 0x0065; 0x0066; 0x0067;
     0x0068; 0x0069; 0x006A; 0x006B; 0x006C; 0x006D; 0x006E; 0x006F;
     0x0070; 0x0071; 0x0072; 0x0073; 0x0074; 0x0075; 0x0076; 0x0077;
     0x0078; 0x0079; 0x007A; 0x007B; 0x007C; 0x007D; 0x007E; 0x007F;
     0x20AC; 0x1234; 0x201A; 0x0192; 0x201E; 0x2026; 0x2020; 0x2021;
     0x02C6; 0x2030; 0x0160; 0x2039; 0x0152; 0x1234; 0x017D; 0x1234;
     0x1234; 0x2018; 0x2019; 0x201C; 0x201D; 0x2022; 0x2013; 0x2014;
     0x02DC; 0x2122; 0x0161; 0x203A; 0x0153; 0x1234; 0x017E; 0x0178;
     0x00A0; 0x00A1; 0x00A2; 0x00A3; 0x00A4; 0x00A5; 0x00A6; 0x00A7;
     0x00A8; 0x00A9; 0x00AA; 0x00AB; 0x00AC; 0x00AD; 0x00AE; 0x00AF;
     0x00B0; 0x00B1; 0x00B2; 0x00B3; 0x00B4; 0x00B5; 0x00B6; 0x00B7;
     0x00B8; 0x00B9; 0x00BA; 0x00BB; 0x00BC; 0x00BD; 0x00BE; 0x00BF;
     0x00C0; 0x00C1; 0x00C2; 0x00C3; 0x00C4; 0x00C5; 0x00C6; 0x00C7;
     0x00C8; 0x00C9; 0x00CA; 0x00CB; 0x00CC; 0x00CD; 0x00CE; 0x00CF;
     0x00D0; 0x00D1; 0x00D2; 0x00D3; 0x00D4; 0x00D5; 0x00D6; 0x00D7;
     0x00D8; 0x00D9; 0x00DA; 0x00DB; 0x00DC; 0x00DD; 0x00DE; 0x00DF;
     0x00E0; 0x00E1; 0x00E2; 0x00E3; 0x00E4; 0x00E5; 0x00E6; 0x00E7;
     0x00E8; 0x00E9; 0x00EA; 0x00EB; 0x00EC; 0x00ED; 0x00EE; 0x00EF;
     0x00F0; 0x00F1; 0x00F2; 0x00F3; 0x00F4; 0x00F5; 0x00F6; 0x00F7;
     0x00F8; 0x00F9; 0x00FA; 0x00FB; 0x00FC; 0x00FD; 0x00FE; 0x00FF |]

let rec transcodeRec buf s i l =
  if i < l then begin
    let c = code.(Char.code s.[i]) in
    if c < 0x80 then
      Buffer.add_char buf (Char.chr c)
    else if c < 0x800 then begin
      Buffer.add_char buf (Char.chr (c lsr 6 + 0xC0));
      Buffer.add_char buf (Char.chr (c land 0x3f + 0x80))
    end else if c < 0x10000 then begin
      Buffer.add_char buf (Char.chr (c lsr 12 + 0xE0));
      Buffer.add_char buf (Char.chr ((c lsr 6) land 0x3f + 0x80));
      Buffer.add_char buf (Char.chr (c land 0x3f + 0x80))
    end;
    transcodeRec buf s (i + 1) l
  end

let transcodeDoc s =
  let buf = Buffer.create 1024 in
  transcodeRec buf s 0 (String.length s);
  Buffer.contents buf

(****)

let escapeMarkup s = Glib.Markup.escape_text s

let transcodeFilename s =
  if Prefs.read Case.unicodeEncoding then
    Unicode.protect s
  else if Util.osType = `Win32 then transcodeDoc s else
  try
    Glib.Convert.filename_to_utf8 s
  with Glib.Convert.Error _ ->
    Unicode.protect s

let transcode s =
  if Prefs.read Case.unicodeEncoding then
    Unicode.protect s
  else
  try
    Glib.Convert.locale_to_utf8 s
  with Glib.Convert.Error _ ->
    Unicode.protect s

(**********************************************************************
                       USEFUL LOW-LEVEL WIDGETS
 **********************************************************************)

class scrolled_text
    ?(font=fontMonospaceMediumPango) ?editable ?word_wrap
    ~width ~height ?packing ?show
    () =
  let sw =
    GBin.scrolled_window ?packing ~show:false
      ~hpolicy:`NEVER ~vpolicy:`AUTOMATIC ()
  in
  let text = GText.view ?editable ?wrap_mode:(Some `WORD) ~packing:sw#add () in
  object
    inherit GObj.widget_full sw#as_widget
    method text = text
    method insert ?(font=fontMonospaceMediumPango) s =
      text#buffer#set_text s;
    method show () = sw#misc#show ()
    initializer
      text#misc#modify_font (Lazy.force font);
      text#misc#set_size_chars ~height ~width ();
      if show <> Some false then sw#misc#show ()
  end

(* ------ *)

(* Display a message in a window and wait for the user
   to hit the button. *)
let okBox ~title ~typ ~message =
  let t =
    GWindow.message_dialog
      ~title ~message_type:typ ~message ~modal:true
      ~buttons:GWindow.Buttons.ok () in
  grabFocus t;
  ignore (t#run ()); t#destroy ();
  releaseFocus ()

(* ------ *)

let primaryText msg =
  Printf.sprintf "<span weight=\"bold\" size=\"larger\">%s</span>"
    (escapeMarkup msg)

(* twoBox: Display a message in a window and wait for the user
   to hit one of two buttons.  Return true if the first button is
   chosen, false if the second button is chosen. *)
let twoBox ~title ~message ~astock ~bstock =
  let t =
    GWindow.dialog ~border_width:6 ~modal:true ~no_separator:true
      ~allow_grow:false () in
  t#vbox#set_spacing 12;
  let h1 = GPack.hbox ~border_width:6 ~spacing:12 ~packing:t#vbox#pack () in
  ignore (GMisc.image ~stock:`DIALOG_WARNING ~icon_size:`DIALOG
            ~yalign:0. ~packing:h1#pack ());
  let v1 = GPack.vbox ~spacing:12 ~packing:h1#pack () in
  ignore (GMisc.label
            ~markup:(primaryText title ^ "\n\n" ^ escapeMarkup message)
            ~selectable:true ~yalign:0. ~packing:v1#add ());
  t#add_button_stock bstock `NO;
  t#add_button_stock astock `YES;
  t#set_default_response `NO;
  grabFocus t; t#show();
  let res = t#run () in
  t#destroy (); releaseFocus ();
  res = `YES

(* ------ *)

(* Avoid recursive invocations of the function below (a window receives
   delete events even when it is not sensitive) *)
let inExit = ref false

let doExit () = Lwt_unix.run (Update.unlockArchives ()); exit 0

let safeExit () =
  if not !inExit then begin
    inExit := true;
    if not !busy then exit 0 else
    if twoBox ~title:"Premature exit"
        ~message:"Unison is working, exit anyway ?"
        ~astock:`YES ~bstock:`NO
    then exit 0;
    inExit := false
  end

(* ------ *)

(* warnBox: Display a warning message in a window and wait (unless
   we're in batch mode) for the user to hit "OK" or "Exit". *)
let warnBox title message =
  let message = transcode message in
  if Prefs.read Globals.batch then begin
    (* In batch mode, just pop up a window and go ahead *)
    let t =
      GWindow.dialog ~border_width:6 ~modal:true ~no_separator:true
        ~allow_grow:false () in
    t#vbox#set_spacing 12;
    let h1 = GPack.hbox ~border_width:6 ~spacing:12 ~packing:t#vbox#pack () in
    ignore (GMisc.image ~stock:`DIALOG_INFO ~icon_size:`DIALOG
              ~yalign:0. ~packing:h1#pack ());
    let v1 = GPack.vbox ~spacing:12 ~packing:h1#pack () in
    ignore (GMisc.label ~markup:(primaryText title ^ "\n\n" ^
                                 escapeMarkup message)
              ~selectable:true ~yalign:0. ~packing:v1#add ());
    t#add_button_stock `CLOSE `CLOSE;
    t#set_default_response `CLOSE;
    ignore (t#connect#response ~callback:(fun _ -> t#destroy ()));
    t#show ()
  end else begin
    inExit := true;
    let ok = twoBox ~title ~message ~astock:`OK ~bstock:`QUIT in
    if not(ok) then doExit ();
    inExit := false
  end

(**********************************************************************
                         HIGHER-LEVEL WIDGETS
***********************************************************************)

class stats width height =
  let pixmap = GDraw.pixmap ~width ~height () in
  let area =
    pixmap#set_foreground `WHITE;
    pixmap#rectangle ~filled:true ~x:0 ~y:0 ~width ~height ();
    GMisc.pixmap pixmap ~width ~height ~xpad:4 ~ypad:8 ()
  in
  object (self)
    inherit GObj.widget_full area#as_widget
    val mutable maxim = ref 0.
    val mutable scale = ref 1.
    val mutable min_scale = 1.
    val values = Array.make width 0.
    val mutable active = false

    method activate a = active <- a

    method scale h = truncate ((float height) *. h /. !scale)

    method private rect i v' v =
      let h = self#scale v in
      let h' = self#scale v' in
      let h1 = min h' h in
      let h2 = max h' h in
      pixmap#set_foreground `BLACK;
      pixmap#rectangle
        ~filled:true ~x:i ~y:(height - h1) ~width:1 ~height:h1 ();
      for h = h1 + 1 to h2 do
        let v = truncate (65535. *. (float (h - h1) /. float (h2 - h1))) in
        let v = (v / 4096) * 4096 in (* Only use 16 gray levels *)
        pixmap#set_foreground (`RGB (v, v, v));
        pixmap#rectangle
          ~filled:true ~x:i ~y:(height - h) ~width:1 ~height:1 ();
      done

    method push v =
      let need_max = values.(0) = !maxim in
      for i = 0 to width - 2 do
        values.(i) <- values.(i + 1)
      done;
      values.(width - 1) <- v;
      if need_max then begin
        maxim := 0.;
        for i = 0 to width - 1 do maxim := max !maxim values.(i) done
      end else
        maxim := max !maxim v;
      if active then begin
        let need_resize =
          !maxim > !scale || (!maxim > min_scale && !maxim < !scale /. 1.5) in
        if need_resize then begin
          scale := min_scale;
          while !maxim > !scale do
            scale := !scale *. 1.5
          done;
          pixmap#set_foreground `WHITE;
          pixmap#rectangle ~filled:true ~x:0 ~y:0 ~width ~height ();
          pixmap#set_foreground `BLACK;
          for i = 0 to width - 1 do
            self#rect i values.(max 0 (i - 1)) values.(i)
          done
        end else begin
          pixmap#put_pixmap ~x:0 ~y:0 ~xsrc:1 (pixmap#pixmap);
          pixmap#set_foreground `WHITE;
          pixmap#rectangle
            ~filled:true ~x:(width - 1) ~y:0 ~width:1 ~height ();
          self#rect (width - 1) values.(width - 2) values.(width - 1)
        end;
        area#misc#draw None
      end
  end

let clientWritten = ref 0.
let serverWritten = ref 0.

let statistics () =
  let title = "Statistics" in
  let t = GWindow.dialog ~title () in
  let t_dismiss = GButton.button ~stock:`CLOSE ~packing:t#action_area#add () in
  t_dismiss#grab_default ();
  let dismiss () = t#misc#hide () in
  ignore (t_dismiss#connect#clicked ~callback:dismiss);
  ignore (t#event#connect#delete ~callback:(fun _ -> dismiss (); true));

  let emission = new stats 320 50 in
  t#vbox#pack ~expand:false ~padding:4 (emission :> GObj.widget);
  let reception = new stats 320 50 in
  t#vbox#pack ~expand:false ~padding:4 (reception :> GObj.widget);

  let lst =
    GList.clist
      ~packing:(t#vbox#add)
      ~titles_active:false
      ~titles:[""; "Client"; "Server"; "Total"] ()
  in
  lst#set_column ~auto_resize:true 0;
  lst#set_column ~auto_resize:true ~justification:`RIGHT 1;
  lst#set_column ~auto_resize:true ~justification:`RIGHT 2;
  lst#set_column ~auto_resize:true ~justification:`RIGHT 3;
  ignore (lst#append ["Reception rate"]);
  ignore (lst#append ["Data received"]);
  ignore (lst#append ["File data written"]);
  for r = 0 to 2 do
    lst#set_row ~selectable:false r
  done;

  ignore (t#event#connect#map (fun _ ->
    emission#activate true;
    reception#activate true;
    false));
  ignore (t#event#connect#unmap (fun _ ->
    emission#activate false;
    reception#activate false;
    false));

  let delay = 0.5 in
  let a = 0.5 in
  let b = 0.8 in

  let emittedBytes = ref 0. in
  let emitRate = ref 0. in
  let emitRate2 = ref 0. in
  let receivedBytes = ref 0. in
  let receiveRate = ref 0. in
  let receiveRate2 = ref 0. in
  let timeout _ =
    emitRate :=
      a *. !emitRate +.
      (1. -. a) *. (!Remote.emittedBytes -. !emittedBytes) /. delay;
    emitRate2 :=
      b *. !emitRate2 +.
      (1. -. b) *. (!Remote.emittedBytes -. !emittedBytes) /. delay;
    emission#push !emitRate;
    receiveRate :=
      a *. !receiveRate +.
      (1. -. a) *. (!Remote.receivedBytes -. !receivedBytes) /. delay;
    receiveRate2 :=
      b *. !receiveRate2 +.
      (1. -. b) *. (!Remote.receivedBytes -. !receivedBytes) /. delay;
    reception#push !receiveRate;
    emittedBytes := !Remote.emittedBytes;
    receivedBytes := !Remote.receivedBytes;
    let kib2str v = Format.sprintf "%.0f B" v in
    let rate2str v =
      if v > 9.9e3 then begin
        if v > 9.9e6 then
          Format.sprintf "%4.0f MiB/s" (v /. 1e6)
        else if v > 999e3 then
          Format.sprintf "%4.1f MiB/s" (v /. 1e6)
        else
          Format.sprintf "%4.0f KiB/s" (v /. 1e3)
      end else begin
        if v > 990. then
          Format.sprintf "%4.1f KiB/s" (v /. 1e3)
        else if v > 99. then
          Format.sprintf "%4.2f KiB/s" (v /. 1e3)
        else
          "          "
      end
    in
    lst#set_cell ~text:(rate2str !receiveRate2) 0 1;
    lst#set_cell ~text:(rate2str !emitRate2) 0 2;
    lst#set_cell ~text:
      (rate2str (!receiveRate2 +. !emitRate2)) 0 3;
    lst#set_cell ~text:(kib2str !receivedBytes) 1 1;
    lst#set_cell ~text:(kib2str !emittedBytes) 1 2;
    lst#set_cell ~text:
      (kib2str (!receivedBytes +. !emittedBytes)) 1 3;
    lst#set_cell ~text:(kib2str !clientWritten) 2 1;
    lst#set_cell ~text:(kib2str !serverWritten) 2 2;
    lst#set_cell ~text:
      (kib2str (!clientWritten +. !serverWritten)) 2 3;
    true
  in
  ignore (GMain.Timeout.add ~ms:(truncate (delay *. 1000.)) ~callback:timeout);

  t

(****)

(* Standard file dialog *)
let file_dialog ~title ~callback ?filename () =
  let sel = GWindow.file_selection ~title ~modal:true ?filename () in
  grabFocus sel;
  ignore (sel#cancel_button#connect#clicked ~callback:sel#destroy);
  ignore (sel#ok_button#connect#clicked ~callback:
            (fun () ->
               let name = sel#filename in
               sel#destroy ();
               callback name));
  sel#show ();
  ignore (sel#connect#destroy ~callback:GMain.Main.quit);
  GMain.Main.main ();
  releaseFocus ()

(* ------ *)

let fatalError message =
  Trace.log (message ^ "\n");
  let title = "Fatal error" in
  let t =
    GWindow.dialog ~border_width:6 ~modal:true ~no_separator:true
      ~allow_grow:false () in
  t#vbox#set_spacing 12;
  let h1 = GPack.hbox ~border_width:6 ~spacing:12 ~packing:t#vbox#pack () in
  ignore (GMisc.image ~stock:`DIALOG_ERROR ~icon_size:`DIALOG
            ~yalign:0. ~packing:h1#pack ());
  let v1 = GPack.vbox ~spacing:12 ~packing:h1#pack () in
  ignore (GMisc.label
            ~markup:(primaryText title ^ "\n\n" ^
                     escapeMarkup (transcode message))
            ~line_wrap:true ~selectable:true ~yalign:0. ~packing:v1#add ());
  t#add_button_stock `QUIT `QUIT;
  t#set_default_response `QUIT;
  grabFocus t; t#show(); ignore (t#run ()); t#destroy (); releaseFocus ();
  exit 1

(* ------ *)

let tryAgainOrQuit = fatalError

(* ------ *)

let getFirstRoot() =
  let t = GWindow.dialog ~title:"Root selection"
      ~modal:true ~allow_grow:true () in
  t#misc#grab_focus ();

  let hb = GPack.hbox
      ~packing:(t#vbox#pack ~expand:false ~padding:15) () in
  ignore(GMisc.label ~text:tryAgainMessage
           ~justify:`LEFT
           ~packing:(hb#pack ~expand:false ~padding:15) ());

  let f1 = GPack.hbox ~spacing:4
      ~packing:(t#vbox#pack ~expand:true ~padding:4) () in
  ignore (GMisc.label ~text:"Dir:" ~packing:(f1#pack ~expand:false) ());
  let fileE = GEdit.entry ~packing:f1#add () in
  fileE#misc#grab_focus ();
  let browseCommand() =
    file_dialog ~title:"Select a local directory"
      ~callback:fileE#set_text ~filename:fileE#text () in
  let b = GButton.button ~label:"Browse"
      ~packing:(f1#pack ~expand:false) () in
  ignore (b#connect#clicked ~callback:browseCommand);

  let f3 = t#action_area in
  let result = ref None in
  let contCommand() =
    result := Some(fileE#text);
    t#destroy () in
  let contButton = GButton.button ~stock:`OK ~packing:f3#add () in
  ignore (contButton#connect#clicked ~callback:contCommand);
  ignore (fileE#connect#activate ~callback:contCommand);
  contButton#grab_default ();
  let quitButton = GButton.button ~stock:`QUIT ~packing:f3#add () in
  ignore (quitButton#connect#clicked
            ~callback:(fun () -> result := None; t#destroy()));
  t#show ();
  ignore (t#connect#destroy ~callback:GMain.Main.quit);
  GMain.Main.main ();
  match !result with None -> None
  | Some file ->
      Some(Clroot.clroot2string(Clroot.ConnectLocal(Some file)))

(* ------ *)

let getSecondRoot () =
  let t = GWindow.dialog ~title:"Root selection"
      ~modal:true ~allow_grow:true () in
  t#misc#grab_focus ();

  let message = "Please enter the second directory you want to synchronize." in

  let vb = t#vbox in
  let hb = GPack.hbox ~packing:(vb#pack ~expand:false ~padding:15) () in
  ignore(GMisc.label ~text:message
           ~justify:`LEFT
           ~packing:(hb#pack ~expand:false ~padding:15) ());
  let helpB = GButton.button ~stock:`HELP ~packing:hb#add () in
  ignore (helpB#connect#clicked
            ~callback:(fun () -> okBox ~title:"Picking roots" ~typ:`INFO
                ~message:helpmessage));

  let result = ref None in

  let f = GPack.vbox ~packing:(vb#pack ~expand:false) () in

  let f1 = GPack.hbox ~spacing:4 ~packing:f#add () in
  ignore (GMisc.label ~text:"Directory:" ~packing:(f1#pack ~expand:false) ());
  let fileE = GEdit.entry ~packing:f1#add () in
  fileE#misc#grab_focus ();
  let browseCommand() =
    file_dialog ~title:"Select a local directory"
      ~callback:fileE#set_text ~filename:fileE#text () in
  let b = GButton.button ~label:"Browse"
      ~packing:(f1#pack ~expand:false) () in
  ignore (b#connect#clicked ~callback:browseCommand);

  let f0 = GPack.hbox ~spacing:4 ~packing:f#add () in
  let localB = GButton.radio_button ~packing:(f0#pack ~expand:false)
      ~label:"Local" () in
  let sshB = GButton.radio_button ~group:localB#group
      ~packing:(f0#pack ~expand:false)
      ~label:"SSH" () in
  let rshB = GButton.radio_button ~group:localB#group
      ~packing:(f0#pack ~expand:false) ~label:"RSH" () in
  let socketB = GButton.radio_button ~group:sshB#group
      ~packing:(f0#pack ~expand:false) ~label:"Socket" () in

  let f2 = GPack.hbox ~spacing:4 ~packing:f#add () in
  ignore (GMisc.label ~text:"Host:" ~packing:(f2#pack ~expand:false) ());
  let hostE = GEdit.entry ~packing:f2#add () in

  ignore (GMisc.label ~text:"(Optional) User:"
            ~packing:(f2#pack ~expand:false) ());
  let userE = GEdit.entry ~packing:f2#add () in

  ignore (GMisc.label ~text:"Port:"
            ~packing:(f2#pack ~expand:false) ());
  let portE = GEdit.entry ~packing:f2#add () in

  let varLocalRemote = ref (`Local : [`Local|`SSH|`RSH|`SOCKET]) in
  let localState() =
    varLocalRemote := `Local;
    hostE#misc#set_sensitive false;
    userE#misc#set_sensitive false;
    portE#misc#set_sensitive false;
    b#misc#set_sensitive true in
  let remoteState() =
    hostE#misc#set_sensitive true;
    b#misc#set_sensitive false;
    match !varLocalRemote with
      `SOCKET ->
        (portE#misc#set_sensitive true; userE#misc#set_sensitive false)
    | _ ->
        (portE#misc#set_sensitive false; userE#misc#set_sensitive true) in
  let protoState x =
    varLocalRemote := x;
    remoteState() in
  ignore (localB#connect#clicked ~callback:localState);
  ignore (sshB#connect#clicked ~callback:(fun () -> protoState(`SSH)));
  ignore (rshB#connect#clicked ~callback:(fun () -> protoState(`RSH)));
  ignore (socketB#connect#clicked ~callback:(fun () -> protoState(`SOCKET)));
  localState();
  let getRoot() =
    let file = fileE#text in
    let user = userE#text in
    let host = hostE#text in
    let port = portE#text in
    match !varLocalRemote with
      `Local ->
        Clroot.clroot2string(Clroot.ConnectLocal(Some file))
    | `SSH | `RSH ->
        Clroot.clroot2string(
        Clroot.ConnectByShell((if !varLocalRemote=`SSH then "ssh" else "rsh"),
                              host,
                              (if user="" then None else Some user),
                              (if port="" then None else Some port),
                              Some file))
    | `SOCKET ->
        Clroot.clroot2string(
        (* FIX: report an error if the port entry is not well formed *)
        Clroot.ConnectBySocket(host,
                               portE#text,
                               Some file)) in
  let contCommand() =
    try
      let root = getRoot() in
      result := Some root;
      t#destroy ()
    with Failure "int_of_string" ->
      if portE#text="" then
        okBox ~title:"Error" ~typ:`ERROR ~message:"Please enter a port"
      else okBox ~title:"Error" ~typ:`ERROR
          ~message:"The port you specify must be an integer"
    | _ ->
      okBox ~title:"Error" ~typ:`ERROR
        ~message:"Something's wrong with the values you entered, try again" in
  let f3 = t#action_area in
  let contButton =
    GButton.button ~stock:`OK ~packing:f3#add () in
  ignore (contButton#connect#clicked ~callback:contCommand);
  contButton#grab_default ();
  ignore (fileE#connect#activate ~callback:contCommand);
  let quitButton =
    GButton.button ~stock:`QUIT ~packing:f3#add () in
  ignore (quitButton#connect#clicked ~callback:safeExit);

  t#show ();
  ignore (t#connect#destroy ~callback:GMain.Main.quit);
  GMain.Main.main ();
  !result

(* ------ *)

let getPassword rootName msg =
  let t =
    GWindow.dialog ~title:"Unison: SSH connection" ~position:`CENTER
      ~no_separator:true ~modal:true ~allow_grow:false ~border_width:6 () in
  t#misc#grab_focus ();

  t#vbox#set_spacing 12;

  let header =
    primaryText
      (Format.sprintf "Connecting to '%s'..." (Unicode.protect rootName)) in

  let h1 = GPack.hbox ~border_width:6 ~spacing:12 ~packing:t#vbox#pack () in
  ignore (GMisc.image ~stock:`DIALOG_AUTHENTICATION ~icon_size:`DIALOG
            ~yalign:0. ~packing:h1#pack ());
  let v1 = GPack.vbox ~spacing:12 ~packing:h1#pack () in
  ignore(GMisc.label ~markup:(header ^ "\n\n" ^
                              escapeMarkup (Unicode.protect msg))
           ~selectable:true ~yalign:0. ~packing:v1#pack ());

  let passwordE = GEdit.entry ~packing:v1#pack ~visibility:false () in
  passwordE#misc#grab_focus ();

  t#add_button_stock `QUIT `QUIT;
  t#add_button_stock `OK `OK;
  t#set_default_response `OK;
  ignore (passwordE#connect#activate ~callback:(fun _ -> t#response `OK));

  grabFocus t; t#show();
  let res = t#run () in
  let pwd = passwordE#text in
  t#destroy (); releaseFocus ();
  gtk_sync true;
  begin match res with
    `DELETE_EVENT | `QUIT -> safeExit (); ""
  | `OK                   -> pwd
  end

let termInteract = Some getPassword

(* ------ *)

type profileInfo = {roots:string list; label:string option}

(* ------ *)

let profileKeymap = Array.create 10 None

let provideProfileKey filename k profile info =
  try
    let i = int_of_string k in
    if 0<=i && i<=9 then
      match profileKeymap.(i) with
        None -> profileKeymap.(i) <- Some(profile,info)
      | Some(otherProfile,_) ->
          raise (Util.Fatal
            ("Error scanning profile "^
                System.fspathToPrintString filename ^":\n"
             ^ "shortcut key "^k^" is already bound to profile "
             ^ otherProfile))
    else
      raise (Util.Fatal
        ("Error scanning profile "^ System.fspathToPrintString filename ^":\n"
         ^ "Value of 'key' preference must be a single digit (0-9), "
         ^ "not " ^ k))
  with int_of_string -> raise (Util.Fatal
    ("Error scanning profile "^ System.fspathToPrintString filename ^":\n"
     ^ "Value of 'key' preference must be a single digit (0-9), "
     ^ "not " ^ k))

(* ------ *)

let profilesAndRoots = ref []

let scanProfiles () =
  Array.iteri (fun i _ -> profileKeymap.(i) <- None) profileKeymap;
  profilesAndRoots :=
    (Safelist.map
       (fun f ->
          let f = Filename.chop_suffix f ".prf" in
          let filename = Prefs.profilePathname f in
          let fileContents = Safelist.map (fun (_, _, n, v) -> (n, v)) (Prefs.readAFile f) in
          let roots =
            Safelist.map snd
              (Safelist.filter (fun (n, _) -> n = "root") fileContents) in
          let label =
            try Some(Safelist.assoc "label" fileContents)
            with Not_found -> None in
          let info = {roots=roots; label=label} in
          (* If this profile has a 'key' binding, put it in the keymap *)
          (try
             let k = Safelist.assoc "key" fileContents in
             provideProfileKey filename k f info
           with Not_found -> ());
          (f, info))
       (Safelist.filter (fun name -> not (   Util.startswith name ".#"
                                          || Util.startswith name Os.tempFilePrefix))
          (Files.ls Os.unisonDir "*.prf")))

let getProfile () =
  (* The selected profile *)
  let result = ref None in

  (* Build the dialog *)
  let t = GWindow.dialog ~title:"Profiles" ~width:400 () in

  let cancelCommand _ = t#destroy (); exit 0 in
  let cancelButton = GButton.button ~stock:`CANCEL
      ~packing:t#action_area#add () in
  ignore (cancelButton#connect#clicked ~callback:cancelCommand);
  ignore (t#event#connect#delete ~callback:cancelCommand);
  cancelButton#misc#set_can_default true;

  let okCommand() =
    currentWindow := None;
    t#destroy () in
  let okButton =
    GButton.button ~stock:`OK ~packing:t#action_area#add () in
  ignore (okButton#connect#clicked ~callback:okCommand);
  okButton#misc#set_sensitive false;
  okButton#grab_default ();

  let vb = t#vbox in

  ignore (GMisc.label
            ~text:"Select an existing profile or create a new one"
            ~xpad:2 ~ypad:5 ~packing:(vb#pack ~expand:false) ());

  let sw =
    GBin.scrolled_window ~packing:(vb#pack ~expand:true) ~height:200
      ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
  let lst = GList.clist_poly ~selection_mode:`BROWSE ~packing:(sw#add) () in
  let selRow = ref 0 in
  let fillLst default =
    scanProfiles();
    lst#freeze ();
    lst#clear ();
    let i = ref 0 in (* FIX: Work around a lablgtk bug *)
    Safelist.iter
      (fun (profile, info) ->
         let labeltext =
           match info.label with None -> "" | Some(l) -> " ("^l^")" in
         let s = profile ^ labeltext in
         ignore (lst#append [s]);
         if profile = default then selRow := !i;
         lst#set_row_data !i (profile, info);
         incr i)
      (Safelist.sort (fun (p, _) (p', _) -> compare p p') !profilesAndRoots);
    let r = lst#rows in
    let p = if r < 2 then 0. else float !selRow /. float (r - 1) in
    lst#scroll_vertical `JUMP p;
    lst#thaw () in
  let tbl =
    GPack.table ~rows:2 ~columns:2 ~packing:(vb#pack ~expand:true) () in
  tbl#misc#set_sensitive false;
  ignore (GMisc.label ~text:"Root 1:" ~xpad:2
            ~packing:(tbl#attach ~left:0 ~top:0 ~expand:`NONE) ());
  ignore (GMisc.label ~text:"Root 2:" ~xpad:2
            ~packing:(tbl#attach ~left:0 ~top:1 ~expand:`NONE) ());
  let root1 =
    GEdit.entry ~packing:(tbl#attach ~left:1 ~top:0 ~expand:`X)
      ~editable:false () in
  let root2 =
    GEdit.entry ~packing:(tbl#attach ~left:1 ~top:1 ~expand:`X)
      ~editable:false () in
  root1#misc#set_can_focus false;
  root2#misc#set_can_focus false;
  let hb =
    GPack.hbox ~border_width:2 ~spacing:2 ~packing:(vb#pack ~expand:false) ()
  in
  let nw =
    GButton.button ~label:"Create new profile"
      ~packing:(hb#pack ~expand:false) () in
  ignore (nw#connect#clicked ~callback:(fun () ->
    let t =
      GWindow.dialog ~title:"New profile" ~modal:true ()
    in
    let vb = GPack.vbox ~border_width:4 ~packing:t#vbox#add () in
    let f = GPack.vbox ~packing:(vb#pack ~expand:true ~padding:4) () in
    let f0 = GPack.hbox ~spacing:4 ~packing:f#add () in
    ignore (GMisc.label ~text:"Profile name:"
              ~packing:(f0#pack ~expand:false) ());
    let prof = GEdit.entry ~packing:f0#add () in
    prof#misc#grab_focus ();

    let exit () = t#destroy (); GMain.Main.quit () in
    ignore (t#event#connect#delete ~callback:(fun _ -> exit (); true));

    let f3 = t#action_area in
    let okCommand () =
      let profile = prof#text in
      if profile <> "" then
        let filename = Prefs.profilePathname profile in
        if System.file_exists filename then
          okBox
            ~title:"Error" ~typ:`ERROR
            ~message:("Profile \""
                      ^ (transcodeFilename profile)
                      ^ "\" already exists!\nPlease select another name.")
        else
          (* Make an empty file *)
          let ch =
            System.open_out_gen
              [Open_wronly; Open_creat; Open_excl] 0o600 filename in
          close_out ch;
          fillLst profile;
          exit () in
    let okButton = GButton.button ~stock:`OK ~packing:f3#add () in
    ignore (okButton#connect#clicked ~callback:okCommand);
    okButton#grab_default ();
    let cancelButton =
      GButton.button ~stock:`CANCEL ~packing:f3#add () in
    ignore (cancelButton#connect#clicked ~callback:exit);

    t#show ();
    grabFocus t;
    GMain.Main.main ();
    releaseFocus ()));

  ignore (lst#connect#unselect_row ~callback:(fun ~row:_ ~column:_ ~event:_ ->
    root1#set_text ""; root2#set_text "";
    result := None;
    tbl#misc#set_sensitive false;
    okButton#misc#set_sensitive false));

  let select_row i =
    (* Inserting the first row triggers the signal, even before the row
       data is set. So, we need to catch the corresponding exception *)
    (try
      let (profile, info) = lst#get_row_data i in
      result := Some profile;
      begin match info.roots with
        [r1; r2] -> root1#set_text (Unicode.protect r1);
                    root2#set_text (Unicode.protect r2);
                    tbl#misc#set_sensitive true
      | _        -> root1#set_text ""; root2#set_text "";
                    tbl#misc#set_sensitive false
      end;
      okButton#misc#set_sensitive true
    with Gpointer.Null -> ()) in

  ignore (lst#connect#select_row
            ~callback:(fun ~row:i ~column:_ ~event:_ -> select_row i));

  ignore (lst#event#connect#button_press ~callback:(fun ev ->
    match GdkEvent.get_type ev with
      `TWO_BUTTON_PRESS ->
        okCommand ();
        true
    | _ ->
        false));
  fillLst "default";
  select_row !selRow;
  lst#misc#grab_focus ();
  currentWindow := Some (t :> GWindow.window_skel);
  ignore (t#connect#destroy ~callback:GMain.Main.quit);
  t#show ();
  GMain.Main.main ();
  !result

(* ------ *)

let documentation sect =
  let title = "Documentation" in
  let t = GWindow.dialog ~title () in
  let t_dismiss =
    GButton.button ~stock:`CLOSE ~packing:t#action_area#add () in
  t_dismiss#grab_default ();
  let dismiss () = t#destroy () in
  ignore (t_dismiss#connect#clicked ~callback:dismiss);
  ignore (t#event#connect#delete ~callback:(fun _ -> dismiss (); true));

  let (name, docstr) = Safelist.assoc sect Strings.docs in
  let docstr = transcodeDoc docstr in
  let hb = GPack.hbox ~packing:(t#vbox#pack ~expand:false ~padding:2) () in
  let optionmenu =
    GMenu.option_menu ~packing:(hb#pack ~expand:true ~fill:false) () in

  let t_text =
    new scrolled_text ~editable:false
      ~width:80 ~height:20 ~packing:t#vbox#add ()
  in
  t_text#insert docstr;

  let sect_idx = ref 0 in
  let idx = ref 0 in
  let menu = GMenu.menu () in
  let addDocSection (shortname, (name, docstr)) =
    if shortname <> "" && name <> "" then begin
      if shortname = sect then sect_idx := !idx;
      incr idx;
      let item = GMenu.menu_item ~label:name ~packing:menu#append () in
      let docstr = transcodeDoc docstr in
      ignore
        (item#connect#activate ~callback:(fun () -> t_text#insert docstr))
    end
  in
  Safelist.iter addDocSection Strings.docs;
  optionmenu#set_menu menu;
  optionmenu#set_history !sect_idx;

  t#show ()

(* ------ *)

let messageBox ~title ?(action = fun t -> t#destroy) ?(modal = false) message =
  let utitle = transcode title in
  let t = GWindow.dialog ~title:utitle ~modal ~position:`CENTER () in
  let t_dismiss = GButton.button ~stock:`CLOSE ~packing:t#action_area#add () in
  t_dismiss#grab_default ();
  ignore (t_dismiss#connect#clicked ~callback:(action t));
  let t_text =
    new scrolled_text ~editable:false
      ~width:80 ~height:20 ~packing:t#vbox#add ()
  in
  t_text#insert message;
  ignore (t#event#connect#delete ~callback:(fun _ -> action t (); true));
  t#show ();
  if modal then begin
    grabFocus t;
    GMain.Main.main ();
    releaseFocus ()
  end

(* twoBoxAdvanced: Display a message in a window and wait for the user
   to hit one of two buttons.  Return true if the first button is
   chosen, false if the second button is chosen. Also has a button for 
   showing more details to the user in a messageBox dialog *)
let twoBoxAdvanced ~title ~message ~longtext ~advLabel ~astock ~bstock =
  let t =
    GWindow.dialog ~border_width:6 ~modal:false ~no_separator:true
      ~allow_grow:false () in
  t#vbox#set_spacing 12;
  let h1 = GPack.hbox ~border_width:6 ~spacing:12 ~packing:t#vbox#pack () in
  ignore (GMisc.image ~stock:`DIALOG_WARNING ~icon_size:`DIALOG
            ~yalign:0. ~packing:h1#pack ());
  let v1 = GPack.vbox ~spacing:12 ~packing:h1#pack () in
  ignore (GMisc.label
            ~markup:(primaryText title ^ "\n\n" ^ escapeMarkup message)
            ~selectable:true ~yalign:0. ~packing:v1#add ());
  t#add_button_stock `CANCEL `NO;
  let cmd () =
    messageBox ~title:"Details" ~modal:false longtext
  in
  t#add_button advLabel `HELP;
  t#add_button_stock `APPLY `YES;
  t#set_default_response `NO;
  let res = ref false in
  let setRes signal =
    match signal with
      `YES -> res := true; t#destroy ()
    | `NO -> res := false; t#destroy ()
    | `HELP -> cmd ()
    | _ -> ()
  in
  ignore (t#connect#response ~callback:setRes);
  ignore (t#connect#destroy ~callback:GMain.Main.quit);
  grabFocus t; t#show();
  GMain.Main.main();
  releaseFocus ();
  !res


(**********************************************************************
                             TOP-LEVEL WINDOW
 **********************************************************************)

let myWindow = ref None

let getMyWindow () =
  if not (Prefs.read Uicommon.reuseToplevelWindows) then begin
    (match !myWindow with Some(w) -> w#destroy() | None -> ());
    myWindow := None;
  end;
  let w = match !myWindow with
            Some(w) ->
              Safelist.iter w#remove w#children;
              w
          | None ->
              (* Used to be ~position:`CENTER -- maybe that was better... *)
              GWindow.window ~kind:`TOPLEVEL ~position:`CENTER
                ~title:myNameCapitalized () in
  myWindow := Some(w);
  w#set_allow_grow true;
  w

(* ------ *)

let displayWaitMessage () =
  if not (Prefs.read Uicommon.contactquietly) then begin
    (* FIX: should use a dialog *)
    let w = getMyWindow() in
    w#set_allow_grow false;
    currentWindow := Some (w :> GWindow.window_skel);
    let v = GPack.vbox ~packing:(w#add) ~border_width:2 () in
    let bb =
      GPack.button_box `HORIZONTAL ~layout:`END ~spacing:10 ~border_width:5
        ~packing:(v#pack ~fill:true ~from:`END) () in
    let h1 = GPack.hbox ~border_width:12 ~spacing:12 ~packing:v#pack () in
    ignore (GMisc.image ~stock:`DIALOG_INFO ~icon_size:`DIALOG
              ~yalign:0. ~packing:h1#pack ());
    let m =
      GMisc.label ~markup:(primaryText (Uicommon.contactingServerMsg()))
        ~yalign:0. ~selectable:true ~packing:h1#add () in
    m#misc#set_can_focus false;
    let quit = GButton.button ~stock:`QUIT ~packing:bb#pack () in
    quit#grab_default ();
    ignore (quit#connect#clicked ~callback:safeExit);
    ignore (w#event#connect#delete ~callback:(fun _ -> safeExit (); true));
    w#show()
  end

(* ------ *)

type status = NoStatus | Done | Failed

let rec createToplevelWindow () =
  let toplevelWindow = getMyWindow() in
  (* There is already a default icon under Windows, and transparent
     icons are not supported by all version of Windows *)
  if Util.osType <> `Win32 then toplevelWindow#set_icon (Some icon);
  let toplevelVBox = GPack.vbox ~packing:toplevelWindow#add () in

  (*******************************************************************
   Statistic window
   *******************************************************************)

  let stat_win = statistics () in

  (*******************************************************************
   Groups of things that are sensitive to interaction at the same time
   *******************************************************************)
  let grAction = ref [] in
  let grDiff = ref [] in
  let grGo = ref [] in
  let grRescan = ref [] in
  let grDetail = ref [] in
  let grAdd gr w = gr := w#misc::!gr in
  let grSet gr st = Safelist.iter (fun x -> x#set_sensitive st) !gr in
  let grDisactivateAll () =
    grSet grAction false;
    grSet grDiff false;
    grSet grGo false;
    grSet grRescan false;
    grSet grDetail false
  in

  (*********************************************************************
    Create the menu bar
   *********************************************************************)
  let topHBox = GPack.hbox ~packing:(toplevelVBox#pack ~expand:false) () in

  let menuBar =
    GMenu.menu_bar ~border_width:0
      ~packing:(topHBox#pack ~expand:true) () in
  let menus = new GMenu.factory ~accel_modi:[] menuBar in
  let accel_group = menus#accel_group in
  toplevelWindow#add_accel_group accel_group;
  let add_submenu ?(modi=[]) ~label () =
    new GMenu.factory ~accel_group ~accel_modi:modi (menus#add_submenu label)
  in

  let profileLabel =
    GMisc.label ~text:"" ~packing:(topHBox#pack ~expand:false ~padding:2) () in

  let displayNewProfileLabel p =
    let label = Prefs.read Uicommon.profileLabel in
    let s =
      if p="" then ""
      else if p="default" then label
      else if label="" then p
      else p ^ " (" ^ label ^ ")" in
    toplevelWindow#set_title
      (if s = "" then myNameCapitalized else
       Format.sprintf "%s [%s]" myNameCapitalized s);
    let s = if s="" then "" else "Profile: " ^ s in
    profileLabel#set_text (transcodeFilename s)
  in

  begin match !Prefs.profileName with
    None -> ()
  | Some(p) -> displayNewProfileLabel p
  end;

  (*********************************************************************
    Create the menus
   *********************************************************************)
  let fileMenu = add_submenu ~label:"Synchronization" ()
  and actionsMenu = add_submenu ~label:"Actions" ()
  and ignoreMenu = add_submenu ~modi:[`SHIFT] ~label:"Ignore" ()
  and sortMenu = add_submenu ~label:"Sort" ()
  and helpMenu = add_submenu ~label:"Help" () in

  (*********************************************************************
    Action bar
   *********************************************************************)
  let actionBar =
    let hb = GBin.handle_box ~packing:(toplevelVBox#pack ~expand:false) () in
    GButton.toolbar ~style:`BOTH
      (* 2003-0519 (stse): how to set space size in gtk 2.0? *)
      (* Answer from Jacques Garrigue: this can only be done in
         the user's.gtkrc, not programmatically *)
      ~orientation:`HORIZONTAL ~tooltips:true (* ~space_size:10 *)
      ~packing:(hb#add) () in

  (*********************************************************************
    Create the main window
   *********************************************************************)
  let mainWindow =
    let sw =
      GBin.scrolled_window ~packing:(toplevelVBox#pack ~expand:true)
        ~height:(Prefs.read Uicommon.mainWindowHeight * 12)
        ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
    GList.clist ~columns:5 ~titles_show:true
      ~selection_mode:`BROWSE ~packing:sw#add () in
  mainWindow#misc#grab_focus ();
(*
  let cols = new GTree.column_list in
  let c_replica1 = cols#add Gobject.Data.string in
  let c_action   = cols#add Gobject.Data.gobject in
  let c_replica2 = cols#add Gobject.Data.string in
  let c_status   = cols#add Gobject.Data.string in
  let c_path     = cols#add Gobject.Data.string in
  let lst_store = GTree.list_store cols in
  let lst =
    GTree.view ~model:lst_store ~packing:(toplevelVBox#add)
      ~headers_clickable:false () in
  let s = Uicommon.roots2string () in
  ignore (lst#append_column
    (GTree.view_column
       ~title:(" " ^ Unicode.protect (String.sub s  0 12) ^ " ")
       ~renderer:(GTree.cell_renderer_text [], ["text", c_replica1]) ()));
  ignore (lst#append_column
    (GTree.view_column ~title:"  Action  "
       ~renderer:(GTree.cell_renderer_pixbuf [], ["pixbuf", c_action]) ()));
  ignore (lst#append_column
    (GTree.view_column
       ~title:(" " ^ Unicode.protect (String.sub s  15 12) ^ " ")
       ~renderer:(GTree.cell_renderer_text [], ["text", c_replica2]) ()));
  ignore (lst#append_column
    (GTree.view_column ~title:"  Status  " ()));
  ignore (lst#append_column
    (GTree.view_column ~title:"  Path  "
       ~renderer:(GTree.cell_renderer_text [], ["text", c_path]) ()));
*)

(*
  let status_width =
    let font = mainWindow#misc#style#font in
    4 + max (max (Gdk.Font.string_width font "working")
                 (Gdk.Font.string_width font "skipped"))
                 (Gdk.Font.string_width font "  Action  ")
  in
*)
  mainWindow#set_column ~justification:`CENTER 1;
  mainWindow#set_column
    ~justification:`CENTER (*~auto_resize:false ~width:status_width*) 3;

  let setMainWindowColumnHeaders () =
    (* FIX: roots2string should return a pair *)
    let s = Uicommon.roots2string () in
    Array.iteri
      (fun i data ->
         mainWindow#set_column
           ~title_active:false ~auto_resize:true ~title:data i)
      [| " " ^ Unicode.protect (String.sub s  0 12) ^ " "; "  Action  ";
         " " ^ Unicode.protect (String.sub s 15 12) ^ " "; "  Status  ";
         " Path" |]
  in
  setMainWindowColumnHeaders();

  (*********************************************************************
    Create the details window
   *********************************************************************)

  let showDetCommand () =
    let details =
      match !current with
	None ->
          None
      | Some row ->
          let path = Path.toString !theState.(row).ri.path1 in
	  match !theState.(row).whatHappened with
	    Some (Util.Failed _, Some det) ->
              Some ("Merge execution details for file" ^
                    transcodeFilename path,
                    det)
	  | _ ->
              match !theState.(row).ri.replicas with
                Problem err ->
                  Some ("Errors for file " ^ transcodeFilename path, err)
              | Different diff ->
                  let prefix s l =
                    Safelist.map (fun err -> Format.sprintf "%s%s\n" s err) l
                  in
                  let errors =
                    Safelist.append
                      (prefix "[root 1]: " diff.errors1)
                      (prefix "[root 2]: " diff.errors2)
                  in
                  let errors =
                    match !theState.(row).whatHappened with
                       Some (Util.Failed err, _) -> err :: errors
                    |  _                         -> errors
                  in
                  Some ("Errors for file " ^ transcodeFilename path,
                        String.concat "\n" errors)
    in
    match details with
      None                  -> ((* Should not happen *))
    | Some (title, details) -> messageBox ~title (transcode details)
  in

  let detailsWindow =
    let sw =
      GBin.scrolled_window ~packing:(toplevelVBox#pack ~expand:false)
        ~shadow_type:`IN ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
    GText.view ~editable:false ~wrap_mode:`NONE ~packing:sw#add ()
  in
  detailsWindow#misc#modify_font (Lazy.force fontMonospaceMediumPango);
  detailsWindow#misc#set_size_chars ~height:3 ~width:112 ();
  detailsWindow#misc#set_can_focus false;

  let updateButtons () =
    match !current with
      None ->
        grSet grAction false;
        grSet grDiff false;
	grSet grDetail false
    | Some row ->
        let details =
          begin match !theState.(row).ri.replicas with
            Different diff -> diff.errors1 <> [] || diff.errors2 <> []
          | Problem _      -> true
          end
            ||
          begin match !theState.(row).whatHappened with
            Some (Util.Failed _, _) -> true
          | _                       -> false
          end
        in
        grSet grDetail details;
        if not !busy then begin
          let activateAction = !theState.(row).whatHappened = None in
          let activateDiff =
            activateAction &&
            match !theState.(row).ri.replicas with
              Different {rc1 = {typ = `FILE}; rc2 = {typ = `FILE}} ->
                true
            | _ ->
                false
          in
          grSet grAction activateAction;
          grSet grDiff activateDiff
        end;
  in

  let makeRowVisible row =
    if mainWindow#row_is_visible row <> `FULL then begin
      let adj = mainWindow#vadjustment in
      let upper = adj#upper and lower = adj#lower in
      let v =
        float row /. float (mainWindow#rows + 1) *. (upper-.lower) +. lower
      in
      adj#set_value (min v (upper -. adj#page_size));
    end in

  let makeFirstUnfinishedVisible pRiInFocus =
    let im = Array.length !theState in
    let rec find i =
      if i >= im then makeRowVisible im else
      match pRiInFocus (!theState.(i).ri), !theState.(i).whatHappened with
        true, None -> makeRowVisible i
      | _ -> find (i+1) in
    find 0
  in

  let updateDetails () =
    begin match !current with
      None ->
        detailsWindow#buffer#set_text ""
    | Some row ->
        makeRowVisible row;
        let details =
          match !theState.(row).whatHappened with
            None -> Uicommon.details2string !theState.(row).ri "  "
          | Some(Util.Succeeded, _) -> Uicommon.details2string !theState.(row).ri "  "
          | Some(Util.Failed(s), None) -> s
	  | Some(Util.Failed(s), Some resultLog) -> s in
	let path = Path.toString !theState.(row).ri.path1 in
        let txt = transcodeFilename path ^ "\n" ^ transcode details in
        let len = String.length txt in
        let txt =
          if txt.[len - 1] = '\n' then String.sub txt 0 (len - 1) else txt in
        detailsWindow#buffer#set_text txt
    end;
    (* Display text *)
    updateButtons () in

  (*********************************************************************
    Status window
   *********************************************************************)

  let statusHBox = GPack.hbox ~packing:(toplevelVBox#pack ~expand:false) () in

  let progressBar =
    GRange.progress_bar ~packing:(statusHBox#pack ~expand:false) () in
  progressBar#set_pulse_step 0.02;
  let progressBarPulse = ref false in

  let statusWindow =
    GMisc.statusbar ~packing:(statusHBox#pack ~expand:true) () in
  let statusContext = statusWindow#new_context ~name:"status" in
  ignore (statusContext#push "");

  let displayStatus m =
    statusContext#pop ();
    if !progressBarPulse then progressBar#pulse ();
    ignore (statusContext#push (transcode m));
    (* Force message to be displayed immediately *)
    gtk_sync false
  in

  let formatStatus major minor = (Util.padto 30 (major ^ "  ")) ^ minor in

  (* Tell the Trace module about the status printer *)
  Trace.messageDisplayer := displayStatus;
  Trace.statusFormatter := formatStatus;
  Trace.sendLogMsgsToStderr := false;

  (*********************************************************************
    Functions used to print in the main window
   *********************************************************************)

  let select i =
    let r = mainWindow#rows in
    let p = if r < 2 then 0. else (float i +. 0.5) /. float (r - 1) in
    mainWindow#scroll_vertical `JUMP (min p 1.)
  in

  ignore (mainWindow#connect#select_row ~callback:
      (fun ~row ~column ~event -> current := Some row; updateDetails ()));

  let nextInteresting () =
    let l = Array.length !theState in
    let start = match !current with Some i -> i + 1 | None -> 0 in
    let rec loop i =
      if i < l then
        match !theState.(i).ri.replicas with
          Different {direction = dir}
              when not (Prefs.read Uicommon.auto) || dir = Conflict ->
            select i
        | _ ->
            loop (i + 1) in
    loop start in
  let selectSomethingIfPossible () =
    if !current=None then nextInteresting () in

  let columnsOf i =
    let oldPath = if i = 0 then Path.empty else !theState.(i-1).ri.path1 in
    let status =
      match !theState.(i).ri.replicas with
        Different {direction = Conflict} | Problem _ ->
          NoStatus
      | _ ->
          match !theState.(i).whatHappened with
            None                     -> NoStatus
          | Some (Util.Succeeded, _) -> Done
          | Some (Util.Failed _, _)  -> Failed
    in
    let (r1, action, r2, path) =
      Uicommon.reconItem2stringList oldPath !theState.(i).ri in
    (r1, action, r2, status, path)
  in

  let greenPixel  = "00dd00" in
  let redPixel    = "ff2040" in
  let lightbluePixel = "8888FF" in
  let orangePixel = "ff9303" in
(*
  let yellowPixel = "999900" in
  let blackPixel  = "000000" in
*)
  let buildPixmap p =
    GDraw.pixmap_from_xpm_d ~window:toplevelWindow ~data:p () in
  let buildPixmaps f c1 =
    (buildPixmap (f c1), buildPixmap (f lightbluePixel)) in

  let doneIcon = buildPixmap Pixmaps.success in
  let failedIcon = buildPixmap Pixmaps.failure in
  let rightArrow = buildPixmaps Pixmaps.copyAB greenPixel in
  let leftArrow = buildPixmaps Pixmaps.copyBA greenPixel in
  let orangeRightArrow = buildPixmaps Pixmaps.copyAB orangePixel in
  let orangeLeftArrow = buildPixmaps Pixmaps.copyBA orangePixel in
  let ignoreAct = buildPixmaps Pixmaps.ignore redPixel in
  let failedIcons = (failedIcon, failedIcon) in
  let mergeLogo = buildPixmaps Pixmaps.mergeLogo greenPixel in
(*
  let rightArrowBlack = buildPixmap (Pixmaps.copyAB blackPixel) in
  let leftArrowBlack = buildPixmap (Pixmaps.copyBA blackPixel) in
  let mergeLogoBlack = buildPixmap (Pixmaps.mergeLogo blackPixel) in
*)

  let displayArrow i j action =
    let changedFromDefault = match !theState.(j).ri.replicas with
        Different diff -> diff.direction <> diff.default_direction
      | _ -> false in
    let sel pixmaps =
      if changedFromDefault then snd pixmaps else fst pixmaps in
    let pixmaps =
      match action with
        Uicommon.AError      -> failedIcons
      | Uicommon.ASkip _     -> ignoreAct
      | Uicommon.ALtoR false -> rightArrow
      | Uicommon.ALtoR true  -> orangeRightArrow
      | Uicommon.ARtoL false -> leftArrow
      | Uicommon.ARtoL true  -> orangeLeftArrow
      | Uicommon.AMerge      -> mergeLogo
    in
    mainWindow#set_cell ~pixmap:(sel pixmaps) i 1
  in


  let displayStatusIcon i status =
    match status with
    | Failed   -> mainWindow#set_cell ~pixmap:failedIcon i 3
    | Done     -> mainWindow#set_cell ~pixmap:doneIcon i 3
    | NoStatus -> mainWindow#set_cell ~text:" " i 3 in

  let displayMain() =
    (* The call to mainWindow#clear below side-effect current,
       so we save the current value before we clear out the main window and
       rebuild it. *)
    let savedCurrent = !current in
    mainWindow#freeze ();
    mainWindow#clear ();
    for i = Array.length !theState - 1 downto 0 do
      let (r1, action, r2, status, path) = columnsOf i in
(*
let row = lst_store#prepend () in
lst_store#set ~row ~column:c_replica1 r1;
lst_store#set ~row ~column:c_replica2 r2;
lst_store#set ~row ~column:c_status status;
lst_store#set ~row ~column:c_path path;
*)
      ignore (mainWindow#prepend
                [ r1; ""; r2; ""; transcodeFilename path ]);
      displayArrow 0 i action;
      displayStatusIcon i status
    done;
    debug (fun()-> Util.msg "reset current to %s\n"
             (match savedCurrent with None->"None" | Some(i) -> string_of_int i));
    if savedCurrent <> None then current := savedCurrent;
    selectSomethingIfPossible ();
    begin match !current with Some idx -> select idx | None -> () end;
    mainWindow#thaw ();
    updateDetails ();
 in

  let redisplay i =
    let (r1, action, r2, status, path) = columnsOf i in
    mainWindow#freeze ();
    mainWindow#set_cell ~text:r1     i 0;
    displayArrow i i action;
    mainWindow#set_cell ~text:r2     i 2;
    displayStatusIcon i status;
    mainWindow#set_cell ~text:(transcodeFilename path)   i 4;
    if status = Failed then
      mainWindow#set_cell
        ~text:(transcodeFilename path ^
               "       [failed: click on this line for details]") i 4;
    mainWindow#thaw ();
    if !current = Some i then updateDetails ();
    updateButtons () in

  let fastRedisplay i =
    let (r1, action, r2, status, path) = columnsOf i in
    displayStatusIcon i status;
    if status = Failed then
      mainWindow#set_cell
        ~text:(transcodeFilename path ^
               "       [failed: click on this line for details]") i 4;
    if !current = Some i then updateDetails ();
  in

  let totalBytesToTransfer = ref Uutil.Filesize.zero in
  let totalBytesTransferred = ref Uutil.Filesize.zero in

  let lastFrac = ref 0. in
  let displayGlobalProgress v =
    if v = 0. || abs_float (v -. !lastFrac) > 1. then begin
      lastFrac := v;
      progressBar#set_fraction (max 0. (min 1. (v /. 100.)))
    end;
(*
    if v > 0.5 then
      progressBar#set_text (Util.percent2string v)
    else
      progressBar#set_text "";
*)
  in

  let showGlobalProgress b =
    (* Concatenate the new message *)
    totalBytesTransferred := Uutil.Filesize.add !totalBytesTransferred b;
    let v =
      (Uutil.Filesize.percentageOfTotalSize
         !totalBytesTransferred !totalBytesToTransfer)
    in
    displayGlobalProgress v
  in

  let initGlobalProgress b =
    totalBytesToTransfer := b;
    totalBytesTransferred := Uutil.Filesize.zero;
    displayGlobalProgress 0.
  in

  let (root1,root2) = Globals.roots () in
  let root1IsLocal = fst root1 = Local in
  let root2IsLocal = fst root2 = Local in

  let showProgress i bytes dbg =
    let i = Uutil.File.toLine i in
    let item = !theState.(i) in
    item.bytesTransferred <- Uutil.Filesize.add item.bytesTransferred bytes;
    let b = item.bytesTransferred in
    let len = item.bytesToTransfer in
    let newstatus =
      if b = Uutil.Filesize.zero || len = Uutil.Filesize.zero then "start "
      else if len = Uutil.Filesize.zero then
        Printf.sprintf "%5s " (Uutil.Filesize.toString b)
      else Util.percent2string (Uutil.Filesize.percentageOfTotalSize b len) in
    let dbg = if Trace.enabled "progress" then dbg ^ "/" else "" in
    let newstatus = dbg ^ newstatus in
    let oldstatus = mainWindow#cell_text i 3 in
    if oldstatus <> newstatus then mainWindow#set_cell ~text:newstatus i 3;
    showGlobalProgress bytes;
    gtk_sync false;
    begin match item.ri.replicas with
      Different diff ->
        begin match diff.direction with
          Replica1ToReplica2 ->
            if root2IsLocal then
              clientWritten := !clientWritten +. Uutil.Filesize.toFloat bytes
            else
              serverWritten := !serverWritten +. Uutil.Filesize.toFloat bytes
        | Replica2ToReplica1 ->
            if root1IsLocal then
              clientWritten := !clientWritten +. Uutil.Filesize.toFloat bytes
            else
              serverWritten := !serverWritten +. Uutil.Filesize.toFloat bytes
        | Conflict | Merge ->
            (* Diff / merge *)
            clientWritten := !clientWritten +. Uutil.Filesize.toFloat bytes
        end
    | _ ->
        assert false
    end
  in

  (* Install showProgress so that we get called back by low-level
     file transfer stuff *)
  Uutil.setProgressPrinter showProgress;

  (* Apply new ignore patterns to the current state, expecting that the
     number of reconitems will grow smaller. Adjust the display, being
     careful to keep the cursor as near as possible to its position
     before the new ignore patterns take effect. *)
  let ignoreAndRedisplay () =
    let lst = Array.to_list !theState in
    (* FIX: we should actually test whether any prefix is now ignored *)
    let keep sI = not (Globals.shouldIgnore sI.ri.path1) in
    begin match !current with
      None ->
        theState := Array.of_list (Safelist.filter keep lst)
    | Some index ->
        let i = ref index in
        let l = ref [] in
        Array.iteri
          (fun j sI -> if keep sI then l := sI::!l
                       else if j < !i then decr i)
          !theState;
        theState := Array.of_list (Safelist.rev !l);
        current := if !l = [] then None
                   else Some (min (!i) ((Array.length !theState) - 1));
    end;
    displayMain() in

  let sortAndRedisplay () =
    current := None;
    let compareRIs = Sortri.compareReconItems() in
    Array.stable_sort (fun si1 si2 -> compareRIs si1.ri si2.ri) !theState;
    displayMain() in

  (******************************************************************
   Main detect-updates-and-reconcile logic
   ******************************************************************)

  let commitUpdates () =
    Trace.status "Updating synchronizer state";
    let t = Trace.startTimer "Updating synchronizer state" in
    gtk_sync true;
    Update.commitUpdates();
    Trace.showTimer t
  in

  let detectUpdatesAndReconcile () =
    grDisactivateAll ();

    mainWindow#clear();
    detailsWindow#buffer#set_text "";

    progressBarPulse := true;
    sync_action := Some (fun () -> progressBar#pulse ());
    let findUpdates () =
      let t = Trace.startTimer "Checking for updates" in
      Trace.status "Looking for changes";
      let updates = Update.findUpdates () in
      Trace.showTimer t;
      updates in
    let reconcile updates =
      let t = Trace.startTimer "Reconciling" in
      let reconRes = Recon.reconcileAll ~allowPartial:true updates in
      Trace.showTimer t;
      reconRes in
    let (reconItemList, thereAreEqualUpdates, dangerousPaths) =
      reconcile (findUpdates ()) in
    if not !Update.foundArchives then commitUpdates ();
    if reconItemList = [] then
      if thereAreEqualUpdates then begin
        if !Update.foundArchives then commitUpdates ();
        Trace.status
          "Replicas have been changed only in identical ways since last sync"
      end else
        Trace.status "Everything is up to date"
    else
      Trace.status "Check and/or adjust selected actions; then press Go";
    theState :=
      Array.of_list
         (Safelist.map
            (fun ri -> { ri = ri;
                         bytesTransferred = Uutil.Filesize.zero;
                         bytesToTransfer = Uutil.Filesize.zero;
                         whatHappened = None })
            reconItemList);
    current := None;
    displayMain();
    progressBarPulse := false; sync_action := None; displayGlobalProgress 0.;
    grSet grGo (Array.length !theState > 0);
    grSet grRescan true;
    if Prefs.read Globals.confirmBigDeletes then begin
      if dangerousPaths <> [] then begin
        Prefs.set Globals.batch false;
        Util.warn (Uicommon.dangerousPathMsg dangerousPaths)
      end;
    end;
  in

  (*********************************************************************
    Help menu
   *********************************************************************)
  let addDocSection (shortname, (name, docstr)) =
    if shortname = "about" then
      ignore (helpMenu#add_image_item
                ~stock:`ABOUT ~callback:(fun () -> documentation shortname)
                ~label:name ())
    else if shortname <> "" && name <> "" then
      ignore (helpMenu#add_item
                ~callback:(fun () -> documentation shortname)
                name) in
  Safelist.iter addDocSection Strings.docs;

  (*********************************************************************
    Ignore menu
   *********************************************************************)
  let addRegExpByPath pathfunc =
    match !current with
      Some i ->
        Uicommon.addIgnorePattern (pathfunc !theState.(i).ri.path1);
        ignoreAndRedisplay ()
    | None ->
        () in
  grAdd grAction
    (ignoreMenu#add_item ~key:GdkKeysyms._i
       ~callback:(fun () -> getLock (fun () ->
          addRegExpByPath Uicommon.ignorePath))
       "Permanently ignore this path");
  grAdd grAction
    (ignoreMenu#add_item ~key:GdkKeysyms._E
       ~callback:(fun () -> getLock (fun () ->
          addRegExpByPath Uicommon.ignoreExt))
       "Permanently ignore files with this extension");
  grAdd grAction
    (ignoreMenu#add_item ~key:GdkKeysyms._N
       ~callback:(fun () -> getLock (fun () ->
          addRegExpByPath Uicommon.ignoreName))
       "Permanently ignore files with this name (in any dir)");

  (*
  grAdd grRescan
    (ignoreMenu#add_item ~callback:
       (fun () -> getLock ignoreDialog) "Edit ignore patterns");
  *)

  (*********************************************************************
    Sort menu
   *********************************************************************)
  grAdd grAction
    (sortMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Sortri.sortByName();
          sortAndRedisplay()))
       "Sort entries by name");
  grAdd grAction
    (sortMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Sortri.sortBySize();
          sortAndRedisplay()))
       "Sort entries by size");
  grAdd grAction
    (sortMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Sortri.sortNewFirst();
          sortAndRedisplay()))
       "Sort new entries first");
  grAdd grAction
    (sortMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Sortri.restoreDefaultSettings();
          sortAndRedisplay()))
       "Go back to default ordering");

  (*********************************************************************
    Main function : synchronize
   *********************************************************************)
  let synchronize () =
    if Array.length !theState = 0 then
      Trace.status "Nothing to synchronize"
    else begin
      grDisactivateAll ();

      Trace.status "Propagating changes";
      Transport.logStart ();
      let totalLength =
        Array.fold_left
          (fun l si ->
             si.bytesTransferred <- Uutil.Filesize.zero;
             let len =
               if si.whatHappened = None then Common.riLength si.ri else
               Uutil.Filesize.zero
             in
             si.bytesToTransfer <- len;
             Uutil.Filesize.add l len)
          Uutil.Filesize.zero !theState in
      initGlobalProgress totalLength;
      let t = Trace.startTimer "Propagating changes" in
      let im = Array.length !theState in
      let rec loop i actions pRiThisRound =
        if i < im then begin
          let theSI = !theState.(i) in
	  let textDetailed = ref None in
          let action =
            match theSI.whatHappened with
              None ->
                if not (pRiThisRound theSI.ri) then
                  return ()
                else
                  catch (fun () ->
                           Transport.transportItem
                             theSI.ri (Uutil.File.ofLine i)
                             (fun title text -> 
			       textDetailed := (Some text);
                               if Prefs.read Uicommon.confirmmerge then
				 twoBoxAdvanced
				   ~title:title
				   ~message:("Do you want to commit the changes to"
					     ^ " the replicas ?")
				   ~longtext:text
				   ~advLabel:"View details..."
				   ~astock:`YES
				   ~bstock:`NO
                               else 
				 true)
                           >>= (fun () ->
                             return Util.Succeeded))
                         (fun e ->
                           match e with
                             Util.Transient s ->
                               return (Util.Failed s)
                           | _ ->
                               fail e)
                    >>= (fun res ->
                      let rem =
                        Uutil.Filesize.sub
                          theSI.bytesToTransfer theSI.bytesTransferred
                      in
                      if rem <> Uutil.Filesize.zero then
                        showProgress (Uutil.File.ofLine i) rem "done";
                      theSI.whatHappened <- Some (res, !textDetailed);
                  fastRedisplay i;
                  sync_action :=
                    Some
                      (fun () ->
                         makeFirstUnfinishedVisible pRiThisRound;
                         sync_action := None);
                  gtk_sync false;
                  return ())
            | Some _ ->
                return () (* Already processed this one (e.g. merged it) *)
          in
          loop (i + 1) (action :: actions) pRiThisRound
        end else
          actions
      in
      Lwt_unix.run
        (let actions = loop 0 [] (fun ri -> not (Common.isDeletion ri)) in
         Lwt_util.join actions);
      Lwt_unix.run
        (let actions = loop 0 [] Common.isDeletion in
         Lwt_util.join actions);
      Transport.logFinish ();
      Trace.showTimer t;
      commitUpdates ();

      let failures =
        let count =
          Array.fold_left
            (fun l si ->
               l + (match si.whatHappened with Some(Util.Failed(_), _) -> 1 | _ -> 0))
            0 !theState in
        if count = 0 then [] else
          [Printf.sprintf "%d failure%s" count (if count=1 then "" else "s")]
      in
      let partials =
        let count =
          Array.fold_left
            (fun l si ->
               l + match si.whatHappened with
                     Some(Util.Succeeded, _)
                     when partiallyProblematic si.ri &&
                          not (problematic si.ri) ->
                       1
                   | _ ->
                       0)
            0 !theState in
        if count = 0 then [] else
          [Printf.sprintf "%d partially transferred" count] in
      let skipped =
        let count =
          Array.fold_left
            (fun l si ->
               l + (if problematic si.ri then 1 else 0))
            0 !theState in
        if count = 0 then [] else
          [Printf.sprintf "%d skipped" count] in
      Trace.status
        (Printf.sprintf "Synchronization complete         %s"
           (String.concat ", " (failures @ partials @ skipped)));
      displayGlobalProgress 0.;

      grSet grRescan true
    end in

  (*********************************************************************
    Quit button
   *********************************************************************)
(*  actionBar#insert_space ();*)
  ignore (actionBar#insert_button ~text:"Quit"
            ~icon:((GMisc.image ~stock:`QUIT ())#coerce)
            ~tooltip:"Exit Unison"
            ~callback:safeExit ());

  (*********************************************************************
    go button
   *********************************************************************)
(*  actionBar#insert_space ();*)
  grAdd grGo
    (actionBar#insert_button ~text:"Go"
       (* tooltip:"Go with displayed actions" *)
       ~icon:((GMisc.image ~stock:`EXECUTE ())#coerce)
       ~tooltip:"Perform the synchronization"
       ~callback:(fun () ->
                    getLock synchronize) ());

  (* Does not quite work: too slow, and Files.copy must be modifed to
     support an interruption without error. *)
  (*
  ignore (actionBar#insert_button ~text:"Stop"
            ~icon:((GMisc.image ~stock:`STOP ())#coerce)
            ~tooltip:"Exit Unison"
            ~callback:Abort.all ());
  *)

  (*********************************************************************
    Rescan button
   *********************************************************************)
  let loadProfile p =
    debug (fun()-> Util.msg "Loading profile %s..." p);
    Uicommon.initPrefs p displayWaitMessage getFirstRoot getSecondRoot
      termInteract;
    displayNewProfileLabel p;
    setMainWindowColumnHeaders()
  in

  let reloadProfile () =
    match !Prefs.profileName with
      None -> ()
    | Some(n) -> loadProfile n in

  let detectCmdName = "Rescan" in
  let detectCmd () =
    getLock detectUpdatesAndReconcile;
    updateDetails ();
    if Prefs.read Globals.batch then begin
      Prefs.set Globals.batch false; synchronize()
    end
  in
(*  actionBar#insert_space ();*)
  grAdd grRescan
    (actionBar#insert_button ~text:detectCmdName
       ~icon:((GMisc.image ~stock:`REFRESH ())#coerce)
       ~tooltip:"Check for updates"
       ~callback: (fun () -> reloadProfile(); detectCmd()) ());

  (*********************************************************************
    Buttons for <--, M, -->, Skip
   *********************************************************************)
  let doAction f =
    match !current with
      Some i ->
        let theSI = !theState.(i) in
        begin match theSI.whatHappened, theSI.ri.replicas with
          None, Different diff ->
            f diff;
            redisplay i;
            nextInteresting ()
        | _ ->
            ()
        end
    | None ->
        () in
  let leftAction _ =
    doAction (fun diff -> diff.direction <- Replica2ToReplica1) in
  let rightAction _ =
    doAction (fun diff -> diff.direction <- Replica1ToReplica2) in
  let questionAction _ = doAction (fun diff -> diff.direction <- Conflict) in
  let mergeAction    _ = doAction (fun diff -> diff.direction <- Merge) in

  actionBar#insert_space ();
  grAdd grAction
    (actionBar#insert_button
(*       ~icon:((GMisc.pixmap leftArrowBlack ())#coerce)*)
       ~icon:((GMisc.image ~stock:`GO_BACK ())#coerce)
       ~text:"Right to Left"
       ~tooltip:"Propagate this item from the right replica to the left one"
       ~callback:leftAction ());
(*  actionBar#insert_space ();*)
  grAdd grAction
    (actionBar#insert_button
(*       ~icon:((GMisc.pixmap mergeLogoBlack())#coerce)*)
       ~icon:((GMisc.image ~stock:`ADD ())#coerce)
       ~text:"Merge"
       ~callback:mergeAction ());
(*  actionBar#insert_space ();*)
  grAdd grAction
    (actionBar#insert_button
(*       ~icon:((GMisc.pixmap rightArrowBlack ())#coerce)*)
       ~icon:((GMisc.image ~stock:`GO_FORWARD ())#coerce)
       ~text:"Left to Right"
       ~tooltip:"Propagate this item from the left replica to the right one"
       ~callback:rightAction ());
(*  actionBar#insert_space ();*)
  grAdd grAction
    (actionBar#insert_button ~text:"Skip"
       ~icon:((GMisc.image ~stock:`NO ())#coerce)
       ~tooltip:"Skip this item"
       ~callback:questionAction ());

  (*********************************************************************
    Diff / merge buttons
   *********************************************************************)
  let diffCmd () =
    match !current with
      Some i ->
        getLock (fun () ->
          let item = !theState.(i) in
          let len =
            match item.ri.replicas with
              Problem _ ->
                Uutil.Filesize.zero
            | Different diff ->
                snd (if root1IsLocal then diff.rc2 else diff.rc1).size
          in
          item.bytesTransferred <- Uutil.Filesize.zero;
          item.bytesToTransfer <- len;
          initGlobalProgress len;
          Uicommon.showDiffs item.ri
            (fun title text -> messageBox ~title (transcode text))
            Trace.status (Uutil.File.ofLine i);
          displayGlobalProgress 0.;
          fastRedisplay i)
    | None ->
        () in

  actionBar#insert_space ();
  grAdd grDiff (actionBar#insert_button ~text:"Diff"
                  ~icon:((GMisc.image ~stock:`DIALOG_INFO ())#coerce)
                  ~tooltip:"Compare the two items at each replica"
                  ~callback:diffCmd ());

(*  actionBar#insert_space ();*)
(*
  grAdd grDiff (actionBar#insert_button ~text:"Merge"
                  ~icon:((GMisc.image ~stock:`DIALOG_QUESTION ())#coerce)
                  ~tooltip:"Merge the two items at each replica"
                  ~callback:mergeCmd ());
 *)
  (*********************************************************************
    Detail button
   *********************************************************************)
  actionBar#insert_space ();
  grAdd grDetail (actionBar#insert_button ~text:"Details"
                    ~icon:((GMisc.image ~stock:`INFO ())#coerce)
                    ~tooltip:"Show details"
                    ~callback:showDetCommand ());

  (*********************************************************************
    Keyboard commands
   *********************************************************************)
  ignore
    (mainWindow#event#connect#key_press ~callback:
       begin fun ev ->
         let key = GdkEvent.Key.keyval ev in
         if key = GdkKeysyms._Left then begin
           leftAction (); GtkSignal.stop_emit (); true
         end else if key = GdkKeysyms._Right then begin
           rightAction (); GtkSignal.stop_emit (); true
         end else
           false
       end);

  (*********************************************************************
    Action menu
   *********************************************************************)
  let (root1,root2) = Globals.roots () in
  let loc1 = root2hostname root1 in
  let loc2 = root2hostname root2 in
  let descr =
    if loc1 = loc2 then "left to right" else
    Printf.sprintf "from %s to %s" loc1 loc2 in
  let left =
    actionsMenu#add_image_item ~key:GdkKeysyms._greater ~callback:rightAction
      ~image:((GMisc.image ~stock:`GO_FORWARD ~icon_size:`MENU ())#coerce)
      ~label:("Propagate this path " ^ descr) () in
  grAdd grAction left;
  left#add_accelerator ~group:accel_group ~modi:[`SHIFT] GdkKeysyms._greater;
  left#add_accelerator ~group:accel_group GdkKeysyms._period;

  let merge =
    actionsMenu#add_image_item ~key:GdkKeysyms._m ~callback:mergeAction
      ~image:((GMisc.image ~stock:`ADD ~icon_size:`MENU ())#coerce)
      ~label:"Merge the files" () in
  grAdd grAction merge;
(* merge#add_accelerator ~group:accel_group ~modi:[`SHIFT] GdkKeysyms._m; *)

  let descl =
    if loc1 = loc2 then "right to left" else
    Printf.sprintf "from %s to %s"
      (Unicode.protect loc2) (Unicode.protect loc1) in
  let right =
    actionsMenu#add_image_item ~key:GdkKeysyms._less ~callback:leftAction
      ~image:((GMisc.image ~stock:`GO_BACK ~icon_size:`MENU ())#coerce)
      ~label:("Propagate this path " ^ descl) () in
  grAdd grAction right;
  right#add_accelerator ~group:accel_group ~modi:[`SHIFT] GdkKeysyms._less;
  right#add_accelerator ~group:accel_group ~modi:[`SHIFT] GdkKeysyms._comma;

  grAdd grAction
    (actionsMenu#add_image_item ~key:GdkKeysyms._slash ~callback:questionAction
      ~image:((GMisc.image ~stock:`NO ~icon_size:`MENU ())#coerce)
      ~label:"Do not propagate changes to this path" ());

  (* Override actions *)
  ignore (actionsMenu#add_separator ());
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.setDirection si.ri `Replica1ToReplica2 `Prefer)
            !theState;
          displayMain()))
       "Resolve all conflicts in favor of first root");
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.setDirection si.ri `Replica2ToReplica1 `Prefer)
            !theState;
          displayMain()))
       "Resolve all conflicts in favor of second root");
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.setDirection si.ri `Newer `Prefer)
            !theState;
          displayMain()))
       "Resolve all conflicts in favor of most recently modified");
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.setDirection si.ri `Older `Prefer)
            !theState;
          displayMain()))
       "Resolve all conflicts in favor of least recently modified");
  ignore (actionsMenu#add_separator ());
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.setDirection si.ri `Replica1ToReplica2 `Force)
            !theState;
          displayMain()))
       "Force all changes from first root to second");
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.setDirection si.ri `Replica2ToReplica1 `Force)
            !theState;
          displayMain()))
       "Force all changes from second root to first");
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.setDirection si.ri `Newer `Force)
            !theState;
          displayMain()))
       "Force newer files to replace older ones");
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.setDirection si.ri `Merge `Force)
            !theState;
          displayMain()))
       "Revert all paths to the merging default, if avaible");
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.setDirection si.ri `Older `Force)
            !theState;
          displayMain()))
       "Force older files to replace newer ones");
  ignore (actionsMenu#add_separator ());
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          Array.iter
            (fun si -> Recon.revertToDefaultDirection si.ri)
            !theState;
          displayMain()))
       "Revert all paths to Unison's recommendations");
  grAdd grAction
    (actionsMenu#add_item
       ~callback:(fun () -> getLock (fun () ->
          match !current with
            Some i ->
              let theSI = !theState.(i) in
              Recon.revertToDefaultDirection theSI.ri;
              redisplay i;
              nextInteresting ()
          | None ->
              ()))
       "Revert selected path to Unison's recommendations");

  (* Diff *)
  ignore (actionsMenu#add_separator ());
  grAdd grDiff (actionsMenu#add_image_item ~key:GdkKeysyms._d ~callback:diffCmd
      ~image:((GMisc.image ~stock:`DIALOG_INFO ~icon_size:`MENU ())#coerce)
      ~label:"Show diffs for selected path" ());

  (*********************************************************************
    Synchronization menu
   *********************************************************************)

  grAdd grGo
    (fileMenu#add_image_item ~key:GdkKeysyms._g
       ~image:(GMisc.image ~stock:`EXECUTE ~icon_size:`MENU () :> GObj.widget)
       ~callback:(fun () -> getLock synchronize)
       ~label:"Go" ());
  grAdd grRescan
    (fileMenu#add_image_item ~key:GdkKeysyms._r
       ~image:(GMisc.image ~stock:`REFRESH ~icon_size:`MENU () :> GObj.widget)
       ~callback:(fun () -> reloadProfile(); detectCmd())
       ~label:detectCmdName ());
  grAdd grRescan
    (fileMenu#add_item ~key:GdkKeysyms._a
       ~callback:(fun () ->
                    reloadProfile();
                    Prefs.set Globals.batch true;
                    detectCmd())
       "Detect updates and proceed (without waiting)");
  grAdd grRescan
    (fileMenu#add_item ~key:GdkKeysyms._f
       ~callback:(
         fun () ->
           let rec loop i acc =
             if i >= Array.length (!theState) then acc else
             let notok =
               (match !theState.(i).whatHappened with
                   None-> true
                 | Some(Util.Failed _, _) -> true
                 | Some(Util.Succeeded, _) -> false)
              || match !theState.(i).ri.replicas with
                   Problem _ -> true
                 | Different diff -> diff.direction = Conflict in
             if notok then loop (i+1) (i::acc)
             else loop (i+1) (acc) in
           let failedindices = loop 0 [] in
           let failedpaths =
             Safelist.map (fun i -> !theState.(i).ri.path1) failedindices in
           debug (fun()-> Util.msg "Rescaning with paths = %s\n"
                    (String.concat ", " (Safelist.map
                                           (fun p -> "'"^(Path.toString p)^"'")
                                           failedpaths)));
           Prefs.set Globals.paths failedpaths;
           Prefs.set Globals.confirmBigDeletes false;
           detectCmd();
           reloadProfile())
       "Recheck unsynchronized items");

  ignore (fileMenu#add_separator ());

  grAdd grRescan
    (fileMenu#add_image_item ~key:GdkKeysyms._p
       ~callback:(fun _ ->
          match getProfile() with
            None -> ()
          | Some(p) -> loadProfile p; detectCmd ())
       ~image:(GMisc.image ~stock:`OPEN ~icon_size:`MENU () :> GObj.widget)
       ~label:"Select a new profile from the profile dialog..." ());

  let fastProf name key =
    grAdd grRescan
      (fileMenu#add_item ~key:key
            ~callback:(fun _ ->
               if System.file_exists (Prefs.profilePathname name) then begin
                 Trace.status ("Loading profile " ^ name);
                 loadProfile name; detectCmd ()
               end else
                 Trace.status ("Profile " ^ name ^ " not found"))
            ("Select profile " ^ name)) in

  let fastKeysyms =
    [| GdkKeysyms._0; GdkKeysyms._1; GdkKeysyms._2; GdkKeysyms._3;
       GdkKeysyms._4; GdkKeysyms._5; GdkKeysyms._6; GdkKeysyms._7;
       GdkKeysyms._8; GdkKeysyms._9 |] in

  Array.iteri
    (fun i v -> match v with
      None -> ()
    | Some(profile, info) ->
        fastProf profile fastKeysyms.(i))
    profileKeymap;

  ignore (fileMenu#add_separator ());
  ignore (fileMenu#add_item
            ~callback:(fun _ -> stat_win#show ()) "Statistics");

  ignore (fileMenu#add_separator ());
  ignore (fileMenu#add_image_item
            ~key:GdkKeysyms._q ~callback:safeExit
            ~image:((GMisc.image ~stock:`QUIT ~icon_size:`MENU ())#coerce)
            ~label:"Quit" ());

  (*********************************************************************
    Expert menu
   *********************************************************************)
  if Prefs.read Uicommon.expert then begin
    let expertMenu = add_submenu ~label:"Expert" () in

    let addDebugToggle modname =
      let cm =
        expertMenu#add_check_item ~active:(Trace.enabled modname)
          ~callback:(fun b -> Trace.enable modname b)
          ("Debug '" ^ modname ^ "'") in
      cm#set_show_toggle true in

    addDebugToggle "all";
    addDebugToggle "verbose";
    addDebugToggle "update";

    ignore (expertMenu#add_separator ());
    ignore (expertMenu#add_item
              ~callback:(fun () ->
                           Printf.fprintf stderr "\nGC stats now:\n";
                           Gc.print_stat stderr;
                           Printf.fprintf stderr "\nAfter major collection:\n";
                           Gc.full_major(); Gc.print_stat stderr;
                           flush stderr)
              "Show memory/GC stats")
  end;

  (*********************************************************************
    Finish up
   *********************************************************************)
  grDisactivateAll ();

  ignore (toplevelWindow#event#connect#delete ~callback:
            (fun _ -> safeExit (); true));
  toplevelWindow#show ();
  currentWindow := Some (toplevelWindow :> GWindow.window_skel);
  detectCmd ()


(*********************************************************************
                               STARTUP
 *********************************************************************)

let start _ =
  begin try
    (* Initialize the GTK library *)
    ignore (GMain.Main.init ());

    Util.warnPrinter := Some (warnBox "Warning");

    GtkSignal.user_handler :=
      (fun exn ->
         match exn with
           Util.Transient(s) | Util.Fatal(s) -> fatalError s
         | exn -> fatalError (Uicommon.exn2string exn));

    (* Ask the Remote module to call us back at regular intervals during
       long network operations. *)
    let rec tick () =
      gtk_sync true;
      Lwt_unix.sleep 0.05 >>= tick
    in
    ignore_result (tick ());

    Uicommon.uiInit
      fatalError
      tryAgainOrQuit
      displayWaitMessage
      getProfile
      getFirstRoot
      getSecondRoot
      termInteract;

    scanProfiles();
    createToplevelWindow();

    (* Display the ui *)
    ignore (GMain.Timeout.add 500 (fun _ -> true));
              (* Hack: this allows signals such as SIGINT to be
                 handled even when Gtk is waiting for events *)
    GMain.Main.main ()
  with
    Util.Transient(s) | Util.Fatal(s) -> fatalError s
  | exn -> fatalError (Uicommon.exn2string exn)
  end

end (* module Private *)


(*********************************************************************
                            UI SELECTION
 *********************************************************************)

module Body : Uicommon.UI = struct

let start = function
    Uicommon.Text -> Uitext.Body.start Uicommon.Text
  | Uicommon.Graphic ->
      let displayAvailable =
        Util.osType = `Win32
          ||
        try System.getenv "DISPLAY" <> "" with Not_found -> false
      in
      if displayAvailable then Private.start Uicommon.Graphic
      else Uitext.Body.start Uicommon.Text

let defaultUi = Uicommon.Graphic

end (* module Body *)
