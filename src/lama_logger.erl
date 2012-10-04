%%%------------------------------------------------------------------------
%%% File: $Id$
%%%------------------------------------------------------------------------
%%% @doc Simplistic string logger.
%%%
%%% @author  Serge Aleynikov <saleyn@gmail.com>
%%% @version $Revision$
%%%          $Date$
%%% @end
%%%------------------------------------------------------------------------
%%% Created 2007-04-04 Serge Aleynikov <saleyn@gmail.com>
%%%------------------------------------------------------------------------
-module(lama_logger).
-author('saleyn@gmail.com').
-id    ("$Id$").

-behaviour(gen_server).

%% External exports
-export([start_link/3, log/2]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------
-include_lib("kernel/include/file.hrl").
-include("logger.hrl").

%%--------------------------------------------------------------------
%% Records
%%--------------------------------------------------------------------

%% Server state
-record(state, {
    fd,                 % term(), file descriptor
    fbase,              % string(), base of the filename
    fname,              % string(), file name
    append_date         % date | undefined
}).

%%--------------------------------------------------------------------
%% Macros
%%--------------------------------------------------------------------
%% benchmarking shows no real speed improvement by delayed_write,
%% just annoyance
-define(FILE_OPTS, [append, raw, binary]).

%%====================================================================
%% External functions
%%====================================================================

%%----------------------------------------------------------------------
%% @spec (Name::atom(), LogBase::string(), Verbose::boolean()) ->
%%          {ok, Pid} | {error, Reason}
%%
%% @doc Called by a supervisor to start the logging process.
%% @end
%%----------------------------------------------------------------------
start_link(Name, LogBase, AppendDate) when is_list(LogBase), is_boolean(AppendDate) ->
    DateSuffix = ?IF(AppendDate, true, date, undefined),
    gen_server:start_link({local, Name}, ?MODULE, [LogBase, DateSuffix], []).

%%--------------------------------------------------------------------
%% @spec (Logger, Data) -> ok
%%          Logger = atom() | pid()
%%          Data = list() | binary()
%% @doc Called by a supervisor to start the logging process.
%% @end
%%----------------------------------------------------------------------
log(LoggerPid, Data) when is_pid(LoggerPid), is_list(Data); is_binary(Data) ->
    case process_info(LoggerPid, message_queue_len) of
    N when N < 200 ->
        gen_server:cast(LoggerPid, {log, Data});
    _ ->
        gen_server:call(LoggerPid, {log, Data})
    end;
log(Logger, Data) when is_atom(Logger) ->
    log(whereis(Logger), Data).

%%%------------------------------------------------------------------------
%%% Callback functions from gen_server
%%%------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%% @spec (Args) -> {ok, State}           |
%%                 {ok, State, Timeout}  |
%%                 ignore                |
%%                 {stop, Reason}
%% @doc Called by gen_server framework at process startup.
%%      ```    Args       = [Basename, AppendDate]
%%             Basename   = string()  - is log filename base.
%%             AppendDate = date | undefined - if `date' is specified, the
%%                          log file is appended with a YYYYMMDD suffix
%%      '''
%% @end
%% @private
%%-------------------------------------------------------------------------
init([Basename, AppendDate]) ->
    Fname = lama:filename(Basename, AppendDate),
    %% Construct log filenames and open/create them
    case file:open(Fname, ?FILE_OPTS) of
    {ok, Fd} ->
        {ok, #state{fd=Fd, fbase=Basename, fname=Fname, append_date=AppendDate}};
    {error, Reason} ->
        {stop, "Error opening file " ++ Fname ++ ": " ++ file:format_error(Reason)}
    end.

%%-------------------------------------------------------------------------
%% @spec (Request, From, State) -> {reply, Reply, State}          |
%%                                 {reply, Reply, State, Timeout} |
%%                                 {noreply, State}               |
%%                                 {noreply, State, Timeout}      |
%%                                 {stop, Reason, Reply, State}   |
%%                                 {stop, Reason, State}
%% @doc Callback for synchronous server calls.  If `{stop, ...}' tuple
%%      is returned, the server is stopped and `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------
handle_call({log, Data}, _From, #state{fd=IO, fname=FN} = State)
  when is_binary(Data); is_list(Data) ->
    try
        IoDevice = write_to_file(IO, FN, Data),
        {reply, ok, State#state{fd = IoDevice}}
    catch error:Why ->
        {stop, Why, State}
    end;
handle_call(Unknown, _From, State) ->
    {stop, {unsupported_call, Unknown, State}}.

%%-------------------------------------------------------------------------
%% @spec (Msg, State) ->{noreply, State}          |
%%                      {noreply, State, Timeout} |
%%                      {stop, Reason, State}
%% @doc Callback for asyncrous server calls.  If `{stop, ...}' tuple
%%      is returned, the server is stopped and `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------
handle_cast({log, Data}, #state{fd=IO, fname=FN} = State)
  when is_binary(Data); is_list(Data) ->
    try
        IoDevice = write_to_file(IO, FN, Data),
        {noreply, State#state{fd = IoDevice}}
    catch error:Why ->
        {stop, Why, State}
    end;

handle_cast(Unknown, State) ->
    {stop, {unknown_cast, Unknown}, State}.

%%-------------------------------------------------------------------------
%% @spec (Msg, State) ->{noreply, State}          |
%%                      {noreply, State, Timeout} |
%%                      {stop, Reason, State}
%% @doc Callback for messages sent directly to server's mailbox.
%%      If `{stop, ...}' tuple is returned, the server is stopped and
%%      `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------
handle_info(Unknown, State) ->
    ?ERROR("~w logger: unknown message: ~80p\n", [self(), Unknown]),
    {noreply, State}.

%%-------------------------------------------------------------------------
%% @spec (Reason, State) -> any
%% @doc  Callback executed on server shutdown. It is only invoked if
%%       `process_flag(trap_exit, true)' is set by the server process.
%%       The return value is ignored.
%% @end
%% @private
%%-------------------------------------------------------------------------
terminate(Reason, State) ->
    file:close(State#state.fd),
    Reason.

%%-------------------------------------------------------------------------
%% @spec (OldVsn, State, Extra) -> {ok, NewState}
%% @doc  Convert process state when code is changed.
%% @end
%% @private
%%-------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%------------------------------------------------------------------------
%%% Internal functions
%%%------------------------------------------------------------------------

write_to_file(IoDevice, Filename, Data) ->
    case file:write(IoDevice, Data) of
    ok ->
        IoDevice;
    {error, Reason} ->
        erlang:error(?FMT("Error writing to log ~s: ~p.",
                          [Filename, file:format_error(Reason)]))
    end.
