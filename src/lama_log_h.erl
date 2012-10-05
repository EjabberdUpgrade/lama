%%%------------------------------------------------------------------------
%%% File: $Id: lama_syslog_h.erl 777 2007-04-10 19:53:38Z serge $
%%%------------------------------------------------------------------------
%%% @doc This module implements an error_logger event handler that allows
%%%      to call other log handler callbacks for logging one-line reports
%%%      and multi-line reports.
%%% @author  Serge Aleynikov <saleyn@gmail.com>
%%% @version $Rev: 777 $
%%%          $LastChangedDate: 2007-04-10 15:53:38 -0400 (Tue, 10 Apr 2007) $
%%% ``
%%% Example message as seen in the syslog file:
%%% Mar 19 21:26:44 10.231.12.2 n@spider:test[0.45.0]: [ALERT] Test msg
%%% '''
%%% @end
%%%----------------------------------------------------------------------
%%% $URL$
%%% Created: 19-Mar-2003
%%%----------------------------------------------------------------------
-module(lama_log_h).
-author('saleyn@gmail.com').
-id("$Id: lama_syslog_h.erl 777 2007-04-10 19:53:38Z serge $").

-behaviour(gen_event).

%% External exports
-export([start_link/1, % log/4,
         add_logger/3, delete_logger/2]).

%% gen_server callbacks
-export([init/1, handle_call/2, handle_event/2, handle_info/2,
         code_change/3, terminate/2]).

%% Internal and Debug exports
-export([get_def_options/0,
         which_loggers/0, which_loggers/1,
         get_state/0, log_debug_event/1, test/0, test1/0, test2/0, one_line/1, format_supervisor/1]).

-record(state, {alarm_pri,      % {AlarmSetPriority, AlarmClearedPriority}
                ignore_types,   % List of event types that need to be ignored
                                %  with no action. Default: []. Allowed values:
                                %  [error,alert,warning,notice,info,debug]
                display_types,  % List of event types that will be displayed to screen
                                %  Default: [alert,error,warning,notice,info,debug]
                logger_1_state, % One-line loggers state: [{Logger, State}]
                logger_M_state  % Multi-line loggers state: [{Logger, State}]
               }).

-include("logger.hrl").

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start_link(Options) ->
    % Note: gen_event:add_handler/2 doesn't check for duplicates
    case gen_event:swap_sup_handler(error_logger,
           {?MODULE, swap}, {?MODULE, Options}) of
    ok ->
        % Remove standard error handler. Note that it's better to do this
        % by setting {kernel, [{error_logger, silent}]}
        % gen_event:delete_handler(error_logger, error_logger_tty_h, []);
        ok;
    {error, Reason} ->
        throw({error, ?FMT("Cannot start LAMA error_logger handler: ~p", [Reason])})
    end.

%log(Priority, Format, Msg, Optional) when is_list(Msg), is_list(Optional) ->
%    gen_event:notify(error_logger,
%        {info_report, group_leader(),
%            {self(), lama_logger, {Priority, Format, Msg, Optional}}}).

%%------------------------------------------------------------------------
%% @spec (Type, Module::atom(), Options) -> ok | {error, Reason}
%%          Type    = one | multi
%%          Options = [{Opt::atom(), Value}]
%% @doc Add a new logger module to LAMA.  The module must export two
%%      functions: `init/1', `log/2' and optionally `terminate/2'.
%%      `Type' determines if `Module' is a `one'-line logger or
%%      `multi'-line logger.
%% @end
%%------------------------------------------------------------------------
add_logger(Type, Module, Options) when Type =:= one; Type =:= multi ->
    gen_event:call(error_logger, ?MODULE, {add_logger, Type, Module, Options}).

%%------------------------------------------------------------------------
%% @spec (Type, Module::atom()) -> ok
%%          Type = one | multi
%%% @doc Remore a log handler module from LAMA.
%% @end
%%------------------------------------------------------------------------
delete_logger(Type, Module) when Type =:= one; Type =:= multi ->
    gen_event:call(error_logger, ?MODULE, {delete_logger, Type, Module}).

%%------------------------------------------------------------------------
%% @spec get_state() -> state()
%% @private
%%------------------------------------------------------------------------
get_state() ->
    gen_event:call(error_logger, ?MODULE, get_state).

%%------------------------------------------------------------------------
%% @spec () -> {ok, Loggers}
%%          Loggers = [{Type, [Module::atom()]}]
%%          Type = one | multi
%% @private
%%------------------------------------------------------------------------
which_loggers() ->
    gen_event:call(error_logger, ?MODULE, which_loggers).

%%------------------------------------------------------------------------
%% @spec (Type) -> {ok, Loggers}
%%          Type = one | multi
%%          Loggers = [Module::atom()]
%% @private
%%------------------------------------------------------------------------
which_loggers(Type) when Type =:= one; Type =:= multi ->
    gen_event:call(error_logger, ?MODULE, {which_loggers, Type}).

%%------------------------------------------------------------------------
%% @spec log_debug_event(Level) -> boolean()
%% @private
%%------------------------------------------------------------------------
log_debug_event(silent) -> false;
log_debug_event(Level)  ->
    MinL = verbosity2int(lama:get_app_env(lama, debug_verbosity, lowest)),
    verbosity2int(Level) =< MinL.

verbosity2int(lowest)  -> 1;
verbosity2int(low)     -> 2;
verbosity2int(medium)  -> 3;
verbosity2int(high)    -> 4;
verbosity2int(highest) -> 5;
verbosity2int(_)       -> 6.

%%------------------------------------------------------------------------
%% @spec get_def_options() -> TypedOptions::typed_options()
%%          typed_options() = lama:typed_options()
%%
%% @doc Gets default module's options.
%% @end
%%------------------------------------------------------------------------
get_def_options() ->
    AllowedTypes = [alert,error,warning,notice,info,debug],
    LogTypes = [log|AllowedTypes],
    [{use_syslog,             false,       boolean},
     {use_console,            true,        boolean},
     {use_logfile,            false,       boolean},
     {one_line_loggers,       [lama_syslog],  {list_of, atom}},
     {multi_line_loggers,     [lama_console,lama_file], {list_of, atom}},
     {syslog_host,            "localhost", string},
     {syslog_indent,          lama,        atom},
     {syslog_facility,        user,        atom},
     {syslog_types, [alert,error,warning], {list,  LogTypes}},
     {ignore_types, [],                    {list,  LogTypes}},
     {display_types,          AllowedTypes,{list,  LogTypes}},
     {logfile_types, [alert, error, warning, log], {list, LogTypes}},
     {logfile_append_date,    true,        boolean},
     {logfile_name,           "",          string},
     {logfile_rotate_size,    0,           integer},
     {alarm_set_priority,     error,       {value, LogTypes}},
     {alarm_cleared_priority, error,       {value, LogTypes}},
     {debug_verbosity,        lowest,      {value, [silent, lowest, low, medium, high, highest]}}
    ].

%%%----------------------------------------------------------------------
%%% Callback functions from gen_server
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%%----------------------------------------------------------------------
init({Options, _Ignore}) ->
    try
        OneLiners   = lama:get_opt(one_line_loggers, Options),
        MultiLiners = lama:get_opt(multi_line_loggers, Options),
        ASP         = lama:get_opt(alarm_set_priority,     Options),
        ACP         = lama:get_opt(alarm_cleared_priority, Options),
        Ignore      = lama:get_opt(ignore_types,           Options),

        Fun = fun(M, Acc) ->
            case M:init(Options) of
            undefined -> Acc;
            State     -> [{M, State} | Acc]
            end
        end,

        Loggers1state = lists:foldl(Fun, [], OneLiners),
        LoggersMstate = lists:foldl(Fun, [], MultiLiners),

        {ok, #state{logger_1_state = Loggers1state,
                    logger_M_state = LoggersMstate,
                    alarm_pri      = {ASP, ACP},
                    ignore_types   = lama:encode_mask(Ignore)}}
    catch {error, Why} ->
        {stop, Why}
    end;
%% This one is called when a event is being installed to an event manager
%% using gen_event:add_[sup_]handler/3 function
init(Options) ->
    init({Options, undefined}).

%%----------------------------------------------------------------------
%% Func: handle_call/2
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_call({add_logger, Type, Module, Options}, #state{logger_1_state=OS, logger_M_state=MS} = State) ->
    try
        LState  = Module:init(Options),

        ?NOTICE("Added (type=~w) ~w log handler with state: ~p\n", [Type, Module, LState]),

        NewState =
            case Type of
            one when LState =/= undefined ->
                State#state{logger_1_state = OS ++ [{Module, LState}]};
            multi when LState =/= undefined ->
                State#state{logger_M_state = MS ++ [{Module, LState}]};
            _ ->
                State
            end,

        {ok, ok, NewState}
    catch {'EXIT', Why} ->
        {ok, {error, Why}, State};
    Error ->
        {ok, Error, State}
    end;

handle_call({delete_logger, Type, Module}, State) ->
    F = fun({M, S}, Acc) when M =:= Module ->
            (catch M:terminate(normal, S)),
            Acc;
        (MS, Acc) ->
            [MS | Acc]
        end,
    case Type of
    one   -> NewState = lists:fold(F, [], State#state.logger_1_state);
    multi -> NewState = lists:fold(F, [], State#state.logger_M_state)
    end,
    {ok, ok, NewState};

handle_call(which_loggers, #state{logger_1_state=OS, logger_M_state=MS} = State) ->
    {ok, {ok, [{one, [M || {M,_} <- OS]}, {multi, [M || {M,_} <- MS]}]}, State};

handle_call({which_loggers, one}, #state{logger_1_state=OS} = State) ->
    {ok, {ok, [M || {M,_} <- OS]}, State};

handle_call({which_loggers, multi}, #state{logger_M_state=MS} = State) ->
    {ok, {ok, [M || {M,_} <- MS]}, State};

handle_call(get_state, State) ->
    {ok, State, State};

handle_call(_Request, State) ->
    {ok, {error, bad_request}, State}.

%%----------------------------------------------------------------------
%% Func: handle_event/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------

%----------------------------------------------------------------------
% Events arising from using logger.hrl macros
%----------------------------------------------------------------------
handle_event({error_report, GL, {Pid, {lama,Type}, {Distr,Report}}},
             State) ->
    % Send distributed messages to other nodes, and also if the
    % Type is in [warning,error] forward it other gen_event handlers or
    % print [info,debug] messages to screen
    distribute(Distr, {error_report, GL, {Pid,{lama,Type},Report}}, State),
    {ok, State};

%----------------------------------------------------------------------
% Don't log events not belonging to this node
%----------------------------------------------------------------------
handle_event({_Type, GL, _Event}, State) when node(GL) /= node() ->
    {ok, State};

%----------------------------------------------------------------------
% lama_alarm_h support
%   Location = undefined | {App, Mod, Line, ErrClass}
%----------------------------------------------------------------------
handle_event({error_report, GL, {Pid, {alarm,Type}, {AlarmID, Detail}, Location, TrapSent}},
             #state{alarm_pri={ASP,ACP}} = State) ->
    Priority = ?IF(Type, set, ASP, ACP),

    TrapDetail =
        case TrapSent of
        {ok, Trap, Varbinds} ->
            io_lib:format("Trap {~p, ~p} sent successfully", [Trap, Varbinds]);
        no_trap -> "";
        {error, Reason} ->
            io_lib:format("Failed to send trap: ~p", [Reason])
        end,
    {Fmt, Args} =
        case io_lib:printable_list(Detail) of
        true when Detail /= [] -> {"~p - ~s~n ~s", [AlarmID, Detail, TrapDetail]};
        true                   -> {"~p~n ~s"     , [AlarmID,         TrapDetail]};
        false                  -> {"~p - ~p~n ~s", [AlarmID, Detail, TrapDetail]}
        end,

    case Location of
    undefined ->
        {App, Mod, Line, ErrClass} = {undefined, undefined, undefined, undefined};
    {App, Mod, Line, ErrClass} ->
        ok
    end,

    % Distribute event to other event handlers
    % gen_event:notify(error_logger, {error, GL, {lama, " "++Header++": "++Fmt, Args}}),
    %% We don't need to call multi-line loggers - they are invoked via the notification above
    Report = {error_report, GL, {Pid, {{alarm,Type},Priority}, {App,Mod,Line,ErrClass,Fmt,Args}}},
    distribute(true, Report, State),
    {ok, State};

%----------------------------------------------------------------------
% error_logger interface support
%----------------------------------------------------------------------
handle_event({_Type, _GL, {lama, _Rep, _Args}}, State) ->
    % These are special messages that this module generates upon
    % receiving gen_events from logger.hrl.  We want standard handlers
    % to pick them up for proper printing and file logging.  In order
    % to avoid duplicate syslog logging in this module, we just skip them.
    {ok, State};
handle_event({error, _GL, {emulator, _Format, _Args}}, State) ->
    % Ignore shell errors by user
    {ok, State};
handle_event({error, _GL, {Pid, Format, Args}}, State) ->
    process_1_loggers(State#state.logger_1_state, {Pid, now(), error, "ERROR", Format, Args}),
    {ok, State};
handle_event({emulator, GL, Chars}, State) when is_list(Chars) ->
    process_1_loggers(State#state.logger_1_state, {GL, now(), error, "ERROR-EMU", "~s", [Chars]}),
    {ok, State};
handle_event({info, _GL, {Pid, Info, _}}, State) ->
    process_1_loggers(State#state.logger_1_state, {Pid, now(), info, "INFO", "~p", [Info]}),
    {ok, State};
handle_event({error_report, _GL, {Pid, std_error, Rep}}, State) ->
    Msg = format_report(Rep),
    process_1_loggers(State#state.logger_1_state, {Pid, now(), error, "ERROR", "~s", [Msg]}),
    {ok, State};
handle_event({info_report, _GL, {Pid, std_info, Rep}}, State) ->
    Msg = format_report(Rep),
    process_1_loggers(State#state.logger_1_state, {Pid, now(), info, "INFO", "~s", [Msg]}),
    {ok, State};
handle_event({info_msg, _GL, {Pid, Format, Args}}, State) ->
    process_1_loggers(State#state.logger_1_state, {Pid, now(), info, "INFO", Format, Args}),
    {ok, State};
handle_event({warning_report,_GL, {Pid, std_warning, Rep}}, State) ->
    Msg = format_report(Rep),
    process_1_loggers(State#state.logger_1_state, {Pid, now(), warning, "WARNING", "~s", [Msg]}),
    {ok, State};
handle_event({warning_msg, _GL, {Pid, Format, Args}}, State) ->
    process_1_loggers(State#state.logger_1_state, {Pid, now(), warning, "WARNING", Format, Args}),
    {ok, State};

%----------------------------------------------------------------------
% sasl event support
%----------------------------------------------------------------------
handle_event({error_report, _GL, {_Pid, supervisor_report, _Rep}}, State) ->
    %Msg = format_supervisor(Rep),
    %process_1_loggers(State#state.logger_1_state, {Pid, now(), error, "ERROR-SUPERV", "~s", [Msg]}),
    {ok, State};
handle_event({error_report, _GL, {Pid, crash_report, Rep}}, State) ->
    % crash report
    case format_crash(Rep) of
    false -> ok;
    Msg   -> process_1_loggers(State#state.logger_1_state, {Pid, now(), error, "ERROR", "~s", [Msg]})
    end,
    {ok, State};
%% Don't send progress reports to syslog
handle_event({info_report,  _GL, {_Pid, progress, _Rep}}, State) ->
    {ok, State};

handle_event(_Msg, State) ->
    {ok, State}.

%%-----------------------------------------------------------------------
%% Func: handle_info/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%-----------------------------------------------------------------------
handle_info({emulator, GL, Chars}, State) when node(GL) == node(); GL == noproc ->
    process_1_loggers(State#state.logger_1_state, {GL, now(), error, "ERROR-EMU", "~s", [Chars]}),
    {ok, State};

handle_info(_Info, State) ->
    {ok, State}.

%%-----------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% @private
%%-----------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%-----------------------------------------------------------------------
%% This function is called when
%% gen_event:swap_handler(EventMgr, {?MODULE, swap}, {NewModule, Args})
%% is called, or the handler is being terminated for some other reason.
%% @private
%%-----------------------------------------------------------------------
terminate(Reason, #state{logger_1_state=Loggers1state, logger_M_state=LoggersMstate}) ->
    [(catch M:terminate(Reason, State)) || {M, State} <- Loggers1state],
    [(catch M:terminate(Reason, State)) || {M, State} <- LoggersMstate],
    ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

%% Report = {Pid, NowTime, Priority, Header, Msg}
process_1_loggers([], _Report) -> ok;
process_1_loggers(Loggers, {Pid, Time, Pri, Hdr, Fmt, Msg}) ->
    process_1_loggers(Loggers, {Pid, Time, Pri, Hdr, safe_format(Fmt, Msg)});
process_1_loggers(Loggers, {Pid, Time, Pri, Hdr, Msg}) ->
    %% Normalize report to a single line
    process_1_loggers2(Loggers, {Pid, Time, Pri, Hdr, one_line(Msg)}).

%% Report = {Pid, Time, Priority, Header, Msg}
process_1_loggers2([{Logger, State} | Tail], Report) ->
    Logger:log(Report, State),
    process_1_loggers2(Tail, Report);
process_1_loggers2([], _) ->
    ok.

%% Report = {Pid, NowTime, Priority, Header, Message::io_list()}
process_M_loggers([{Logger, State} | Tail], Report) ->
    Logger:log(Report, State),
    process_M_loggers(Tail, Report);
process_M_loggers([], _) ->
    ok.

%% Distribute logger.hrl reports to lama_syslog_h handlers at other nodes
%% and also if this is a warning/error/alert error, then
%% dispatch this report to standard event handlers or otherwise
%% print it to screen.
distribute(false = _Distr, Report, State) ->
    distribute2(Report, State);
distribute(true, Report, State) ->
    % Make sure the other nodes don't drop this message
    DistRep = setelement(2, Report, lama),
    _       = [gen_event:notify({error_logger, N}, DistRep) || N <- nodes()],
    distribute2(Report, State).

%% Send
distribute2({_, _GL, {Pid, {Type, Priority}, {App,Mod,Line,Info,Fmt,Args} = _Report}},
            #state{ignore_types=Ignore, logger_1_state=OS, logger_M_state=MS}) ->
    Time = now(),
    case lama:priority_to_int(Priority) band Ignore of
    0 ->
        AppInfo = get_app_info(App,Mod,Line,Info),
        Header1 = get_1_header(Type, Priority),
        HeaderM = get_M_header(Time, Priority, Header1, Pid, AppInfo),
        Message = safe_format(Fmt, Args),
        process_1_loggers(OS, {Pid, Time, Priority, Header1, Message}),
        process_M_loggers(MS, {Pid, Time, Priority, HeaderM, Message});
    _ ->
        ok
    end;
distribute2(_,_) -> ok.

get_1_header({alarm,Type}, _) -> get_alarm_header(Type);
get_1_header(_Type, Priority) -> string:to_upper(atom_to_list(Priority)).

% @spec get_app_info(App,Mod,Line,OamInfo) -> {Fmt, Args}
get_app_info(undefined,undefined,undefined,_Err) ->
    "";
get_app_info(undefined,Mod,Line,undefined) ->
    io_lib:format("(~w:~w)", [Mod,Line]);
get_app_info(undefined,Mod,Line,{ErrClass,ErrCode}) when is_atom(ErrClass) ->
    io_lib:format("<~s:~w> (~w:~w)", [atom_to_list(ErrClass),ErrCode,Mod,Line]);
get_app_info(App,Mod,Line,undefined) ->
    io_lib:format("(~w/~w:~w)", [App,Mod,Line]);
get_app_info(App,Mod,Line,{ErrClass,ErrCode}) when is_atom(ErrClass) ->
    io_lib:format("<~s:~w> (~w/~w:~w)", [atom_to_list(ErrClass),ErrCode,App,Mod,Line]).

get_M_header(Time, Priority, Header1, Pid, AppInfo) ->
    Node = node(Pid),
    Nd = ?IF(node(), Node, [""], lama:format_pid(Pid)),
    case Priority of
    Priority when Priority =:= info; Priority =:= debug ->
        [lama:timestamp(Time,timestamp), $ , Nd, AppInfo, $ ];
    _ ->
        [io_lib:format("\n=~s REPORT==== ~s ~s===\n ",
            [Header1,lama:timestamp(Time, header),Nd]), AppInfo, "\n "]
    end.

get_alarm_header(set)   -> "ALARM SET";
get_alarm_header(clear) -> "ALARM CLEARED".

format_supervisor(Rep) ->
    Sup  = lama:get_opt(supervisor,   Rep, ""),
    Cont = lama:get_opt(errorContext, Rep, ""),
    Why  = lama:get_opt(reason,       Rep, ""),
    List = lama:get_opt(offender,     Rep, ""),
    Pid  = lama:get_opt(pid,  List, undefined),
    Name = lama:get_opt(name, List, undefined),
    MFA  = lama:get_opt(mfa,  List, undefined),
    io_lib:format("~s. Supervisor: ~p, Context: ~p, "
                  "Offender: [Pid=~p, Name=~p, MFA=~p]",
                  [to_string(Why), Sup, Cont, Pid, Name, MFA]).

format_crash([OwnRep, _LinksRep]) ->
    Pid  = lama:get_opt(pid,             OwnRep, undefined),
    Name = lama:get_opt(registered_name, OwnRep, undefined),
    Why  = lama:get_opt(error_info,      OwnRep, undefined),
    case string_p(Why) of
    true  -> io_lib:format("~s. Pid: ~p, Name: ~p", [to_string(Why), Pid, Name]);
    false -> false
    end;
format_crash(Rep) ->
    case string_p(Rep) of
    true  -> proc_lib:format(Rep);
    false -> false
    end.

format_report(Rep) when is_list(Rep) ->
    case string_p(Rep) of
    true -> io_lib:format("~s~n",[Rep]);
    _    -> format_rep(Rep)
    end;
format_report(Rep) ->
    io_lib:format("~p~n",[Rep]).

format_rep([{Tag,Data}|Rep]) ->
    io_lib:format("~s: ~1000p. ",[proper_case(Tag),Data]) ++ format_rep(Rep);
format_rep([Other|Rep]) ->
    io_lib:format("~p. ",[Other]) ++ format_rep(Rep);
format_rep(_) ->
    [].

to_string(L) ->
    case string_p(L) of
    true -> L;
    _    -> io_lib:format("~p\n", [L])
    end.

proper_case(Tag) when is_atom(Tag) ->
    proper_case2(atom_to_list(Tag));
proper_case(Tag) ->
    io_lib:format("~p", [Tag]).
proper_case2([C|Rest]) when C >= $a, C =< $z ->
    [C-($a-$A) | Rest];
proper_case2(Other) ->
    Other.

string_p([]) ->
    false;
string_p(Term) ->
    string_p1(Term).

string_p1([H|T]) when is_integer(H), H >= $\s, H < 255 ->
    string_p1(T);
string_p1([$\n|T]) -> string_p1(T);
string_p1([$\r|T]) -> string_p1(T);
string_p1([$\t|T]) -> string_p1(T);
string_p1([$\v|T]) -> string_p1(T);
string_p1([$\b|T]) -> string_p1(T);
string_p1([$\f|T]) -> string_p1(T);
string_p1([$\e|T]) -> string_p1(T);
string_p1([H|T]) when is_list(H) ->
    case string_p1(H) of
    true -> string_p1(T);
    _    -> false
    end;
string_p1([]) -> true;
string_p1(_) ->  false.

one_line([$ ,$\n|Rest])             -> one_line([$ |Rest]);
one_line([$ |Rest])                 -> [$ | one_line(compact_spaces(Rest))];
one_line([$\n,$ |Rest])             -> one_line([$ |Rest]);
one_line([$\n])                     -> [];
one_line([$\n   |Rest])             -> one_line(Rest);
one_line([$\\,$n|Rest])             -> % Avoid cases when a "\\n" string slips in.
                                       one_line([$ |Rest]);
one_line([$\\,$"|Rest])             -> % Avoid cases when a "\"" string slips in.
                                       one_line([$"|Rest]);
one_line([$\r   |Rest])             -> one_line(Rest);
one_line([$\t   |Rest])             -> one_line([$ |Rest]);
one_line([])                        -> [];
one_line([L|Rest]) when is_list(L)  -> [one_line(L) | one_line(Rest)];
one_line([Char  |Rest])             -> [Char|one_line(Rest)].

compact_spaces([$ |T]) -> [$ | compact_spaces(string:strip(T, left, $ ))];
compact_spaces([C|T])  -> [C | compact_spaces(T)];
compact_spaces([])     -> [].

safe_format(Fmt, Args) ->
    try          io_lib:format(Fmt, Args)
    catch _:_ -> io_lib:format("~p: ~p", [Fmt, Args])
    end.

%%----------------------------------------------------------------------

test() ->
    application:start(lama),
    % test alarms
    lama_alarm_h:set_alarm  ({test, "Test1"}),
    lama_alarm_h:clear_alarm(test),
    ?ALARM_SET({{disk_full, "/usr"}, "Test2"}, []),
    ?ALARM_CLEAR({disk_full, "/usr"}),
    %
    error_logger:error_report(test30),
    error_logger:error_report(type30, test31),
    error_logger:error_msg("test32~n"),
    error_logger:error_msg("test33: ~w~n", [good]),
    %
    error_logger:info_report(test50),
    error_logger:info_report(type50, test51),
    error_logger:info_msg("test52~n"),
    error_logger:info_msg("test53: ~w~n", [good]),
    %
    error_logger:warning_report(test70),
    error_logger:warning_report(type70, test71),
    error_logger:warning_msg("test72~n"),
    error_logger:warning_msg("test73: ~w~n", [good]),
    %
    ?ALERT  ("Logger alert: ~p~n",       [test100]),
    ?ERROR  ("Logger error: ~p~n",       [test101]),
    ?WARNING("Logger warning: ~p~n",     [test102]),
    ?WARNING("Logger warning: ~p~n",     [test103]),
    ?INFO   ("Logger info: ~p~n",        [test104]),
    application:set_env(lama, verbosity, low),
    ?DEBUG  (high, "Logger debug: ~p~n", [test105]),
    application:set_env(lama, verbosity, high),
    ?DEBUG  (high, "Logger debug: ~p~n", [test106]),
    ?INFO   ("Logger info: ~p~n",        [test107]),
    ?NOTICE ("Logger info: ~p~n",        [test108]),
    %
    ?OAM_ERROR('ClassA', 10, "Logger OAM error: ~p~n", [test109]),
    ?OAM_ALERT('ClassB', 11, "Logger OAM error: ~p~n", [test110]),
    ok.

test1() ->
    ?ERROR  ("Logger error: ~p~n",       [test201]).

test2() ->
    ?ALARM_SET({{disk_full, "/usr"}, "Test2"}, []),
    io:format("Active alarms: ~p\n", [lama_alarm_h:get_alarms()]),
    ?ALARM_CLEAR({disk_full, "/usr"}).
