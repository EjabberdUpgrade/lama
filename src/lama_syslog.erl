%%%------------------------------------------------------------------------
%%% File: $Id: lama_syslog.erl 777 2007-04-10 19:53:38Z serge $
%%%------------------------------------------------------------------------
%%% @doc This module implements syslog encoding functions.
%%% @author   Serge Aleynikov <saleyn@gmail.com>
%%% @version  $Rev: 777 $
%%%           $LastChangedDate: 2007-04-10 15:53:38 -0400 (Tue, 10 Apr 2007) $
%%% ``
%%% Example message as seen in the syslog file:
%%% Mar 19 21:26:44 10.231.12.2 n@spider:test[0.45.0]: [ALERT] Test msg
%%% '''
%%% @end
%%%----------------------------------------------------------------------
%%% $URL$
%%% Created: 19-Mar-2003
%%%----------------------------------------------------------------------
-module(lama_syslog).
-author('saleyn@gmail.com').
-id("$Id: lama_syslog.erl 777 2007-04-10 19:53:38Z serge $").

%% External exports
-export([init/1, log/2, terminate/2]).

-include("logger.hrl").

-define(SYSLOG_PORT, 514).

%% Internal state
-record(syslog_state, {
    host,         % Destination host for syslog messages
    indent,       % Default tag to use for syslog messages
    facility,     % Default facility to use for syslog messages
    sock,         % Syslog socket
    syslog_types  % Mask of event types that need to be sent to syslog
                  %  Default: lama:encode_mask([alert,error,warning]).
}).

%%---------------------------------------------------------------------
%% @spec (Options) -> State | throw({error, Reason})
%% @doc Initialize syslog event logger
%% @end
%%---------------------------------------------------------------------
init(Options) ->
    case lama:get_opt(use_syslog, Options) of
    false ->
        undefined;
    true ->
        Host     = lama:get_opt(syslog_host,     Options),
        Facility = lama:get_opt(syslog_facility, Options),
        Indent   = lama:get_opt(syslog_indent,   Options),
        SLopt    = lama:get_opt(syslog_types,    Options),

        case encode_facility(Facility) of
        N when is_integer(N) -> ok;
        _ -> throw({error, ?FMT("Invalid syslog facility: ~p", [Facility])})
        end,

        IP = get_host(Host),

        case gen_udp:open(0) of
        {ok, S} ->
            #syslog_state{
                host          = IP,
                indent        = Indent,
                facility      = Facility,
                sock          = S,
                syslog_types  = lama:encode_mask(SLopt)
            };
        {error, Why} ->
            throw({stop, ?FMT("Failed to open a UDP socket: ~s", [inet:format_error(Why)])})
        end
    end.

%%---------------------------------------------------------------------
%% @spec (Report, State) -> {ok, State} | throw({error, Reason})
%%          Report = {Pid, NowTime, Priority, Header, Msg::io_list()}
%%          State  = #syslog_state{}
%% @doc Initialize syslog event logger
%% @end
%%---------------------------------------------------------------------
log(_Event, undefined) -> ok;
log({_Pid, _Time, Priority, _Header, _Fmt, _Msg} = Report, #syslog_state{syslog_types = ST} = State) ->
    case lama:priority_to_int(Priority) band ST of
    0 -> ok;
    _ -> do_log(Report, State)
    end.

%%---------------------------------------------------------------------
%% @spec (Reason, State) -> void()
%% @private
%%---------------------------------------------------------------------
terminate(_Reason, #syslog_state{sock=S}) ->
    (catch gen_udp:close(S)),
    ok.

%%%--------------------------------------------------------------------
%%% Internal functions
%%%--------------------------------------------------------------------
do_log({Pid, Time, Priority, Header, Msg}, #syslog_state{host=H, indent=I, facility=F, sock=S}) ->
    Packet = io_lib:format("<~w>~s ~w[~s]: [~s] " ++ Msg,
                 [encode_facility(F) bor encode_priority(Priority),
                  lama:timestamp(Time, log), I, lama:format_pid(Pid), Header]),
    gen_udp:send(S,H,?SYSLOG_PORT,Packet).

get_host(Host) ->
    case inet:gethostbyname(Host) of
    {ok,{hostent,_,_,inet,4,[IP|_]}} ->
        IP;
    {error, Reason} ->
        throw({stop, ?FMT("Failed to resolve hostname ~p: ~s", [Host, inet:format_error(Reason)])})
    end.

encode_priority(emergency) -> 0; % system is unusable
encode_priority(alert)     -> 1; % action must be taken immediately
encode_priority(critical)  -> 2; % critical conditions
encode_priority(error)     -> 3; % error conditions
encode_priority(warning)   -> 4; % warning conditions
encode_priority(notice)    -> 5; % normal but significant condition
encode_priority(info)      -> 6; % informational
encode_priority(debug)     -> 7; % debug-level messages
encode_priority(log)       -> 6. % informational

encode_facility(local7)    -> (23 bsl 3); % local use 7
encode_facility(local6)    -> (22 bsl 3); % local use 6
encode_facility(local5)    -> (21 bsl 3); % local use 5
encode_facility(local4)    -> (20 bsl 3); % local use 4
encode_facility(local3)    -> (19 bsl 3); % local use 3
encode_facility(local2)    -> (18 bsl 3); % local use 2
encode_facility(local1)    -> (17 bsl 3); % local use 1
encode_facility(local0)    -> (16 bsl 3); % local use 0
encode_facility(clock)     -> (15 bsl 3); % clock daemon
encode_facility(log_alert) -> (14 bsl 3); % log alert (note 1)
encode_facility(log_audit) -> (13 bsl 3); % log audit (note 1)
encode_facility(ntp)       -> (12 bsl 3); % ntp daemon
encode_facility(ftp)       -> (11 bsl 3); % ftp daemon
encode_facility(authpriv)  -> (10 bsl 3); % security/authorization messages (private)
encode_facility(cron)      -> ( 9 bsl 3); % clock daemon
encode_facility(uucp)      -> ( 8 bsl 3); % UUCP subsystem
encode_facility(news)      -> ( 7 bsl 3); % network news subsystem
encode_facility(lpr)       -> ( 6 bsl 3); % line printer subsystem
encode_facility(syslog)    -> ( 5 bsl 3); % messages generated internally by syslogd
encode_facility(auth)      -> ( 4 bsl 3); % security/authorization messages
encode_facility(daemon)    -> ( 3 bsl 3); % system daemons
encode_facility(mail)      -> ( 2 bsl 3); % mail system
encode_facility(user)      -> ( 1 bsl 3); % random user-level messages
encode_facility(kern)      -> ( 0 bsl 3). % kernel messages
