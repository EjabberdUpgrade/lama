%%%------------------------------------------------------------------------
%%% File: $Id: lama_mib.erl 214 2006-06-02 16:49:27Z serge $
%%%------------------------------------------------------------------------
%%% @doc Implements MIB instrumentation functions for ORG-LAMA-MIB.mib
%%% @author Serge Aleynikov <saleyn@gmail.com>
%%% @version $Rev: 214 $ 
%%%          $Date: 2006-06-02 12:49:27 -0400 (Fri, 02 Jun 2006) $
%%% @end
%%%------------------------------------------------------------------------
%%% Created: 2006-03-21 Serge Aleynikov <saleyn@gmail.com>
%%% $URL$
%%%------------------------------------------------------------------------
-module(lama_mib).
-author('saleyn@gmail.com').
-id("$Id: lama_mib.erl 214 2006-06-02 16:49:27Z serge $").

-export([counter/2, counter/3]).

%%
%% get functions
%% @private
%%
counter(get, Item) ->
    case Item of
    lamaNodeName             -> {value, atom_to_list(node())};
    lamaDateTime             -> {{Y,M,D},{H,Mi,S}} = calendar:local_time(),
                                {value, lists:flatten(
                                            io_lib:format("~w-~.2.0w-~.2.0w ~.2.0w:~.2.0w:~.2.0w",
                                                          [Y,M,D,H,Mi,S]))};
    lamaCurrentAlarmCount    -> {value, length(lama:get_alarms())};
    lamaAlarmInformation     -> {noValue, noSuchObject};
    _                        -> {noValue, noSuchObject}
    end.

%%
%% is_set_ok functions
%% @private
%%
counter(is_set_ok, _NewValue, _Param) ->
    inconsistentName;

%%
%% set functions
%%
counter(set, _NewValue, _) ->
    commitFailed.

