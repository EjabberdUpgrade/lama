%%%------------------------------------------------------------------------
%%% File: $Id: tracer.erl 774 2007-04-09 17:27:44Z dkarga $
%%%------------------------------------------------------------------------
%%% @author Serge Aleynikov <saleyn@gmail.com>
%%% @doc This module implements tracing support for function calls.  It is
%%% similar to dbg:c/3, however it can return the trace as its result.
%%% @version $Rev: 774 $
%%% $LastChangedDate: 2007-04-09 13:27:44 -0400 (Mon, 09 Apr 2007) $
%%% @end
%%% $URL$
%%%------------------------------------------------------------------------
-module(tracer).
-author('saleyn@gmail.com').
-id("$Id: tracer.erl 774 2007-04-09 17:27:44Z dkarga $").

% Debugging facility
-export([
    t/3, t/4, t/5, t/8,
    tp/3, tp/4, tp/5,
    tf/3, tf/4, tf/5,
    match_trace/1, match_mtrace/1,
    print_trace/1, print_mtrace/1
]).

-include("logger.hrl").

%% @spec tp(M, F, Args) -> Result::term()
%% @doc Trace a function call and print trace result of all functions
%%      in the M module to the console.
%% @end
%%
tp(M, F, Args) ->
    tp(M, F, Args, [M], call).

%% @spec tp(M::atom(), F::atom(), Args::list(), MFs) -> Result::term()
%%          MFs = [MF]
%%          MF  = M::atom() | {M::atom(), F::atom()}
%% @doc Same as tp/5 with ``Flags=call''.
%%      In addition to {M,F} the trace will include modules/functions 
%%      listed in the MFs list.
%% @end
%%
tp(M, F, Args, MFs) ->
    tp(M, F, Args, MFs, call).

%% @spec tp(M, F, Args, MFs, FlagList) -> Result::term()
%%          FlagList = [ Flag::atom() ]
%%          MFs = [MF]
%%          MF  = M::atom() | {M::atom(), F::atom()}
%% @doc Trace a function call and print trace result to the console.
%%      ``MFs'' can contain ``{M, F}'' pairs or just ``M'' module names
%%      that need to be traced.
%%      See {@link //kernel/erlang:trace/3} for description of Flags.
%% @end
%%
tp(M, F, Args, MFs, Flags) ->
    {R,T} = t(M, F, Args, MFs, Flags),
    print_trace(T),
    R.

%% @spec tf(M, F, Args) -> TraceList::term()
%% @doc Trace a function call and return trace result.
%% @end
%%
tf(M, F, Args) ->
    tf(M, F, Args, [M], call).

%% @spec tf(M, F, Args, Flags) -> TraceList::term()
%% @doc Trace a function call and return trace result.
%%      See {@link //kernel/erlang:trace/3} for description of Flags.
%% @end
%%
tf(M, F, Args, MFs) ->
    {_,T} = t(M, F, Args, MFs, call),
    format_trace(T, []).

%% @spec tf(M::atom(), F::atom(), Args::list(), MFs, Flags) -> TraceList::term()
%%          MFs = [MF]
%%          MF  = M::atom() | {M::atom(), F::atom()}
%% @doc Trace a function call and return trace result.
%%      In addition to {M,F} the trace will include modules/functions 
%%      listed in the MFs list.
%%      See {@link //kernel/erlang:trace/3} for description of Flags.
%% @end
%%
tf(M, F, Args, MFs, Flags) ->
    {_,T} = t(M, F, Args, MFs, Flags),
    format_trace(T, []).

%% @spec t(M::atom(), F::atom(), Args::list()) -> {Result::term(), Trace::list()}
%% @doc Same as t/5 with MFs=[M] and Flags='call'.
%% @end
%%
t(M, F, Args) ->
    t(M, F, Args, [M], call).

%% @spec t(M::atom(), F::atom(), Args::list(), MFs::list()) -> 
%%          {Result::term(), Trace::list()}
%% @doc Same as t/5 with Flags='call'.
%% @end
%%
t(M, F, Args, MFs) ->
    t(M, F, Args, MFs, call).

%% @spec t(M::atom(), F::atom(), Args::list(), MFs, Flags::list()) ->
%%            {Result::term(), Trace}
%%          MFs   = [MF]
%%          MF    = M::atom() | {M::atom(), F::atom()}
%%          Trace = list() | Error
%%          Error = atom()
%% @doc Call M:F function with Args arguments, and return a tuple
%% {Result, Trace} containing call trace of functions in module M.
%% @end
%%

%t(M, F, Args, Flags) ->
    % Set up a tracer
%    Fun = fun(Msg,A) ->
%              T=[Msg|A], put(trace, T), T
%          end,
%    dbg:tracer(process, {Fun, []}),
%    dbg:p(self(), Flags),
%    dbg:tpl(M, [{'_',[],[{return_trace}]}]),

    % Call the function
%    Res = apply(M, F, Args),

    % Retrieve trace
%    {ok, Tracer} = dbg:get_tracer(),

%    {dictionary, List} = process_info(Tracer, dictionary),
%    dbg:stop_clear(),
%    T = proplists:get_value(trace, List),
%    {Res, match_trace(T)}.

t(M, F, Args, MFs, Flags)
  when is_atom(F), is_atom(F), is_list(Args), is_list(MFs), 
       (is_atom(Flags) orelse is_list(Flags)) ->
    t(M, F, Args, MFs, self(), Flags, local,
    fun(Trace) -> match_trace(Trace) end).

t(M, F, Args, MFs, Items, Flags, Nodes, MatchFunc)
  when is_atom(F), is_atom(F), is_list(Args), is_list(MFs), 
       (is_atom(Flags) orelse is_list(Flags)) ->

    % Verify args
    lists:foreach(fun({Mod,Fun}) when is_atom(Mod), is_atom(Fun) -> ok;
                     (Mod)       when is_atom(Mod) -> ok;
                     (Other) -> erlang:error({badarg, {tracer, Other}})
                  end, MFs),
    % Set up a local tracer
    dbg:tracer(process, {fun({drop, trace_data, Pid}, A) -> Pid ! {trace_data, A}, A;
                            (Msg,A) -> [Msg | A] 
                         end, []}),

    % start remote tracer(s) on alive nodes
    TracedNodes = case Nodes of
    [_|_] ->
        LocalNode = node(),
        lists:foldl(fun
        (Node, Acc) when is_atom(Node), Node /= LocalNode ->
            case dbg:n(Node) of
            {ok, Node} ->
                % io:format("node ~p added~n", [Node]),
                [Node | Acc];
            cant_add_local_node ->
                Acc;
            {error, {nodedown, _}} ->
                Acc; % ignore nodes which are down
            Error ->
                ?NOTICE("Tracer received error calling dbg:n(~w): ~p~n", [Node, Error]),
                exit({tracer_failed, {dbg, n, Node}, Error})
            end;
        (_, Acc) ->
            Acc
        end, [], Nodes);
    _ ->
        []
    end,

    dbg:p(Items, Flags),

    TraceMatch = [{'_',[],[{return_trace}]}],
    lists:foreach(
        fun ({Mod, Fun}) -> dbg:tpl(Mod, Fun, TraceMatch);
            (Mod)        -> dbg:tpl(Mod, TraceMatch)
        end, MFs),
    
    % Add current M:F to the trace list
    case lists:member(M, MFs) of
    true  -> ok;
    false -> dbg:tpl(M, F, TraceMatch)
    end,
        
    % Call the function
    Res = (catch apply(M, F, Args)),

    dbg:ctpl(), % clear

    % clear remote nodes from the list of traced nodes
    [dbg:cn(Node) || Node <- TracedNodes],
        
    % Retrieve trace
    case dbg:get_tracer() of
    {ok, Tracer} ->
        Tracer ! {drop, trace_data, self()},
        
        receive
        {trace_data, Trace} ->
            ok
        after 5000 ->
            Trace = timeout
        end,
        dbg:stop_clear();
    _ ->
        Trace = no_tracer
    end,
    
    {Res, MatchFunc(Trace)}.

match_trace(Ret) when is_atom(Ret) ->
    Ret;
match_trace(Trace) ->
    match_trace(Trace, [], [], 0).
match_trace([], [], Acc, _Indent) ->
    Acc;
match_trace([{trace,_,return_from,{M,F,A},R},
             {trace,_,return_from,{_,_,_},R}=Next | Rest], Stack, Acc, Indent) ->
    % Don't show same result multiple times
    match_trace([Next|Rest], [{{M,F,A}, skip} | Stack], Acc, Indent+1);
match_trace([{trace,_,return_from,{M,F,A},R}|Rest], Stack, Acc, Indent) ->
    match_trace(Rest, [{{M,F,A}, {ok,R}} | Stack], Acc, Indent+1);
match_trace([{trace,_,call,{M,F,Args}} | Rest],
            [{{M,F,A}, R} | StackTail], Acc, Indent) when length(Args) == A ->
    T = {Indent-1, {M,F,Args}, R},
    match_trace(Rest, StackTail, [T | Acc], Indent-1);
% This is a special case when due to an exception there was no 'return_from' 
% clause matching 'call'
match_trace([{trace,_,call,{M,F,Args}} | Rest], Stack, Acc, Indent) ->
    R = ?IF(Acc, [{_, _, E} | _] when E =:= exception; E =:= skip, skip, exception),
    T = {Indent, {M,F,Args}, R},
    match_trace(Rest, Stack, [T | Acc], Indent);
match_trace([H | _Tail], Stack, Acc, Indent) ->
    S = ?FMT("Unknown trace format: ~p", [H]),
    io:format("~w:match_trace -> ~s~nStack: ~p~nAcc: ~p~nIndent: ~w~n",
              [?MODULE, S, Stack, Acc, Indent]),
    throw({error, S}).


-define(DICT, dict).
% -define(DICT, orddict).

match_mtrace(Ret) when is_atom(Ret) ->
    Ret;
match_mtrace(Trace) ->
    match_mtrace(Trace, ?DICT:new()).

match_mtrace([], Dict) ->
    ?DICT:fold(fun
    (Pid, {[], Trace, _Indent}, Acc) ->
        [{Pid, Trace} | Acc];
    (Pid, {_Stack, Trace, _Indent}, Acc) ->
        % FIXME - should we crash if stack not empty?
        io:format("Stack not empty for pid ~p~n", [Pid]),
        [{Pid, Trace} | Acc];
    (Pid, Other, Acc) ->
        % FIXME
        io:format("Unknown data for pid ~p:~n~p~n", [Pid, Other]),
        Acc
    end, [], Dict);

match_mtrace([{trace, P, return_from, {M, F, A}, R} | Rest], Dict) ->
    match_mtrace(Rest, ?DICT:update(P, fun
    ({[{MFA, {ok, Ret}} | StackTail], Acc, Indent}) when Ret == R ->
        {[{{M, F, A}, {ok, R}}, {MFA, skip} | StackTail], Acc, Indent + 1};
    ({Stack, Acc, Indent}) ->
        {[{{M, F, A}, {ok, R}} | Stack], Acc, Indent + 1}
    end, {[{{M, F, A}, {ok, R}}], [], 1}, Dict));

match_mtrace([{trace, P, call, {M, F, Args}} | Rest], Dict) ->
    match_mtrace(Rest, ?DICT:update(P, fun
    ({[{{M1, F1, A}, R} | StackTail], Acc, Indent}) when M == M1, F == F1, length(Args) == A ->
        {StackTail, [{Indent - 1, {M, F, Args}, R} | Acc], Indent - 1};
    ({Stack, Acc, Indent}) ->
        R = ?IF(Acc, [{_, _, E} | _] when E =:= exception; E =:= skip, skip, exception),
        {Stack, [{Indent, {M, F, Args}, R} | Acc], Indent}
    end, {[], [{0, {M, F, Args}, exception}], 0}, Dict));

match_mtrace([H | _Tail], _Dict) ->
    io:format("Unknown trace format: ~p", [H]),
    throw({error, {bad_trace, H}}).

print_mtrace(Trace) ->
    lists:foreach(fun({Pid, Trc}) ->
        io:format("~nProcess ~p:~n~s~n", [Pid, format_trace(Trc, [])])
    end, Trace).

print_trace(Trace) ->
    Str = format_trace(Trace, []),
    io:format("~s", [Str]).

format_trace(undefined, _) ->
    "undefined";
format_trace([], Acc) ->
    Rev = lists:reverse(Acc),
    lists:flatten(Rev);
format_trace([{Indent, {M,F,Args}, Result} | Tail], Acc) ->
    A = case Args of
        [] -> "";
        _  -> [_,[91,L,93]] = io_lib:format("~-*c~100p", [Indent+2,$.,Args]),
              L
        end,
    R = case Result of
        {ok, Res} -> io_lib:format("  ~100p", [Res]);
        exception -> "  ** exception **";
        skip      -> " "
        end,
    N = lists:flatlength(A ++ R),
    S = if N > 100 ->
            io_lib:format("~-*c~w:~w(~s) ->~n~s~n", [Indent,$., M,F,A,R]);
        true ->
            io_lib:format("~-*c~w:~w(~s) ->~s~n", [Indent,$., M,F,A,tl(R)])
        end,
    format_trace(Tail, [lists:flatten(S) | Acc]);
format_trace([Head | _Tail], _Acc) ->
    throw({error, ?FMT("ERROR! Wrong Trace Format: ~p", [Head])}).
