%%%------------------------------------------------------------------------
%%% File: $Id: lama_app.erl 727 2007-03-27 22:10:43Z serge $
%%%------------------------------------------------------------------------
%%% @doc This module implements LAMA application behaviour.
%%%
%%% @type expected_type() = ExpectedType
%%%          ExpectedType = atom | {value, ValidItems::list()} |
%%%             tuple   | boolean | string |
%%%             integer | {integer, Min::integer(), Max::integer()} |
%%%             float   | {float, Min::float(), Max::float()} |
%%%             list    | {list, ValidItems::list()} | {list_of, Type} |
%%%             Fun
%%%          Type = integer | float | atom | list | tuple |
%%%                 number | string | ValidItems
%%%          Fun = (Opt, Value) -> ok |
%%%                      throw({error, {bad_config, {Key, Val}, Reason}})
%%%          ValidItems = list()
%%% @type options()       = [ Option::option() ]
%%% @type option()        = {Option::atom(), Value::term()}
%%% @type typed_options() = [ TypedOption::typed_option() ]
%%% @type typed_option()  = {Option::atom(), Value::term(), ExpType::expected_type()}
%%% @author   Serge Aleynikov <saleyn@gmail.com>
%%% @version $Rev: 727 $
%%%          $LastChangedDate: 2007-03-27 18:10:43 -0400 (Tue, 27 Mar 2007) $
%%% @end
%%%------------------------------------------------------------------------
%%% Created 20-Mar-2003
%%% $URL: http://devlinuxpro/svn/libraries/Erlang/lama/current/src/lama_app.erl $
%%%------------------------------------------------------------------------
-module(lama_app).
-author('saleyn@gmail.com').
-id("$Id: lama.erl 727 2007-03-27 22:10:43Z serge $").

-behaviour(application).

-include("logger.hrl").

%% Internal exports
-export([start/2, stop/1, init/1, verify_type/3]).

%%%-----------------------------------------------------------------
%%% application callbacks
%%%-----------------------------------------------------------------

%% Note: Options is taken from {mod, Options} option in lama.app
%% @private
start(_, Options) ->
    AlarmOpts  = lama:get_app_options(lama, Options, lama_alarm_h:get_def_options()),
    LogOpts = lama:get_app_options(lama, Options, lama_log_h:get_def_options()),
    supervisor:start_link({local, lama_sup},
                          ?MODULE, [AlarmOpts, LogOpts]).

%% @private
stop(_State) ->
    ok.

%%%-----------------------------------------------------------------
%%% supervisor callbacks
%%%-----------------------------------------------------------------
%% @private
init([AlarmOptions, LogOpts]) ->
    SafeSupervisor =
        {lama_safe_sup,
            {supervisor, start_link,
                [{local, lama_sup_safe}, ?MODULE,
                 {safe, AlarmOptions, LogOpts}]},
            permanent, infinity, supervisor, [?MODULE]},
    %% Reboot node if lama_logger or lama_alarmer or lama_snmp_trapper crashes!
    {ok, {_SupFlags = {one_for_one, 0, 1}, [SafeSupervisor]}};

init({safe, AlarmOptions, LogOpts}) ->
    LoggerH =
        {lama_guard_log,
            {lama_guard, start_link,
                [lama_guard_log, lama_log_h, LogOpts]},
            permanent, 2000, worker, dynamic},
    AlarmH =
        {lama_guard_alarm,
            {lama_guard, start_link,
                [lama_guard_alarm, lama_alarm_h, AlarmOptions]},
            permanent, 2000, worker, dynamic},
    {ok, {_SupFlags = {one_for_one, 4, 3600}, [LoggerH, AlarmH]}}.

%%%-----------------------------------------------------------------
%%% Internal functions
%%%-----------------------------------------------------------------

verify_type(_Tag, Val, atom)    when is_atom(Val) -> Val;
verify_type( Tag, Val, {Type, ValidItems}) when Type == value; Type == atom ->
    find_in_list(Tag, Val, ValidItems), Val;
verify_type(_Tag, Val, tuple)   when is_tuple(Val)  -> Val;
verify_type(_Tag, Val, integer) when is_integer(Val) -> Val;
verify_type( Tag, Val, {integer, Min, Max}) when is_integer(Val) ->
    (Val >= Min andalso Val =< Max) orelse throw_error(Tag,Val,{out_of_range,Min,Max}),
    Val;
verify_type(_Tag, Val, float)   when is_float(Val) -> Val;
verify_type( Tag, Val, {float, Min, Max})   when is_float(Val) ->
    (Val >= Min andalso Val =< Max) orelse throw_error(Tag,Val,{out_of_range,Min,Max}),
    Val;
verify_type(_Tag, Val, list)    when is_list(Val) -> Val;
verify_type(Tag,  Val, {list, ValidItems}) when is_list(Val) ->
    [find_in_list(Tag, I, ValidItems) || I <- Val], Val;
verify_type(_Tag, Val, boolean) when is_boolean(Val) -> Val;
verify_type(Tag, Val, {list_of, Type}) when is_list(Val)  ->
    F = fun(A) when Type =:= atom,    is_atom(A)    -> ok;
           (A) when Type =:= string                 -> is_string(Tag, A);
           (A) when Type =:= tuple,   is_tuple(A)   -> ok;
           (A) when Type =:= integer, is_integer(A) -> ok;
           (A) when Type =:= float,   is_float(A)   -> ok;
           (A) when Type =:= number,  is_number(A)  -> ok;
           (A) when is_list(Type)                   -> find_in_list(Tag, A, Type);
           (_) -> throw_error(Tag, Val, {list_of, Type, expected})
        end,
    [F(V) || V <- Val], Val;
verify_type( Tag, Val, Fun) when is_function(Fun, 2), not is_tuple(Fun) -> % In current Erlang release is_function({a, b},2) returns true
    Fun(Tag, Val), Val;
verify_type(Tag, Val, string) -> is_string(Tag, Val), Val;
verify_type(Tag, Val, _) ->
    throw_error(Tag, Val, unknown_param).

throw_error(Tag, Val, Reason) ->
    throw({error, {bad_config, {Tag, Val, Reason}}}).

find_in_list(Tag, Ele, List) ->
    case lists:member(Ele, List) of
    true  -> ok;
    false -> throw_error(Tag, Ele, unknown_param)
    end.

is_string(Tag, S) ->
    case io_lib:printable_list(S) of
    true  -> ok;
    false -> throw_error(Tag, S, not_a_string)
    end.
