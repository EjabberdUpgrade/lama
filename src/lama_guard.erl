%%%------------------------------------------------------------------------
%%% File: $Id: lama_guard.erl 339 2006-09-21 19:58:38Z serge $
%%%------------------------------------------------------------------------
%%% @doc This module implements a guard process for custom event handlers
%%% @author Serge Aleynikov <saleyn@gmail.com>
%%% @version $Rev: 339 $
%%%          $LastChangedDate: 2006-09-21 15:58:38 -0400 (Thu, 21 Sep 2006) $
%%% @end
%%%------------------------------------------------------------------------
-module(lama_guard).
-author('saleyn@gmail.com').
-id("$Id: lama_guard.erl 339 2006-09-21 19:58:38Z serge $").

%%%
%%% A guard process that facilitates re-addition of alarm and log handlers
%%% in case if they crash
%%%

-export([start_link/3,
         init/4,
         system_continue/3,
         system_terminate/4,
         system_code_change/4]).

%% @spec start_link(GuardName::atom(), HandlerModule::atom(), Options::list()) ->
%%         {ok, Pid} | {error, {already_started, Pid}} | {error, Reason}
%% @doc Use this function to link this process to a supervisor.  Note that it uses
%% proc_lib so that this process would comply with OTP release management principles
%% @end
%%
start_link(GuardName, HandlerModule, Options) ->
    Self = self(),
    proc_lib:start_link(?MODULE, init, [GuardName, HandlerModule, Options, Self], infinity).

init(GuardName, HandlerModule, Options, Parent) ->
    case catch erlang:register(GuardName, self()) of
    true ->
        % Note that HandlerModule:start_link/1 will install a new event handler supervised
        % by this guarding process
        case catch HandlerModule:start_link(Options) of
        ok ->
            proc_lib:init_ack(Parent, {ok, self()}),
            loop(Parent, GuardName);
        already_started ->
            proc_lib:init_ack(Parent, {error, {already_started, HandlerModule}});
        Error ->
            proc_lib:init_ack(Parent, {error, Error})
        end;
    _Error ->
        Pid = whereis(GuardName),
        proc_lib:init_ack(Parent, {error, {already_started, Pid}})
    end.

loop(Parent, GuardName) ->
    receive
    %% gen_event sends this message if a handler was added using
    %% gen_event:add_sup_handler/3 or gen_event:swap_sup_handler/3 functions
    {gen_event_EXIT, Handler, Reason}
        when Handler == lama_alarm_h;
             Handler == lama_log_h ->
        io:format("~w: ~p detected handler ~p shutdown:~n~p~n",
                  [?MODULE, GuardName, Handler, Reason]),
        % Let the guard crash.  It's supervisor will restart this guard process
        % that will, in turn, reinstall the failed event handler.
        exit({handler_died, Handler, Reason});
    %% This one is for testing purposes
    stop ->
        io:format("~w: ~p received stop request~n",
                  [?MODULE, GuardName]),
        exit(normal);
    %% Handle OTP system messages
    {system, From, Msg} ->
        sys:handle_system_msg(Msg, From, Parent, ?MODULE, [], GuardName);
    {_Label, From, get_modules} ->
        gen:reply(From, [?MODULE]),
        loop(Parent, GuardName);
    %% This should never happen
    Other ->
        io:format("~w: ~p received unknown message:~n~p~n",
                  [?MODULE, GuardName, Other]),
        loop(Parent, GuardName)
    end.

%% Callbacks of the sys module to process system messages.
%%
system_continue(Parent, _Debug, GuardName) ->
    loop(Parent, GuardName).

system_terminate(Reason, _Parent, _Debug, _GuardName) ->
    exit(Reason).

system_code_change(GuardName, _Module, _OldVsn, _Extra) ->
    {ok, GuardName}.
