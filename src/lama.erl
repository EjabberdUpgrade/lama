%%%------------------------------------------------------------------------
%%% File: $Id: lama.erl 727 2007-03-27 22:10:43Z serge $
%%%------------------------------------------------------------------------
%%% @doc This module implements LAMA - Log and Alarm Management Applicaiton.
%%% This module provides interface functions for .<p/>
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
%%% $URL: http://devlinuxpro/svn/libraries/Erlang/lama/current/src/lama.erl $
%%%------------------------------------------------------------------------
-module(lama).
-author('saleyn@gmail.com').
-id("$Id: lama.erl 727 2007-03-27 22:10:43Z serge $").

-include("logger.hrl").

%% External exports
-export([start/0, stop/0]).

%% Usability functions
-export([set_alarm/1, clear_alarm/1, get_alarms/0,
         check_alarm/2, add_alarm_trap/3,
         which_loggers/0, which_loggers/1,
         verify_config/1, verify_config/2,
         get_app_env/3, get_app_env/4,
         get_app_opt/3, get_app_opt/4,
         get_app_options/3, get_app_options2/3,
         get_opt/2, get_opt/3, os_path/1, filename/2,
         create_release_file/2, create_release_file/3
         ]).

%% Internal exports
-export([get_app/0,
         priority_to_int/1, encode_mask/1, format_pid/1,
         timestamp/2]).

-import(lama_utils, [i2l/2, month/1]).

-include_lib("sasl/src/systools.hrl").

%%------------------------------------------------------------------------
%% @spec start() -> ok | {error, Reason}
%% @doc Start LAMA application.  This is a shortcut for
%%      application:start/1.
%% @see application:start/1
%% @end
%%------------------------------------------------------------------------
start() ->
    application:start(lama).

%%------------------------------------------------------------------------
%% @spec stop() -> ok | {error, Reason}
%% @doc Stop LAMA application.  This is a shortcut for
%%      application:stop/1.
%% @see application:stop/1
%% @end
%%------------------------------------------------------------------------
stop() ->
    application:stop(lama).

%%----------------------------------------------------------------------
%% Exported miscelaneous functions
%%----------------------------------------------------------------------

%%------------------------------------------------------------------------
%% @spec set_alarm(Alarm::alarm()) -> ok
%%          alarm() = lama_alarm_h:alarm()
%%
%% @doc Set alarm. This function
%%      is equivalent to {@link lama_alarm_h:set_alarm/1}.
%% @see lama_alarm_h:set_alarm/1
%% @see check_alarm/2
%% @end
%%------------------------------------------------------------------------
set_alarm(Alarm) ->
    lama_alarm_h:set_alarm(Alarm).

%%------------------------------------------------------------------------
%% @spec clear_alarm(AlarmId::alarm_id()) -> ok
%%          alarm_id() = lama_alarm_h:alarm_id()
%%
%% @doc Clear alarm that was previously set by set_alarm/1. This function
%%      is equivalent to {@link lama_alarm_h:clear_alarm/1}.
%% @see lama_alarm_h:clear_alarm/1
%% @see check_alarm/2
%% @end
%%------------------------------------------------------------------------
clear_alarm(AlarmId) ->
    lama_alarm_h:clear_alarm(AlarmId).

%%------------------------------------------------------------------------
%% @spec check_alarm(Fun::function(), Alarm::alarm()) -> ok
%%          Fun      = () -> boolean() | {true, Varbinds}
%%          Varbinds = list()
%%          alarm()  = lama_alarm_h:alarm()
%% @doc Based on the return value of Fun set or clear an Alarm.
%% @end
%%------------------------------------------------------------------------
check_alarm(F, {AlarmID,_} = Alarm) ->
    case F() of
    false            -> lama_alarm_h:clear_alarm(AlarmID);
    true             -> lama_alarm_h:set_alarm(Alarm);
    {true, Varbinds} -> lama_alarm_h:set_alarm(Alarm, Varbinds)
    end.

%%------------------------------------------------------------------------
%% @spec get_alarms() -> Alarms
%%          Alarms = [ Alarm::alarm() ]
%% @doc Get currently active alarms.
%% @end
%%------------------------------------------------------------------------
get_alarms() ->
    lama_alarm_h:get_alarms().

%%------------------------------------------------------------------------
%% @spec add_alarm_trap(AlarmID::atom(), Trap::atom(),
%%                      Varbinds::list()) -> ok
%% @doc Add an alarm to trap mapping to the internal #state.alarm_map list.
%% Same as {@link lama_alarm_h:add_alarm_trap/3}.
%% @see lama_alarm_h:add_alarm_trap/3
%% @end
%%------------------------------------------------------------------------
add_alarm_trap(AlarmID, Trap, Varbinds) when is_atom(AlarmID) ->
    lama_alarm_h:add_alarm_trap(AlarmID, Trap, Varbinds).

%%------------------------------------------------------------------------
%% @spec get_app_env(App::atom(), Key::atom(), Default::term()) ->
%%              Value::term()
%%
%% @doc Fetch a value of the application's environment variable ``Key''.
%%      Use ``Default'' if that value is not set.
%% @end
%%------------------------------------------------------------------------
get_app_env(App, Key, Default) ->
    case application:get_env(App, Key) of
    {ok, Val} -> Val;
    _         -> Default
    end.

%%------------------------------------------------------------------------
%% @spec get_app_opt(App::atom(), Key::atom(), Default::term()) ->
%%                Option::option()
%%
%% @doc Same as get_app_env/3, but returns an Option tuple {Key, Value}
%%      rather than just a Value.
%% @end
%%------------------------------------------------------------------------
get_app_opt(App, Key, Default) ->
    {Key, get_app_env(App, Key, Default)}.

%%------------------------------------------------------------------------
%% @spec get_app_env(App::atom(), Key::atom(), Default::term(),
%%                   ExpectedType::expected_type()) -> Value::term()
%% @doc Fetch a value of the application's environment variable ``Key''.
%%      Use ``Default'' if that value is not set.  Perform validation of
%%      value type given ExpectedType.
%% @see get_app_env/5
%% @end
%%------------------------------------------------------------------------
get_app_env(App, Key, Default, ExpectedType) ->
    Value = get_app_env(App, Key, Default),
    lama_app:verify_type(Key, Value, ExpectedType).

%%------------------------------------------------------------------------
%% @spec get_app_opt(App::atom(), Key::atom(), Default::term(),
%%                   ExpectedType::expected_type()) -> Option::option()
%%
%% @doc Same as get_app_env/4 but returns a tuple {Key, Value} rather than
%%      a Value.
%% @see get_app_env/4
%% @see get_opt/2
%% @see get_opt/3
%% @end
%%------------------------------------------------------------------------
get_app_opt(App, Key, Default, ExpectedType) ->
    {Key, get_app_env(App, Key, Default, ExpectedType)}.

%%------------------------------------------------------------------------
%% @spec get_app_options(App::atom(), DefOptions::options(),
%%            TypedOptions::typed_options()) -> Options::options()
%%
%% @doc Look up TypedOptions in the environment. If not found use defaults
%%      in the DefOptions list, and if not found there, use the default
%%      value from a TypedOption's tuple: {_Key, DefaultValue, _Type}.
%% ```
%% Example:
%%    start_application(StartArgs) ->
%%        get_app_options(test, StartArgs, [{file, "bar", string}]),
%%        ... .
%%
%%    start_application([])              ->   [{file, "bar"}]
%%    start_application([{file, "foo"}]) ->   [{file, "foo"}]
%%
%%    If application's environment had {file, "zzz"}, than this tuple
%%    would've been returned instead.
%% '''
%% @see get_app_env/4
%% @end
%%------------------------------------------------------------------------
get_app_options(App, Defaults, TypedOptions) ->
    GetVal = fun(K, D, T) ->
                 V = get_opt(K, Defaults, D),
                 lama_app:verify_type(K, V, T)
             end,
    [get_app_opt(App, Key, GetVal(Key, Def, ExpectedType)) ||
        {Key, Def, ExpectedType} <- TypedOptions].

%%------------------------------------------------------------------------
%% @spec get_app_options2(App::atom(), Overrides::options(),
%%            TypedOptions::typed_options()) -> Options::options()
%%
%% @doc Same as get_app_options/3, but will override environment options
%%      with values in the ``Overrides'' list, instead of using them as
%%      defaults.
%% @end
%%------------------------------------------------------------------------
get_app_options2(App, Overrides, TypedOptions) ->
    GetVal = fun({Opt, Val}, T) ->
                 V = get_opt(Opt, Overrides, Val),
                 {Opt, lama_app:verify_type(Opt, V, T)}
             end,
    [GetVal(get_app_opt(App, Key, Def), ExpType) ||
        {Key, Def, ExpType} <- TypedOptions].

%%------------------------------------------------------------------------
%% @spec get_opt(Opt::atom(), Options) -> term() | throw({error, Reason})
%%       Options = [{Option::atom(), Value::term()}]
%%
%% @doc Fetch the Option's value from the ``Options'' list
%% @see get_app_env/4
%% @see get_app_env/5
%% @see get_opt/3
%% @end
%%------------------------------------------------------------------------
get_opt(Opt, Options) ->
    case lists:keysearch(Opt, 1, Options) of
    {value, {_, V}} -> V;
    false           -> throw({error, {undefined_option, Opt}})
    end.

%%------------------------------------------------------------------------
%% @spec get_opt(Opt::atom(), Options, Default::term()) -> term()
%%       Options = [{Option::atom(), Value::term()}]
%%
%% @doc Same as get_opt/2, but instead of throwing an error, it returns
%%      a ``Default'' value if the ``Opt'' is not in the ``Options'' list.
%% @see get_app_env/4
%% @see get_app_env/5
%% @see get_opt/2
%% @end
%%------------------------------------------------------------------------
get_opt(Opt, Options, Default) ->
    proplists:get_value(Opt, Options, Default).

%%------------------------------------------------------------------------
%% @spec () -> {ok, Loggers}
%%          Loggers = [{Type, [Module::atom()]}]
%%          Type = one | multi
%% @doc Return a list of registered loggers.
%% @end
%%------------------------------------------------------------------------
which_loggers() ->
    gen_event:call(error_logger, lama_log_h, which_loggers).

%%------------------------------------------------------------------------
%% @spec (Type) -> {ok, Loggers}
%%          Type = one | multi
%%          Loggers = [Module::atom()]
%% @doc Return a list of registered loggers.
%% @end
%%------------------------------------------------------------------------
which_loggers(Type) when Type =:= one; Type =:= multi ->
    gen_event:call(error_logger, lama_log_h, {which_loggers, Type}).

%%------------------------------------------------------------------------
%% @spec verify_config(App::atom(), TypedOptions) -> ok | throw({error, Reason})
%%           TypedOptions = typed_options()
%%
%% @doc Fetch selected options from the application's environment and
%%      perform type verification.
%% @see get_app_env/4
%% @end
%%------------------------------------------------------------------------
verify_config(App, Options) ->
    [get_app_opt(App, Opt, Def, Type) || {Opt, Def, Type} <- Options],
    ok.

%%------------------------------------------------------------------------
%% @spec verify_config(TypedOptions::typed_options()) ->
%%           Options::options() | throw({error, Reason})
%%
%% @doc For each ``Option'' in the ``Options'' list
%%      perform type verification.
%% @end
%%------------------------------------------------------------------------
verify_config(Options) ->
    F = fun(Op,V,T) -> {Op, lama_app:verify_type(Op,V,T)} end,
    [F(Opt, Value, Type) || {Opt, Value, Type} <- Options].

%% This function is used by the logger.hrl macros
%% @private
get_app() ->
    case application:get_application() of
    {ok, App} -> App;
    undefined -> undefined
    end.

%%------------------------------------------------------------------------
%% @spec (OsPath) -> Path::string()
%%         OsPath = string() | binary()
%% @doc Perform replacement of environment variable values in the OsPath.
%% ```
%%    Example:
%%       lama:os_path("~/${HOME}/myapp") -> "/home/user//home/user/myapp"
%% '''
%% @see os:getenv/1
%% @end
%%------------------------------------------------------------------------
os_path(OsPath) ->
    [_, Path] = env_subst(OsPath),
    Path.

env_subst(Bin) when is_binary(Bin) ->
    [VarList, NewText] = env_subst(binary_to_list(Bin)),
    [VarList, list_to_binary(NewText)];
env_subst(Text) ->
    env_subst(Text,
        "(\\$\\$)|(~[^/$]*)|(\\${[A-Za-z][A-Za-z_0-9]*})|(\\$[A-Za-z][A-Za-z_0-9]*)",
        fun(Var) -> env_var(Var) end).

env_subst(Text, Pattern, ValFunc) ->
    [Vars, TextList, Last] =
    case re:run(Text, Pattern, [{capture, all}]) of
    {match, Matches} ->
        lists:foldl(fun
        ({Start, Length}, [Dict, List, Prev]) when Start >= 0 ->
            Pos = Start+1,
            Match = string:substr(Text, Pos, Length),
            case ValFunc(Match) of
            {Key, Val} ->
                case orddict:is_key(Key, Dict) of
                true  -> NewDict = Dict;
                false -> NewDict = orddict:append(Key, Val, Dict)
                end;
            Val ->
                NewDict = Dict
            end,
            NewList = [Val, string:substr(Text, Prev, Pos - Prev) | List],
            NewPrev = Pos + Length,
            [NewDict, NewList, NewPrev];
        (_, Acc) -> Acc
        end, [orddict:new(), [], 1], Matches);
    Error ->
        throw(Error)
    end,
    VarList = [{K, V} || {K, [V|_]} <- orddict:to_list(Vars)],
    NewText = lists:concat(lists:reverse([string:substr(Text, Last) | TextList])),
    [VarList, NewText].

env_var("$$")           -> "$";
env_var("~" = Key)      -> {Key, get_var("HOME")};
env_var([$~ | User])    -> {"~", filename:join(filename:dirname(get_var("HOME")), User)};
env_var([$$, ${ | Env]) -> Key = string:strip(Env, right, $}), {Key, get_var(Key)};
env_var([$$ | Key])     -> {Key, get_var(Key)};
env_var(Other)          -> Other.

get_var(Name) ->
    case os:getenv(Name) of
    false -> "";
    Value -> Value
    end.

%%-------------------------------------------------------------------
%% @doc Convert a priority value to integer
%% @private
%%-------------------------------------------------------------------
priority_to_int(log    ) -> ?LAMA_LOG;
priority_to_int(alert  ) -> ?LAMA_ALERT;
priority_to_int(error  ) -> ?LAMA_ERROR;
priority_to_int(warning) -> ?LAMA_WARNING;
priority_to_int(info   ) -> ?LAMA_INFO;
priority_to_int(notice ) -> ?LAMA_NOTICE;
priority_to_int(debug  ) -> ?LAMA_DEBUG;
priority_to_int(_      ) -> ?LAMA_TEST.

%%-------------------------------------------------------------------
%% @doc Encode a list of priorities into a bitmask
%% @private
%%-------------------------------------------------------------------
encode_mask(Opts)               -> encode_mask(Opts, 0).
encode_mask([Opt | Tail], Mask) -> encode_mask(Tail, Mask bor priority_to_int(Opt));
encode_mask([],           Mask) -> Mask.


%%-------------------------------------------------------------------
%% @spec create_release_file(TemplateRelFile, OutRelFile) -> ok
%%          TemplateRelFile = filename()
%%          OutRelFile      = filename()
%% @doc Create a release file given a release template file.
%% @see create_release_file/3
%% @end
%%-------------------------------------------------------------------
create_release_file(TemplateRelFile, OutRelFile) ->
    create_release_file(TemplateRelFile, OutRelFile, undefined).

%%-------------------------------------------------------------------
%% @spec create_release_file(TemplateRelFile, OutRelFile, Vsn) -> ok
%%          TemplateRelFile = filename()
%%          OutRelFile      = filename()
%%          Vsn             = string()
%% @doc Create a release file given a release template file.  The
%%      release template file should have the same structure as the
%%      release file.  This function will ensure that latest
%%      application versions are included in the release.  It will
%%      also ensure that the latest erts version is specified in
%%      the release file.  Note that both arguments may contain the
%%      ".rel" extension, however the actual TemplateRelFile must
%%      have a ".rel" extension.  The TemplateRelFile doesn't need
%%      to contain application version numbers - an empty string will
%%      do: <code>{kernel, ""}</code>.  This function will populate
%%      the version number with current version of the application.
%%      ``Vsn'' is the version number associated with the generated
%%      release file.  If it is ``undefined'', the version from the
%%      ``TemplateRelFile'' will be used.
%% ```
%% Example:
%%   lama:create_release_file(".drp.template.rel", "./ebin/drp.rel").
%% '''
%% @end
%%-------------------------------------------------------------------
create_release_file(TemplateRelFile, OutRelFile, Vsn) ->
    Rel = get_release(TemplateRelFile),
    OutFileName = filename:join(filename:dirname(OutRelFile),
                                filename:basename(OutRelFile,".rel")++".rel"),
    case file:open(OutFileName, [write]) of
    {ok, FD} ->
        io:format(FD, "%%%~n"
                      "%%% This file is automatically generated from ~s~n"
                      "%%%~n~n", [TemplateRelFile]),
        io:format(FD, "{release, {~p, ~p}, {erts, ~p},~n  [~n~s  ]~n}.~n",
                  [Rel#release.name,
                   case Vsn of
                   undefined -> Rel#release.vsn;
                   _         -> Vsn
                   end,
                   Rel#release.erts_vsn,
                   format_list(Rel#release.applications)]),
        file:close(FD);
    {error, Reason} ->
        throw({error, file:format_error(Reason)})
    end.

get_release(Filename) ->
    File = filename:basename(Filename, ".rel"),
    Dir  = [filename:dirname(Filename) | code:get_path()],
    {ok, Release} = systools_make:read_release(File, Dir),
    case systools_make:get_release(File, Dir) of
    {ok, Rel, _, _} ->
        Rel#release{erts_vsn = erlang:system_info(version)};
    {error,systools_make,List} ->
        NewList =
            lists:foldl(fun({error_reading,{Mod,{not_found,AppFile}}}, {Ok, Err}) ->
                            {Ok, [{not_found, {Mod, AppFile}} | Err]};
                        ({error_reading,{Mod,{no_valid_version,
                                {{"should be",_}, {"found file", _, Vsn}}}}}, {Ok, Err}) ->
                            {[{Mod, Vsn} | Ok], Err}
                        end, {[],[]}, List),
        case NewList of
        {ModVsn, []} ->
            substitute_versions(Release, ModVsn);
        {_, ErrMod} ->
            throw({error, ErrMod})
        end
    end.

substitute_versions(Release, [])     -> Release;
substitute_versions(Release, [{Mod, Vsn} | Tail]) ->
    Apps = Release#release.applications,
    NewApps =
        case lists:keysearch(Mod, 1, Apps) of
        {value, {Mod, _Vsn, Type}} ->
            lists:keyreplace(Mod, 1, Apps, {Mod, Vsn, Type});
        false ->
            Apps
        end,
    substitute_versions(Release#release{applications = NewApps,
                                        erts_vsn     = erlang:system_info(version)}, Tail).

format_list(A) ->
    {LN, LV} =
        lists:foldl(fun({N,V,_}, {L1, L2}) ->
                        {erlang:max(L1, length(atom_to_list(N))),
                         erlang:max(L2, length(V))}
                    end, {0,0}, A),
    format_list(A, [], {LN, LV}).
format_list([], [$\n, $, | Acc], _) ->
    lists:reverse([$\n | Acc]);
format_list([{App,Vsn,permanent} | Tail], Acc, {LN, _LA} = Len) ->
    Str = lists:flatten(io_lib:format("    {~-*w, ~s},~n", [LN, App, [$"]++Vsn++[$"]])),
    format_list(Tail, lists:reverse(Str) ++ Acc, Len);
format_list([{App,Vsn,Type} | Tail], Acc, {LN, LA} = Len) ->
    Str = lists:flatten(io_lib:format("    {~-*w, ~-*s, ~p},~n", [LN, App, LA+2, [$"]++Vsn++[$"], Type])),
    format_list(Tail, lists:reverse(Str) ++ Acc, Len).

format_pid(Pid) ->
    [L] = io_lib:format("~w", [Pid]),
    case Pid of
    Pid when is_pid(Pid), node(Pid) =:= nonode@nohost ->        % Pid is given in the form: <X.Y.Z>
        {ok, Host} = inet:gethostname(),
        Hostname = string:sub_word(Host, 1, $.),
        Hostname ++ ":" ++ os:getpid() ++ ":" ++ format_pid2(L);
    Pid when is_pid(Pid) ->        % Pid is given in the form: <X.Y.Z>
        format_host_node(node(Pid), L);
    Pid when is_atom(Pid) ->       % Pid is given in the form: 'registered_name'
        case whereis(Pid) of
        undefined -> format_host_node(node(), L);
        PidNum    -> format_host_node(node(PidNum), L)
        end;
    _ ->                           % What else?
        format_host_node(node(), L)
    end.
format_pid2([$< | T]) ->
    [$. | Tail] = lists:dropwhile(fun(C) -> C /= $. end, T),
    format_pid2(Tail);
format_pid2([C,  $>]) -> [C];
format_pid2([C  | T]) -> [C | format_pid2(T)];
format_pid2([])       -> [].

format_host_node(Node, L) ->
    [Nodename, Host | _] = string:tokens(atom_to_list(Node), "@"),
    Host ++ ":" ++ os:getpid() ++ ":" ++ Nodename ++ ":" ++ format_pid2(L).

%%-------------------------------------------------------------------------
%% @spec (Filename::string(), Date) -> string()
%%          Date = date() | date | undefined
%% @doc Create a filename by (optionally) appending ".YYYYMMDD" to
%%      `Filename'.  The date suffix is appended only if Date is passed
%%      as `date()' or `date'.
%% @end
%%-------------------------------------------------------------------------
filename(Filename, {Y,M,D}) ->
    BaseName = os_path(Filename),
    lists:flatten([BaseName, $., i2l(Y), i2l(M,2), i2l(D,2)]);
filename(Filename, date) ->
    filename(Filename, date());
filename(Filename, _) ->
    os_path(Filename).

%%-------------------------------------------------------------------
%% @doc Return a formatted timestamp
%% @private
%%-------------------------------------------------------------------
timestamp(NowTime, Type) ->
    {{YYYY,MM,DD}, {Hour,Min,Sec}} = calendar:now_to_local_time(NowTime),
    case Type of
    log       -> [month(MM), $ , i2l(DD,2), $ , i2l(Hour,2), $:, i2l(Min,2), $:, i2l(Sec,2)];
    header    -> [i2l(DD,2),$-,month(MM),$-,i2l(YYYY), "::", i2l(Hour,2), $:, i2l(Min,2), $:, i2l(Sec,2)];
    timestamp -> [i2l(Hour,2), $:, i2l(Min,2), $:, i2l(Sec,2), $., i2l(element(2, NowTime))]
    end.

%%%-----------------------------------------------------------------
%%% Internal functions
%%%-----------------------------------------------------------------

i2l(I) -> integer_to_list(I).
