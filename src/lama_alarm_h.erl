%%%------------------------------------------------------------------------
%%% File: $Id: lama_alarm_h.erl 801 2007-04-11 20:11:18Z dkorsun $
%%%------------------------------------------------------------------------
%%% @doc This module implements a replacement for SASL's alarm_handler.
%%% It offers two features:
%%% <ul>
%%% <li>Setting and clearing alarms that are not duplicated (in contrast
%%%     to SASL's alarm_handler) and that are logged to syslog using
%%%     lama_log_handler)</li>
%%% <li>Defining map between alarms and SNMP traps, so that when
%%%     an alarm is set/cleared, it will cause an associated SNMP
%%%     trap to be sent to a configured SNMP manager.</li>
%%% </ul>
%%% This handler is fault tolegant as it is guarded by the
%%% <code>lama_guard</code> process.  In case of a handler crash the
%%% process will receive a notification sent by <code>gen_event</code>
%%% exit, and will be restarted by the parent <code>lama_sup_safe</code>
%%% supervisor defined in the <code>lama</code> module.<p/>
%%% @author   Serge Aleynikov <saleyn@gmail.com>
%%% @version  $Rev: 801 $
%%%
%%% @type varbinds() = list() | Fun
%%%           Fun = () -> list()
%%% @end
%%%------------------------------------------------------------------------
%%% $URL$
%%% Created: 03-Mar-2004 10:31PM
%%%------------------------------------------------------------------------
-module(lama_alarm_h).
-author('saleyn@gmail.com').
-id("$Id: lama_alarm_h.erl 801 2007-04-11 20:11:18Z dkorsun $").

-behaviour(gen_event).

%% External exports
-export([start_link/1, stop/0, set_alarm/1, set_alarm/2,
         clear_alarm/1, get_alarms/0,
         get_alarm_map/0, add_alarm_trap/3, delete_alarm_trap/1]).

%% Internal exports
-export([init/1,
     handle_event/2, handle_call/2, handle_info/2, code_change/3,
     terminate/2, get_def_options/0, set_alarm/3, clear_alarm/2]).

%% Debugging exports
-export([error/0]).

-include("logger.hrl").

%% Internal state record
-record(state, {alarms,      % List of active alarms
                notify_name, % SNMP NotifyName from nofify.config file
                             %   that's used as a destination for traps
                alarm_map    % Alarm -> SnmpTrap map
               }).

%% Entry containing a relationship between alarm_id and trap
-record(alarm_trap,
               {alarm_id,
                trap,
                varbinds
               }).

%%------------------------------------------------------------------------
%% @spec start_link(Options) ->
%%               ok | already_started | throw({error, Reason})
%%          Options = [ Option ]
%%          Option  = {notify_name, NotifyName::string()} |
%%                    {alarm_traps, AlarmTraps::list()}
%%          AlarmTraps = os_mon |
%%                      {AlarmID::atom(), Trap::atom(), Varbinds::varbinds()}
%%
%% @doc Installs the new alarm handler.  It should be called from
%% the lama_guard's process.<br/>
%% Options:
%% <ul>
%% <li><code>NotifyName</code> - Defines the key from the SNMP's
%%     <code>notify.config</code> configuration file that indicates
%%     the destination SNMP managers that will be receiving
%%     SNMP traps</li>
%% <li><code>AlarmTraps</code> - Defines alarm to trap mappings that
%%     should generate SNMP alarms when corresponding AlarmID's a
%%     set/cleared.  <code>os_mon</code> value adds standard alarms and
%%     traps defined in OTP-OS-MON-MIB.mib.  When adding
%%     {AlarmID, Trap, Varbinds::varbinds()} option, Trap must be known to
%%     the SNMP agent by loading some MIB file containing its definition.
%%     Varbinds contains a list of additional values that will be sent
%%     along with the trap, or a function returning such a list.
%%     Refer to SNMP agen't guide for the use of this feature</li>
%% </ul>
%% Note: Internal store of alarms is a list, and this implementation
%% is not efficient for handling a large number of distinct alarms.
%% @type alarm()    = {AlarmId::alarm_id(), Description::term()}
%% @type alarm_id() = atom() | {atom(), Data::term()}
%% @end
%%------------------------------------------------------------------------
start_link(Options) ->
    % gen_event:add_handler/2 doesn't check for duplicates
    case lists:member(?MODULE, gen_event:which_handlers(alarm_handler)) of
    true  ->
        already_started;
    false ->
        case gen_event:swap_sup_handler(alarm_handler,
               {alarm_handler, swap}, {?MODULE, Options}) of
        ok -> ok;
        {error, Reason} ->
            throw({error, {?MODULE, start_link, Reason}})
        end
    end.

%%------------------------------------------------------------------------
%% @spec stop() -> ok | {error, Reason}
%% @doc Remore alarm handler.
%% @end
%%------------------------------------------------------------------------
stop() ->
    gen_event:swap_handler(alarm_handler, {?MODULE, swap}, {alarm_handler, []}).

%%------------------------------------------------------------------------
%% @spec set_alarm(Alarm::alarm()) -> ok | {error, Reason}
%%
%% @doc Set alarm.
%% @see set_alarm/2
%% @see clear_alarm/1
%% @see check_alarm/2
%% @end
%%------------------------------------------------------------------------
set_alarm(Alarm) ->
    set_alarm(Alarm, []).

%%------------------------------------------------------------------------
%% @spec set_alarm(Alarm::alarm(), Varbinds::list()) -> ok | {error, Reason}
%%
%% @doc Set alarm.  Multiple invocations of this function with the
%% same <code>AlarmId</code> will not cause duplicate alarms to
%% to be set. Error is returned if the alarm is mapped to an SNMP trap,
%% and notification couldn't be sent (in this case the alarm will still
%% be added to the internal alarm list).  See SNMP documentation for
%% description of Varbinds.
%% @see clear_alarm/1
%% @see check_alarm/2
%% @end
%%------------------------------------------------------------------------
set_alarm(Alarm, Varbinds) ->
    gen_event:notify(alarm_handler, 
        {self(), group_leader(), {alarm,set}, Alarm, Varbinds, undefined}).

%%------------------------------------------------------------------------
%% @doc For use by the ?ALARM_SET/2 macro in logger.hrl
%% @end
%%------------------------------------------------------------------------
set_alarm(Alarm, Varbinds, {_App, _Module, _Line, _ErrClassCode} = Location) ->
    gen_event:notify(alarm_handler, 
        {self(), group_leader(), {alarm,set}, Alarm, Varbinds, Location}).
    
%%------------------------------------------------------------------------
%% @spec clear_alarm(AlarmId::alarm_id()) -> ok | {error, Reason}
%%
%% @doc Clear alarm that was previously set by set_alarm/1.
%% Error is returned if the alarm is mapped to an SNMP trap,
%% and notification couldn't be sent (in this case the alarm will still
%% be added to the internal alarm list).
%% @see set_alarm/1
%% @see check_alarm/2
%% @end
%%------------------------------------------------------------------------
clear_alarm(AlarmId) ->
    gen_event:notify(alarm_handler,
        {self(), group_leader(), {alarm,clear}, AlarmId, [], undefined}).

%%------------------------------------------------------------------------
%% @doc For use by the ?ALARM_CLEAR/1 macro in logger.hrl
%% @end
%%------------------------------------------------------------------------
clear_alarm(AlarmId, {_App, _Mod, _Line, _ErrClass} = Location) ->
    gen_event:notify(alarm_handler,
        {self(), group_leader(), {alarm,clear}, AlarmId, [], Location}).

%%------------------------------------------------------------------------
%% @spec get_alarms() -> Alarms
%%          Alarms = [ Alarm::alarm() ]
%% @doc Get currently active alarms.
%% @end
%%------------------------------------------------------------------------
get_alarms() ->
    gen_event:call(alarm_handler, ?MODULE, get_alarms).

%%------------------------------------------------------------------------
%% @spec get_alarm_map() -> AlarmMap
%%       AlarmMap = [{AlarmId::alarm_id(), Trap::atom(), Varbinds::varbinds()}]
%% @doc Get currently active alarms.
%% @end
%%------------------------------------------------------------------------
get_alarm_map() ->
    gen_event:call(alarm_handler, ?MODULE, get_alarm_map).

%%------------------------------------------------------------------------
%% @spec add_alarm_trap(AlarmID::atom(), Trap::atom(),
%%                      Varbinds::varbinds()) -> ok
%% @doc Add an alarm to trap mapping to the internal #state.alarm_map list.
%% Note: when Alarm key is a tuple of ::alarm_id() type, use the first element
%% of the tuple as the AlarmID parameter to this function.<br/>
%% `` Example:
%%       {{AlarmID, _}, _} = {{disk_almost_full, "/usr"}, "Low disk space"}
%%       add_alarm_trap(AlarmID, diskAlmostFullAlarm, []).
%% ''
%% @end
%%------------------------------------------------------------------------
add_alarm_trap(AlarmID, Trap, Varbinds) when is_atom(AlarmID) ->
    gen_event:notify(alarm_handler, {add_alarm_trap, AlarmID, Trap, Varbinds}).

%%------------------------------------------------------------------------
%% @spec delete_alarm_trap(AlarmID::atom()) -> ok
%% @doc Delete an alarm to trap mapping.
%% @end
%%------------------------------------------------------------------------
delete_alarm_trap(AlarmID) ->
    gen_event:notify(alarm_handler, {delete_alarm_trap, AlarmID}).

%%------------------------------------------------------------------------
%% This one is for test purposes to force an error in the handler in order
%% to verify its fault tolerance.
%% @hidden
%%------------------------------------------------------------------------
error() ->
    gen_event:call(alarm_handler, ?MODULE, error).

%%------------------------------------------------------------------------
%% @spec get_def_options() -> TypedOptions::typed_options()
%%          typed_options() = lama:typed_options()
%%
%% @doc Gets default module's options.
%% @end
%%------------------------------------------------------------------------
get_def_options() ->
    [{notify_name, "",       string},
     {alarm_traps, [os_mon], fun check_altr/2}].

%%%----------------------------------------------------------------
%%% Default Alarm handler
%%%----------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, State}          |
%%          Other
%% It is being called when a event is being installed to an event manager
%% using gen_event:swap_[sup_]handler/3 function
%% @private
%%----------------------------------------------------------------------
init({Options, OldAlarms}) ->
    catch
        begin
            NotifyName = lama:get_opt(notify_name, Options),
            WhichMaps  = lama:get_opt(alarm_traps, Options),
            AlarmMap   = init_alarm_map(WhichMaps),
            {ok, #state{alarms      = if not is_list(OldAlarms) -> [];
                                      true -> OldAlarms
                                      end,
                        notify_name = NotifyName,
                        alarm_map   = AlarmMap}}
        end;

%% This one is called when a event is being installed to an event manager
%% using gen_event:add_[sup_]handler/3 function
init(Options) ->
    init({Options, []}).

%% @private
handle_event({add_alarm_trap, AlarmID, Trap, Varbinds}, #state{alarm_map = Alarms} = State)->
    Pos = #alarm_trap.alarm_id,
    List = lists:keydelete(AlarmID, Pos, Alarms),
    NewAlarms = [#alarm_trap{alarm_id=AlarmID, trap=Trap, varbinds=Varbinds} | List],
    {ok, State#state{alarm_map = NewAlarms}};

handle_event({delete_alarm_trap, AlarmID}, #state{alarm_map = Alarms} = State)->
    Pos = #alarm_trap.alarm_id,
    NewAlarms = lists:keydelete(AlarmID, Pos, Alarms),
    {ok, State#state{alarm_map = NewAlarms}};

%% For compatibility with SASL trap its alarm_handler's events
handle_event({Type, Alarm}, State) when Type=:=set_alarm; Type=:= clear_alarm ->
    {Pid, GL, SetOrClear} =
        {alarm_handler, group_leader(), ?IF(Type, set_alarm, set, clear)},
    {_Reply, NewState} = do_handle_alarm({SetOrClear, Pid, GL}, Alarm, [], undefined, State),
    {ok, NewState};

% @private
% Main synchronous alarm handler
%     Location = {App, Mod, Line, ErrorClass}
handle_event({Pid, GL, {alarm,Type}, Alarm, Varbinds, Location}, State) ->
    do_handle_alarm({Type, Pid, GL}, Alarm, Varbinds, Location, State);

handle_event(_, State)->
    {ok, State}.

% @private
handle_info(_, State)             -> {ok, State}.

handle_call(get_alarms, State)    -> {ok, State#state.alarms, State};
handle_call(get_alarm_map, State) -> {ok, State#state.alarm_map, State};
handle_call(error, _State)        -> throw({error, test_error});
handle_call(_Query, State)        -> {ok, {error, bad_query}, State}.

%%----------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
% @private
%%----------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%----------------------------------------------------------------------
%% This function is called when
%% gen_event:swap_handler(EventMgr, {?MODULE, swap}, {NewModule, Args})
%% is called
%% @private
%%----------------------------------------------------------------------
terminate(swap, #state{alarms=Alarms}) -> {?MODULE, Alarms};
terminate(_Reason, _State)             -> ok.

%%%-----------------------------------------------------------------
%%% Internal functions
%%%-----------------------------------------------------------------

init_alarm_map(Options) ->
    Map1 =
        case lists:member(os_mon, Options) of
        true ->
            [   % OS_MON's alarms, see OTP-OS-MON-MIB.mib
                #alarm_trap{alarm_id = process_memory_high_watermark,
                            trap     = loadErlProcMemoryHighAlarm,
                            varbinds = []},
                #alarm_trap{alarm_id = disk_almost_full,
                            trap     = diskAlmostFullAlarm,
                            varbinds = []},
                #alarm_trap{alarm_id = system_memory_high_watermark,
                            trap     = loadSystemMemoryHighAlarm,
                            varbinds = []}
            ];
        false ->
            []
        end,
    Map1.

%%----------------------------------------------------------------------
%% do_handle_alarm functions are responsible for processing alarms.
%%----------------------------------------------------------------------

do_handle_alarm({set, Pid, GL}, {AlarmId, _} = Alarm, Varbinds, Location, #state{alarms = Alarms} = State) ->
    case lists:keysearch(AlarmId, 1, Alarms) of
    {value, _} -> {ok, State};
    false ->
        Reply = do_handle_trap(set, Alarm, State#state.notify_name, State#state.alarm_map, Varbinds),
        gen_event:notify(error_logger, {error_report, GL, {Pid, {alarm,set}, Alarm, Location, Reply}}),
        {ok, State#state{alarms = [Alarm | Alarms]}}
    end;
do_handle_alarm({clear, Pid, GL}, AlarmId, Varbinds, Location, #state{alarms = Alarms} = State) ->
    case lists:keysearch(AlarmId, 1, Alarms) of
    {value, Alarm} ->
        Reply = do_handle_trap(cleared, Alarm, State#state.notify_name, State#state.alarm_map, Varbinds),
        gen_event:notify(error_logger, {error_report, GL, {Pid, {alarm,clear}, Alarm, Location, Reply}}),
        {ok, State#state{alarms = lists:keydelete(AlarmId, 1, Alarms)}};
    false ->
        {ok, State}
    end.

%%----------------------------------------------------------------------
%% do_handle_trap/5 -> {ok, Trap, Varbinds} | no_trap | {error, Reason}
%% do_handle_trap  functions are responsible sending an SNMP traps
%% based on AlarmIDs, if a corresponding association is found in the
%% internal AlarmMap.
%%----------------------------------------------------------------------

%% Type = set | cleared
do_handle_trap(Type, {{AlarmID, Data}, Descr}, NotifyName, AlarmMap, Varbinds) ->
    do_handle_trap2(Type, AlarmID, Data, Descr, NotifyName, AlarmMap, Varbinds);

do_handle_trap(Type, {AlarmID, Descr}, NotifyName, AlarmMap, Varbinds) ->
    do_handle_trap2(Type, AlarmID, [], Descr, NotifyName, AlarmMap, Varbinds);

do_handle_trap(_Type, Alarm, _NotifyName, _AlarmMap, _Varbinds) ->
    {error, {badarg, Alarm}}.

do_handle_trap2(set, AlarmID, Data, Descr, NotifyName, AlarmMap, Varbinds0) when is_list(Varbinds0) ->
    Pos = #alarm_trap.alarm_id,
    case lists:keysearch(AlarmID, Pos, AlarmMap) of
    {value, #alarm_trap{trap = Trap, varbinds = Vals}} when is_function(Vals) ->
        Varbinds = case catch Vals() of
                   V when is_list(V) -> V;
                   _ -> []
                   end,
        do_send_trap(Trap, NotifyName, Data, Descr, Varbinds0 ++ Varbinds);
    {value, #alarm_trap{trap = Trap, varbinds = Varbinds}} when is_list(Varbinds) ->
        do_send_trap(Trap, NotifyName, Data, Descr, Varbinds0 ++ Varbinds);
    {value, #alarm_trap{trap = Trap, varbinds = Varbinds}} ->
        ?ERROR("AlarmID: ~p. Trap: ~p. Invalid Varbinds type: ~p.~n",
               [AlarmID, Trap, Varbinds]),
        {error, {badarg, Varbinds}};
    false ->
        no_trap
    end;

do_handle_trap2(cleared, AlarmID, Data, Descr, NotifyName, AlarmMap, _Varbinds) ->
    Pos = #alarm_trap.alarm_id,
    case {whereis(snmp_master_agent), lists:keysearch(AlarmID, Pos, AlarmMap)} of
    {Pid, {value, #alarm_trap{trap = Trap}}} when is_pid(Pid) ->
        {value, OID} = snmpa:name_to_oid(Trap),
        do_send_trap(lamaAlarmCleared, NotifyName, Data, Descr, [{clearedAlarmObject, OID}]);
    _ ->
        no_trap
    end.

do_send_trap(Trap, NotifyName, Data, Descr, Varbinds) ->
    Info =
        case {Data, Descr} of
        {[], []} -> [];
        {_,  []} -> [{lamaAlarmInformation, string:substr(?FMT("~p", [Data]),  1, 255)}];
        {[],  _} -> [{lamaAlarmInformation, string:substr(?FMT("~p", [Descr]), 1, 255)}];
        {_,   _} -> [{lamaAlarmInformation, string:substr(?FMT("~p. ~p", [Data, Descr]), 1, 255)}]
        end,
    case catch snmpa:send_notification(snmp_master_agent,
                  Trap, no_receiver, NotifyName, Info++Varbinds) of
    {'EXIT', _Reason} ->
        case lists:member(snmp, [App || {App, _, _} <-
                application:which_applications()]) of
        true  -> {error, cannot_send_trap};
        false -> {error, snmp_not_running}
        end;
    _ ->
        {ok, Trap, Varbinds}
    end.

%%----------------------------------------------------------------------
check_altr(_, L) when is_list(L) ->
    F = fun({AlarmID, Trap, Varbinds}) when is_atom(AlarmID),
           is_atom(Trap), is_list(Varbinds) ->
               ok;
           (Opt) when Opt == os_mon ->
               ok;
           (Other) ->
               throw({error, {invalid_option_format, Other}})
        end,
    [F(V) || V <- L],
    ok;
check_altr(_, _) -> false.


