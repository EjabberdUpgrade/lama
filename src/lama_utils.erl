%%%------------------------------------------------------------------------
%%% File: $Id: lama_utils.erl 391 2006-10-13 16:21:03Z dkarga $
%%%------------------------------------------------------------------------
%%% @doc This module implements miscelaneous utility functions
%%% @author Serge Aleynikov <saleyn@gmail.com>
%%% @version $Rev: 391 $
%%%          $Date: 2006-10-13 12:21:03 -0400 (Fri, 13 Oct 2006) $
%%% @end
%%%------------------------------------------------------------------------
%%% Created: 2006/6/16 by Serge Aleynikov <saleyn@gmail.com>
%%% $URL: http://devlinuxpro/svn/libraries/Erlang/lama/current/src/lama_utils.erl $
%%%------------------------------------------------------------------------
-module(lama_utils).
-author('saleyn@gmail.com').
-id("$Id: lama_utils.erl 391 2006-10-13 16:21:03Z dkarga $").

-include("logger.hrl").

%%%
%%% Public exports
%%%

-export([
    str_to_exprs/1, eval_str/1, eval_str/2,
    str_to_term/1, str_to_terms/1, seconds_since_epoch/1, seconds_since_epoch/2,
    bytestring_to_hexstring/1, hexstring_to_bytestring/1,
    check_loops/3, random_shuffle/1, i2l/2, month/1
]).

%%----------------------------------------------------------------------
%% @spec str_to_exprs(String) -> {ok, Exprs} | throw({error, Reason})
%%       String = string()
%%       Exprs   = [term()]
%%       Reason = string()
%% @doc Convert a string to a list of the abstract forms of the parsed expressions.
%%      A String is a string representation of an expressions ending with ".".
%%      Expression list can be used then in call to erl_eval:exprs/1
%%      `` Ex: str_to_exprs("fun(A) -> A + 1 end.") ''
%% @end
%%----------------------------------------------------------------------
str_to_exprs(Str) ->
    T = get_tokens(Str),
    case erl_parse:parse_exprs(T) of
    {ok, Exprs} ->
        {ok, Exprs};
    {error, {Line, _, Info}} ->
        throw({error, ?FMT("~s (line: ~w)", [erl_parse:format_error(Info), Line])})
    end.

%%----------------------------------------------------------------------
%% @spec eval_str(String, Bindings) -> {value, Value, NewBindings} |
%%           throw({error, Reason}) | throw({error, {exception, Class, Exception}})
%%       String = string()
%%       Value  = term()
%%       Bindings = term()
%%       NewBindings = term()
%%       Reason = string()
%%       Class = term()
%%       Exception = term()
%% @doc Evaluate string as expressions using variable bindings.
%%      A String is a string representation of an expressions ending with ".".
%%      Bindings and NewBindings - as returned by erl_eval:bindings/1.
%%      Note:
%%        exception {error, Reason} means parsing error;
%%        exception {error, {exception, Class, Exception} means evaluating error.
%% @end
%%----------------------------------------------------------------------
eval_str(Str, Bindings) ->
    {ok, Exprs} = str_to_exprs(Str),
    try erl_eval:exprs(Exprs, Bindings) of
    {value, Value, NewBindings} ->
        {value, Value, NewBindings}
    catch
    Class:Exception ->
        % exception raised when evaluating expressions
        throw({error, {exception, Class, Exception}})
    end.

%%----------------------------------------------------------------------
%% @spec eval_str(String) -> {value, Value, NewBindings} |
%%           throw({error, Reason}) | throw({error, {exception, Class, Exception}})
%%       String = string()
%%       Value  = term()
%%       NewBindings = term()
%%       Reason = string()
%%       Class = term()
%%       Exception = term()
%% @doc Evaluate string as expressions.
%%      A String is a string representation of an expressions ending with ".".
%%      Bindings and NewBindings - as returned by erl_eval:bindings/1.
%%      Note:
%%        exception {error, Reason} means parsing error;
%%        exception {error, {exception, Class, Exception} means evaluating error.
%% @end
%%----------------------------------------------------------------------
eval_str(Str) ->
    eval_str(Str, erl_eval:new_bindings()).

%%----------------------------------------------------------------------
%% @spec str_to_term(String) -> {ok, Term} | throw({error, Reason})
%%       String = string()
%%       Term   = term()
%%       Reason = string()
%% @doc Convert a string to an Erlang term.  A String is a string
%%      representation of a term ending with ".".  A Term is an Erlang
%%      term.
%%      `` Ex: str_to_term("{1,2,[hello]}.") -> {1,2,[hello]} ''
%% @end
%%----------------------------------------------------------------------
str_to_term(Str) ->
    T = get_tokens(Str),
    case erl_parse:parse_term(T) of
    {ok, Term} ->
        {ok, Term};
    {error, {Line, _, Info}} ->
        throw({error, ?FMT("~s (line: ~w)", [erl_parse:format_error(Info), Line])})
    end.

%%----------------------------------------------------------------------
%% @spec str_to_terms(String) -> {ok, Terms} | throw({error, Reason})
%%       String = string() | binary()
%%       Terms  = [ term() ]
%%       Reason = string()
%% @doc Convert a string to a list of Erlang terms.  This function is
%%      similar to file:consult/1 but it works on a string as opposed to
%%      a file.  An exception is thrown if there is a parsing problem.
%%
%%      `` Ex: str_to_terms("{1,2,[hello]}.\n{3,4}.") ->
%%               [{1,2,[hello]}, {3,4}] ''
%% @end
%%----------------------------------------------------------------------
str_to_terms(BinStr) when is_binary(BinStr) ->
    str_to_terms(binary_to_list(BinStr));
str_to_terms(Str) when is_list(Str) ->
    Tokens = get_tokens(Str),
    parse_tokens(Tokens).

get_tokens(Str) ->
    case erl_scan:string(Str) of
    {ok, Tokens, _} ->
        Tokens;
    {error, Info, Line} ->
        throw({error, ?FMT("~s (line: ~w)", [erl_parse:format_error(Info), Line])})
    end.

parse_tokens(Tokens) ->
    parse_tokens(Tokens, [], []).
parse_tokens([], [], Acc) ->
    lists:foldl(
        fun(T, A) ->
            case erl_parse:parse_term(T) of
            {ok, Term} ->
                [Term | A];
            {error, {Line, _, Why}} ->
                throw({error, ?FMT("~s (line: ~w)", [erl_parse:format_error(Why), Line])})
            end
        end,
        [], Acc);
parse_tokens([], L, Acc) ->
    parse_tokens([], [], [lists:reverse(L) | Acc]);
parse_tokens([{dot,_}=H | Tail], L, Acc) ->
    Term = lists:reverse([H|L]),
    parse_tokens(Tail, [], [Term | Acc]);
parse_tokens([H | Tail], L, Acc) ->
    parse_tokens(Tail, [H | L], Acc).

%%-------------------------------------------------------------------------
%% @spec (NowTime::now()) -> integer()
%% @doc Returns number of seconds in local time elapsed from
%%      1-Jan-1970 00:00:00 UTC.
%% @end
%%-------------------------------------------------------------------------
seconds_since_epoch(NowTime) ->
    seconds_since_epoch(NowTime, local).

%%-------------------------------------------------------------------------
%% @spec (NowTime::now(), Type) -> integer()
%%          Type = local | utc
%% @doc Returns number of seconds in local or UTC time elapsed from
%%      1-Jan-1970 00:00:00 UTC.
%% @end
%%-------------------------------------------------------------------------
seconds_since_epoch(NowTime, local) ->
    calendar:datetime_to_gregorian_seconds(calendar:now_to_local_time(NowTime)) -
    calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}});
seconds_since_epoch(NowTime, utc) ->
    calendar:datetime_to_gregorian_seconds(calendar:now_to_universal_time(NowTime)) -
    calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}).

%%-------------------------------------------------------------------------
%% @spec check_loops(List, RootVal, RequireCommonRoot) ->
%%              ok | throw({error, Reason})
%%           List              = [ {Key, ParentKey} ]
%%           RequireCommonRoot = boolean()
%%           Reason            = {Key, Description::string()}
%%
%% @doc Check if there are loops in the hierarchical ``List''.
%%      ``RootVal'' is the value of a root entry in the hierarchy of keys.
%%      If ``RequireCommonRoot'' is ``true'', then each node must have a
%%      parent with the top-most parent being RootVal.
%%      If ``RequireCommonRoot'' is ``false'', the hierarchical tree
%%      may have nodes without parents.<br/>
%%        This function implements an algorithm that finds loops in a list
%%      containing tuples of hierarchically linked keys.  The algorithm
%%      builds a dictionary of {key, parent_key} tuples, and for each
%%      tuple in the list uses two navigational counters.  One counter
%%      traverses the hierarchy one step at a time, and the second goes
%%      two steps at a time.  If such traversal results in the same key
%%      being fetched by each counter, we have a loop.
%% ```
%%      Example:  check_loops([{a,root},{b,a},{c,b}], root, true) -> ok
%% '''
%% @end
%%-------------------------------------------------------------------------
check_loops(List, RootVal, RequireCommonRoot) ->
    Dict = list_to_dict(List, dict:new()),
    lists:foreach(fun({Key,_}) ->
                      find_loop(Key, Dict, RootVal, Key, RequireCommonRoot)
                  end, List).

list_to_dict([], Dict) ->
    Dict;
list_to_dict([{Key,Val} | Tail], Dict) ->
    case dict:find(Key, Dict) of
    {ok, Value} ->
        throw({error, {Key, ?FMT("multiple parents found: (~p, ~p)", [Val, Value])}});
    error ->
        list_to_dict(Tail, dict:store(Key, Val, Dict))
    end.

find_loop(RootVal, _Dict, RootVal, _StartKey, _RequireCommonRoot) ->
    ok;
find_loop(Key, Dict, RootVal, StartKey, RequireCommonRoot) ->
    Parent = dict:fetch(Key, Dict),
    is_loop(Key, Parent, Dict, RootVal, StartKey, RequireCommonRoot).

is_loop(RootVal, _PKey, _Dict, RootVal, _StartKey, _RequireCommonRoot) ->
    ok;
is_loop(_Key, RootVal, _Dict, RootVal, _StartKey, _RequireCommonRoot) ->
    ok;
is_loop(Key, Key, _Dict, _RootVal, StartKey, _RequireCommonRoot) ->
    throw({error, {StartKey, "loop detected"}});
is_loop(Key, PKey, Dict, RootVal, StartKey, RequireCommonRoot) ->
    NewKey  = move(Key,  1, Dict, RootVal, RequireCommonRoot),
    NewPKey = move(PKey, 2, Dict, RootVal, RequireCommonRoot),
    is_loop(NewKey, NewPKey, Dict, RootVal, StartKey, RequireCommonRoot).

move(RootVal, _N, _Dict, RootVal, _RequireCommonRoot) ->
    RootVal;
move(Key, 0, _Dict, _RootVal, _RequireCommonRoot) ->
    Key;
move(Key, N, Dict, RootVal, RequireCommonRoot) ->
    case {dict:find(Key, Dict), RequireCommonRoot} of
    {{ok, Val}, _} ->
        move(Val, N-1, Dict, RootVal, RequireCommonRoot);
    {error, true} ->
        % No hanging leafs without parents are allowed.  The tree
        % must be fully connected.
        throw({error, {Key, "no parents found"}});
    {error, false} ->
        % Not a problem - nodes without parents are allowed
        RootVal
    end.

%----------------------------------------------------------------------------
% @spec random_shuffle(List::list()) -> RandomList::list()
% @doc Constructs a random permutation of a list.
% @end
%----------------------------------------------------------------------------
random_shuffle(List) ->
    L  = [{random:uniform(16#FFFF), E} || E <- List],
    [E || {_,E} <- lists:keysort(1, L)].

%%------------------------------------------------------------------------
%% @spec bytestring_to_hexstring(ByteString::list()) -> string()
%% @doc Converts a byte string to a list of hexadecimal digits
%%      (every one byte will be represented as two hex digits).
%% @end
%%------------------------------------------------------------------------
bytestring_to_hexstring([]) -> [];
bytestring_to_hexstring([H|T]) when is_integer(H), 0 =< H, H < 256 ->
    case erlang:integer_to_list(H, 16) of
    [I]   -> [$0, I | bytestring_to_hexstring(T)];
    [I,J] -> [ I, J | bytestring_to_hexstring(T)]
    end.

%%------------------------------------------------------------------------
%% @spec hexstring_to_bytestring(HexString::list()) -> list()
%% @doc Converts a hex string to a list of integers. Each two hex digits
%%      represent one byte [0 ... 255].
%% @end
%%------------------------------------------------------------------------
hexstring_to_bytestring(L) ->
    % We need to reverse the list becase left-most "0" may not be passed
    % when length(L) is odd.  Therefore we have to start processing from
    % the tail of the list.
    hexstring_to_bytestring2(lists:reverse(L), []).
hexstring_to_bytestring2([],  Acc) -> Acc;
hexstring_to_bytestring2([H], Acc) ->
    [erlang:list_to_integer([H], 16) | Acc];
hexstring_to_bytestring2([H1, H2 | Rest], Acc) ->
    I = erlang:list_to_integer([H2, H1], 16),
    hexstring_to_bytestring2(Rest, [I | Acc]).

%%------------------------------------------------------------------------
%% @spec (I::integer(), Width::integer()) -> string()
%% @doc Convert an integer to a list left-padded with 0's.
%% @end
%%------------------------------------------------------------------------
i2l(I, Width) -> string:right(integer_to_list(I), Width, $0).

%%------------------------------------------------------------------------
%% @spec (Month::integer()) -> string()
%% @doc Return the month number as a string
%% @end
%%------------------------------------------------------------------------
month(I) when I > 0, I < 12 ->
    element(I, {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}).
