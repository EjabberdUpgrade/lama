%%%------------------------------------------------------------------------
%%% File: $Id: lama_console.erl 777 2007-04-10 19:53:38Z serge $
%%%------------------------------------------------------------------------
%%% @doc This module implements console logging functionality.
%%% @author   Serge Aleynikov <saleyn@gmail.com>
%%% @version  $Rev: 777 $
%%%           $LastChangedDate: 2007-04-10 15:53:38 -0400 (Tue, 10 Apr 2007) $
%%% @end
%%%----------------------------------------------------------------------
%%% $URL$
%%% Created: 19-Mar-2003
%%%----------------------------------------------------------------------
-module(lama_console).
-author('saleyn@gmail.com').
-id("$Id: lama_console.erl 777 2007-04-10 19:53:38Z serge $").

%% External exports
-export([init/1, log/2]).

-record(console_state, {
    display_types    % List of priority types (see logger.hrl) that will be displayed to screen
                     %  Default: lama:encode_mask[alert,error,warning,notice,info,debug]
}).

%%---------------------------------------------------------------------
%% @spec (Options) -> State::#console_state{}
%% @doc Console logger initialization
%% @end
%%---------------------------------------------------------------------
init(Options) ->
    case lama:get_opt(use_console, Options) of
    false ->
        undefined;
    true  ->
        Display = lama:get_opt(display_types, Options),
        #console_state{display_types = lama:encode_mask(Display)}
    end.

%%---------------------------------------------------------------------
%% @spec (Report, State::#console_state{}) -> ok
%%          Report = {Pid, NowTime, Priority, Header, Msg::io_list()}
%% @doc Called by lama_log_h:log() events.
%% @end
%%---------------------------------------------------------------------
log(_Report, undefined) -> ok;
log({_Pid, _Time, Priority, Header, Msg}, #console_state{display_types = DT}) ->
    case lama:priority_to_int(Priority) band DT of
    0 -> ok;
    _ -> io:put_chars([Header, Msg])
    end.

%%%--------------------------------------------------------------------
%%% Internal functions
%%%--------------------------------------------------------------------
