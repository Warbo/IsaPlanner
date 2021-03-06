(* -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- *)
(*  Title:      ./interface/interface.ML
    Author:     Lucas Dixon, Moa Johansson,
                University of Edinburgh
                l.dixon@inf.ed.ac.uk
*)
(* -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- *)
(*  DESCRIPTION:

    User/Debug tools for Tracing IsaPlanner proof planning

*)
(* -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- *)

structure PPInterface =
struct

(* for printing traces during planning *)
val debug_nodes_flag = Unsynchronized.ref true;

val trace_isaplanner = Unsynchronized.ref false;

(* number of nodes *)
val nds_count = Unsynchronized.ref 0;

(* for debugging, think bad exceptions *)
val last_rst = Unsynchronized.ref (NONE : RState.T option);
fun get_last_rst () = the (!last_rst);
fun debug_unfolder unfolder st = (last_rst := SOME st;
                                  (if (!debug_nodes_flag) andalso (!nds_count) mod 10 = 0 then
                                     writeln ("\nnodes: " ^ (string_of_int (!nds_count)))
                                   else ());
                                  unfolder st);

exception EXPLORE_EXP of string;

(* checking that there are no subgoals in the proof plan *)
val no_subgoals = RstPP.solved_all_chk;
(* checking that there is nothing more to do in the proof planning attempt *)
val no_continue = is_none o RState.get_rtechn;

(* function applied once for each state: collects some stats and checks if
there is anything more to do in proof planning. *)
fun no_continue_endchk rst =
    let
      val _ = (nds_count := (!nds_count) + 1)
      val _ = (if (!debug_nodes_flag) andalso (!nds_count) mod 100 = 0 then
           writeln ("\nnodes: " ^ (string_of_int (!nds_count)))
         else ())
      val ignore = (last_rst := SOME rst)
    in no_continue rst end;


(* depth first search with no_subgoals or no_continue_endchk as end
condition, and rstate unfolding using reasoning state as the expansion
function *)
val depth_fs = GSearch.depth_fs no_continue_endchk (debug_unfolder RState.unfold);

(* depth first search with no_subgoals or no_continue_endchk as end
condition, and rstate unfolding using reasoning state as the expansion
function *)
val depth_fs_debug = GSearch.depth_fs no_continue_endchk (debug_unfolder RState.unfold);

(* breadth first search with no_subgoals or no_continue_endchk as end
condition, and rstate unfolding using reasoning state as the expansion
function *)
val breadth_fs = GSearch.breadth_fs no_continue_endchk (debug_unfolder RState.unfold);

(* checks if st1 is equal or more abstract in its hierarchical description. *)
fun is_le_level st1 st2 =
    (HTraceCInfo.current_depth_of_rst st1)
    >= (HTraceCInfo.current_depth_of_rst st2)
    andalso RState.get_id st1 <> RState.get_id st2;

(* a function to go until an equivalent level of abstraction is reached *)
fun step_fun st =
    let fun gf nst = (is_le_level st nst)
    in
      (GSearch.depth_fs gf (debug_unfolder RState.unfold)) st
    end;

(* main interactive explore function *)

(* pretty printing constants *)
val p_space = Pretty.chunks (Library.replicate 10 (Pretty.str ""));
val p_line =
    Pretty.str "----------------------------------------------------------------------------";

(* pretty printing stuff... *)
fun p_id_of_rst rst =
    Pretty.enclose
      "(" ")" [Pretty.str "id: ",
               Pretty.str ((string_of_int o RState.get_id) rst)];

fun p_choice_of_rst (rst, i) =
    Pretty.chunks
      ([Pretty.block
          ([Pretty.enclose "[" "]" [Pretty.str (string_of_int i)]]
           @ [Pretty.str " ", DescripCInfo.pretty_rst rst])]
       @ (if no_continue rst then [Pretty.str " * FINAL_STATE *"] else [])
       @ (if no_subgoals rst then [Pretty.str " * NO_SUBGOALS! *"] else []));

fun p_choices rs =
    (Pretty.chunks o Pretty.breaks o rev o snd)
      (List.foldr (fn (rst, (i,L)) =>
                      (i + 1, p_choice_of_rst (rst,i) :: L))
                  (1,[]) (rev rs));

fun p_commands rst =
    Pretty.chunks
    [Pretty.block
       ([Pretty.str "Commands: ",
         Pretty.str "[x] eXit",
         Pretty.str "  [b] Back"] @
         (* Pretty.str "  [s] Steps", *)
         (* Pretty.str "  [c] goto Choice point ", *)
         (if not(no_continue rst) then
            [Pretty.str "  [g] Go: Depth First Search"] else [])),
     Pretty.block
       [Pretty.str "View:     ",
        Pretty.str "  [v] view PPlan",
        Pretty.str "  [t] view HTrace"
       ]
    ];

(* "   [u] User" ^ "   [i] info" ^
        Pretty.str "[u] sUbgoals",
        Pretty.str "  [o] open Goals",
(if (is_some (RState.get_prev h)) then "   [u] up" else "") ^ *)

fun p_last_choice choices =
    (case choices of
       (NONE, l) => Pretty.block []
     | (SOME p, l) => Pretty.chunks
                        [Pretty.enclose
                           "(" ")" [Pretty.str "Previous choice: ",
                                    Pretty.str (string_of_int p)],
                         Pretty.str ""]);

fun print_pplan rst =
    ((Pretty.writeln o Pretty.chunks)
       [p_space,
        p_line,
        Pretty.str ("  Full Proof Plan:"),
        p_line,
        Prf.pretty (RState.get_pplan rst),
        p_line,
        Pretty.brk 1,
        Pretty.str "Press the return or enter key to return to proof planning."];
     TextIO.inputLine(TextIO.stdIn));

fun print_htrace rst =
    ((Pretty.writeln o Pretty.chunks)
       [p_space,
        p_line,
        Pretty.str ("  Full Hierarchical Trace:"),
        p_line,
        HTraceCInfo.pretty_rst rst,
        p_line,
        Pretty.brk 1,
        Pretty.str "Press the return or enter key to return to proof planning."];
     TextIO.inputLine(TextIO.stdIn));

(* Print the current goal names focused on in the reasoning state *)
fun print_cur_gnames rst =
     Pretty.block
     ((case RState.get_goalnames rst
        of [] => []
         | l =>
           [Pretty.block
              [Pretty.str "  on goals:",
               Pretty.list "{" "}" (map Prf.pretty_gname l),
               Pretty.str " "]])
      @ (case RState.get_resultnames rst
          of [] => []
           | l =>
             [Pretty.block
                [Pretty.str "  on facts:",
                 Pretty.list "{" "}" (map Prf.pretty_gname l),
                 Pretty.str " "]]));

(* pretty a rst, hitrace, pplan, cur gnames *)
fun pretty_rst rst=
    let
      val l = (HTraceCInfo.current_depth_of_rst rst)
      val pp = (RState.get_pplan rst)
    in
      Pretty.chunks
        [
         Pretty.str ("HiProof [level " ^ (string_of_int l) ^ "]: "),
         HTraceCInfo.pretty_cmp_rst rst,
         Pretty.brk 1,
         Pretty.str "Partial proof plan: ",
         Pretty.indent 2 (PPlan.pretty pp),
         print_cur_gnames rst
        ]
    end;
val print_rst = Pretty.writeln o pretty_rst;


exception NOT_A_DIGIT of string;
fun int_of_string s =
    case Int.fromString s
     of NONE => raise NOT_A_DIGIT s
      | SOME i => i;

(* function to interactively explore a reasoning state. go_func is an
function argument to do some automated search. *)
fun explore go_func ist =
    let
      fun rst_order_cmp (st1,st2) =
          Library.int_ord (RState.get_id st1, RState.get_id st2)

      (* reasoning state, choices available and graph of searched
         space, note that the graph allows us to avoid
         duplicate evaluation. *)
      fun expl_menu printQ (rst, choices, T) =
          let
            val _ = (last_rst := SOME rst)
            val (T2,unsortedcldrn) = SearchTree.get_children T rst
            fun redisplay () = expl_menu true (rst, choices, T2)
            fun repromt () = expl_menu false (rst, choices, T2)
            val cldrn = (sort rst_order_cmp unsortedcldrn)
            fun display () =
                (Pretty.writeln o Pretty.chunks)
                  [p_space,
                   p_line,
                   Pretty.block [Pretty.str "State ",
                                 p_id_of_rst rst, Pretty.str ":"],
                   Pretty.brk 1,
                   pretty_rst rst,
                   Pretty.brk 1,
                   p_line,
                   p_commands rst,
                   p_last_choice choices,
                   p_choices cldrn,
                   p_line]
            val _ = (if printQ then display() else ())
            val _ = TextIO.print "PP> "
            val sopt = TextIO.inputLine(TextIO.stdIn)
            val s = (case sopt of NONE => "" | SOME s => s)
            val slist = raw_explode s
          in
            if s = "\n" then (display(); repromt())
            else if s = "x\n" then rst
            (* else if s = "c\n" then
              (display(); writeln "Not implemented yet!"; repromt()) *)
            else if s = "b\n" then
              expl_menu true ((SearchTree.get_parent T2 rst),
                         (case  choices of (_, []) => (NONE, [])
                                        | (_, (h :: t)) => (SOME h, t))
                        , T2)
               handle SearchTree.searchtree_exp s =>
                      (writeln s; repromt())
            else if s = "v\n" then
              (print_pplan rst; display(); repromt())
            else if s = "t\n" then
              (print_htrace rst; display(); repromt())
            else if not(no_continue rst) andalso s = "g\n" then
              let
                val rst' = RState.new_id rst
                val new_go_states =
                    map (fn rst => DescripCInfo.set_pretty_rst
                                     (Pretty.block [Pretty.str "= GO => Final state: ",
                                                    p_id_of_rst rst]) rst)
                        (Seq.list_of (go_func rst'))
                val tmprst = rst' |> (RState.update_rtechn
                                        (fn NONE => NONE |
                                            SOME r =>
                                            SOME (fn _ => Seq.of_list new_go_states)))
                                  |> (DescripCInfo.set_pretty_rst
                                        (Pretty.block [Pretty.str "= GO = (id ",
                                                       p_id_of_rst rst,
                                                       Pretty.str")"]))
              in
                expl_menu true (tmprst, choices,
                                (SearchTree.add_as_children_of_rst
                                   T2 rst [tmprst]))
              end


             else if (length slist) > 1 andalso (hd slist = "s") then
              let val i = (int_of_string (implode (tl slist))) in
                if i > 0 andalso i <= length cldrn then
                  let
                    fun step_naming_f from to =
                        (DescripCInfo.prepend_str_rst
                           ("(Step from state " ^
                            ((string_of_int o RState.get_id) from) ^
                            ") => ") to)

                    val from = (Library.nth cldrn (i - 1))

                    val new_step_states =
                        map (step_naming_f from)
                            (Seq.list_of (step_fun from))
                  in
                    expl_menu true (rst, choices,
                                    (SearchTree.add_as_children_of_rst
                                       T2 rst new_step_states))
                  end
                else
                  raise EXPLORE_EXP (string_of_int i)
              end
              handle EXPLORE_EXP s =>
                     (display(); writeln s; repromt())
                   | NOT_A_DIGIT s =>
                     (display(); writeln s; repromt())
                   | Subscript =>
                     (display(); writeln "No such choice."; repromt())
            else
              let val i = (int_of_string s) in
                if i > 0 andalso i <= length cldrn then
                  expl_menu true ((Library.nth cldrn (i - 1)),
                                  (NONE, i::(#2 choices)), T2)
                else
                  raise EXPLORE_EXP (string_of_int i)
              end
              handle EXPLORE_EXP s =>
                     (display();
                      writeln ("ERROR - No such choice: " ^ s);
                      repromt())
                   | NOT_A_DIGIT s =>
                     (display();
                      writeln ("ERROR - No such option: " ^ s);
                      repromt())
                   | Subscript =>
                     (display();
                      writeln ("ERROR in explore: Subscript. " ^
                               "\n Did you type in a non-existant choice or am I going mad???");
                      repromt())
          end
    in
      expl_menu true (ist, (NONE, []), (SearchTree.init_rst ist))
    end;


(*----------------------------------------------------------------------*)
fun p_new_state_of_rst rst =
    Pretty.chunks
      ([Pretty.block
          [
           Pretty.indent 1 (DescripCInfo.pretty_rst rst)]]
       @ (if no_subgoals rst then [Pretty.str " * NO_SUBGOALS! *"] else []));

fun p_new_states rsts =
    (Pretty.chunks o Pretty.breaks o rev)
      (List.foldr (fn (rst, L) =>
                      (p_new_state_of_rst rst) :: L)
                  [] (rev rsts));

fun p_agenda agenda =
    (* Display the best three states of the agenda *)
    (*if ((List.length agenda) >= 5) then
       p_choices (List.take (agenda, 5))
    else
*) p_choices agenda;

(*Creates a list-representation of the stacked-search agenda *)
fun mk_agenda [] = []
  | mk_agenda (strat::t) =
    let
      fun build_agenda NONE = []
        | build_agenda (SOME(strat, rst')) =
          rst' :: (build_agenda (MSearch.pop_state strat))
    in
      build_agenda (MSearch.pop_state strat)
    end;

fun explore_stacked sstrat ist =
    let
      fun rst_order_cmp (st1,st2) =
          Library.int_ord (RState.get_id st1, RState.get_id st2)

      (* reasoning state, choices available and graph of searched
         space, note that the graph allows us to avoid
         duplicate evaluation. *)
      fun expl_menu printQ (rst, choices, (T,sstack)) =
          let
            val ((T2, new_sstack), unsortedcldrn) = SearchTree.get_children_stacked (T,sstack) rst
            fun redisplay () = expl_menu true (rst, choices, (T2, new_sstack))
            fun repromt () = expl_menu false (rst, choices, (T2,new_sstack))
            val cldrn = (sort rst_order_cmp unsortedcldrn)
            val agenda = mk_agenda new_sstack
            val strat_nm = if(null new_sstack) then "Empty"
                           else (#name (MSearch.staticd_of (hd new_sstack)))
            fun display () =
                (Pretty.writeln o Pretty.chunks)
                  [p_space,
                   p_line,
                   Pretty.block [Pretty.str "State ",
                                 p_id_of_rst rst, Pretty.str ":"],
                   Pretty.brk 1,
                   pretty_rst rst,
                   p_line,
                   p_commands rst,
                   p_last_choice choices,
                   Pretty.str "New states: ",
                   p_new_states cldrn,
                   Pretty.brk 1,
                   Pretty.block [Pretty.str "Agenda: ",
                                 Pretty.str strat_nm],
                   p_agenda agenda,
                   p_line]
            val _ = (if printQ then display() else ())
            val _ = TextIO.print "PP> "
            val sopt = TextIO.inputLine(TextIO.stdIn)
            val s = (case sopt of NONE => "" | SOME s => s)
            val slist = raw_explode s
          in
            if s = "x\n" then rst
            (* else if s = "c\n" then
              (display(); writeln "Not implemented yet!"; repromt()) *)
            else if s = "b\n" then
              expl_menu true ((SearchTree.get_parent T2 rst),
                         (case choices of (_, []) => (NONE, [])
                                        | (_, (h :: t)) => (SOME h, t))
                        , (T2,new_sstack)) (* Fix this, seems to have to put state back in agenda*)
               handle SearchTree.searchtree_exp s =>
                      (writeln s; repromt())
             else if s = "v\n" then
               (print_pplan rst; display(); repromt())
             else if s = "t\n" then
               (print_htrace rst; display(); repromt())
             else if not(no_continue rst) andalso s = "g\n" then
               let
                 val rst' = RState.new_id rst
                 val (go_strat,end_strat) = if (null sstack) then
                                              (MSearch.depthfs(), [MSearch.depthfs()]) (*default*)
                                else
                                  if(null (tl sstack)) then (hd sstack, [MSearch.depthfs()] )
                                    else (hd sstack,tl sstack)
                 val new_go_states =
                       map (fn rst => DescripCInfo.set_pretty_rst
                                        (Pretty.block [Pretty.str "= GO => Final state: ",
                                                       p_id_of_rst rst]) rst)
                           (Seq.list_of (RState.search go_strat rst'))
                 val tmprst = rst' |> (RState.update_rtechn
                                       (fn NONE => NONE |
                                           SOME r =>
                                           SOME (fn _ => Seq.of_list new_go_states)))
                                 |> (DescripCInfo.set_pretty_rst
                                       (Pretty.block [Pretty.str "= GO = (id ",
                                                      p_id_of_rst rst,
                                                      Pretty.str")"]))
               in
                 expl_menu true (tmprst, choices,
                                 ((SearchTree.add_as_children_of_rst
                                    T2 rst [tmprst]),end_strat))
               end

             else
               let val i = (int_of_string s) in
                 if i > 0 andalso i <= length agenda then
                   expl_menu true ((Library.nth agenda (i - 1)),
                                   (NONE, i::(#2 choices)), (T2, new_sstack))
                 else
                   raise EXPLORE_EXP (string_of_int i)
               end
               handle EXPLORE_EXP s =>
                      (display();
                       writeln ("ERROR - No such choice: " ^ s);
                       repromt())
                    | NOT_A_DIGIT s =>
                      (display();
                       writeln ("ERROR - No such option: " ^ s);
                       repromt())
                    | Subscript =>
                      (display();
                       writeln ("ERROR in explore: Subscript. " ^
                               "\n Did you type in a non-existant choice or am I going mad???");
                       repromt())
           end
    in
      expl_menu true (ist, (NONE, []), ((SearchTree.init_rst ist), [sstrat]))
    end;

(*------------------------------------------------------------------*)
(* interactively explore/trace proof planning from a given reasoning
   state. *)
(* fun ipp_rst rst =
    Print_Mode.setmp [] (fn () => explore depth_fs_debug rst) ();
*)
(* Using stacked search *)
(*
fun ipp_rst_stacked rst =
    Print_Mode.setmp [] (fn () => explore_stacked (MSearch.depthfs()) rst) ();
*)

(*-------------------- Set up a new reasoning state -------------*)
(* start a new proof planning attempt given a theory, name and string
   to make the goal term from *)
fun init_rst_of_terms ctxt goals =
      ([],PPlan.init ctxt)
        |> fold (fn t => fn (gnames,pp) =>
                 let val (gname,pp') = PPlan.conj_term_at_top ("g1",t) pp
                 in (gname::gnames,pp') end)
                goals
        |> (fn (goalstrs, pp) =>
               RState.set_goalnames goalstrs (RState.init_from_pp pp));

fun init_rst_of_strings ctxt goalstrs =
      ([],PPlan.init ctxt)
        |> fold (fn s => fn (gnames,pp) =>
                 let val (gname,pp') = PPlan.conj_string_at_top ("g1",s) pp
                 in (gname::gnames,pp') end)
                goalstrs
        |> (fn (goalstrs, pp) =>
               RState.set_goalnames goalstrs (RState.init_from_pp pp));

(* interactive tracing of proof planning. *)

(* Note: having string interfaces is handy as strings get parsed in
the theory of the proof plans. This is useful when experimenting with
theories which are not the top-level isabelle one, and hence
antiquotations will be in the wrong theory. *)
(*
fun ipp_of_strings ctxt r goals =
    (init_rst_of_strings ctxt goals)
      |> RState.set_rtechn (SOME r)
      |> ipp_rst;

fun ipp_of_terms ctxt r goals =
    (init_rst_of_terms ctxt goals)
      |> RState.set_rtechn (SOME r)
      |> ipp_rst;

(* stacked search *)
fun stacked_ipp_of_terms ctxt r goals =
    (init_rst_of_terms ctxt goals)
      |> RState.set_rtechn (SOME r)
      |> ipp_rst_stacked;
*)

end;
