%%----------------------------------------------------------------------
%% File    : logger.hrl
%% Author  : Serge Aleynikov
%% Purpose : Generic log message macros
%% Created : 6/1/2005 1:43PM
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Write the report at the local node only.
%% Note that there are two flavors of the ALERT and ERROR macros.  The
%% ones with the "OAM_" prefix allow to define an
%% ErrClass::atom() and ErrCode::integer() elements for ease of error
%% classification.
%%----------------------------------------------------------------------
-define(OAM_ALERT(ErrClass_, ErrCode_, Str_, Args_),
    error_logger:error_report({lama,alert},
        {false,{lama:get_app(),?MODULE,?LINE, {ErrClass_, ErrCode_}, Str_, Args_}})).
-define(OAM_ERROR(ErrClass_, ErrCode_, Str_, Args_),
    error_logger:error_report({lama,error},
        {false,{lama:get_app(),?MODULE,?LINE, {ErrClass_, ErrCode_}, Str_, Args_}})).

-define(ALERT(Str_, Args_),
    error_logger:error_report({lama,alert},
        {false,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).
-define(ERROR(Str_, Args_),
    error_logger:error_report({lama,error},
        {false,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).
-define(WARNING(Str_, Args_),
    error_logger:error_report({lama,warning},
        {false,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).

%% NOTICE, INFO, DEBUG - don't get sent to log, but get displayed on screen.
%% INFO,   DEBUG       - display plain formated text.
%% NOTICE              - displays text with a standard SASL header
%% These behaviors can be overriden by LAMA configuration options.
-define(NOTICE(Str_, Args_),
    error_logger:error_report({lama,notice},
        {false,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).
-define(INFO(Str_, Args_),
    error_logger:error_report({lama,info},
        {false,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).

-define(LOG(Str_, Args_),
    error_logger:error_report({lama,log},
        {false,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).

%% Verbosity levels supported by DEBUG: silent, lowest, low, medium, high, highest
-define(DEBUG(Verbosity_, Str_, Args_),
    case lama_log_h:log_debug_event(Verbosity_) of
    false -> ok;
    true  -> error_logger:error_report({lama,debug},
                {false, {lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})
    end).

%% Alarm handling
-define(ALARM_SET(Alarm, Varbinds),
    lama_alarm_h:set_alarm(Alarm, Varbinds, {lama:get_app(),?MODULE,?LINE,undefined})).
-define(ALARM_CLEAR(AlarmId),
    lama_alarm_h:clear_alarm(AlarmId, {lama:get_app(),?MODULE,?LINE,undefined})).

%%----------------------------------------------------------------------
%% Write the report at all known nodes.
%%----------------------------------------------------------------------
-define(OAM_DIST_ALERT(ErrClass_, ErrCode_, Str_, Args_),
    error_logger:error_report({lama,alert},
        {true,{lama:get_app(),?MODULE,?LINE, {ErrClass_, ErrCode_}, Str_, Args_}})).
-define(OAM_DIST_ERROR(ErrClass_, ErrCode_, Str_, Args_),
    error_logger:error_report({lama,error},
        {true,{lama:get_app(),?MODULE,?LINE, {ErrClass_, ErrCode_}, Str_, Args_}})).

-define(DIST_ALERT(Str_, Args_),
    error_logger:error_report({lama,alert},
        {true,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).
-define(DIST_ERROR(Str_, Args_),
    error_logger:error_report({lama,error},
        {true,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).
-define(DIST_WARNING(Str_, Args_),
    error_logger:error_report({lama,warning},
        {true,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).
-define(DIST_NOTICE(Str_, Args_),
    error_logger:error_report({lama,notice},
        {false,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).
-define(DIST_INFO(Str_, Args_),
    error_logger:error_report({lama,info},
        {true,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})).
-define(DIST_DEBUG(Verbosity_, Str_, Args_),
    case lama_log_h:log_debug_event(Verbosity_) of
    false -> ok;
    true  -> error_logger:error_report({lama,debug},
                  {true,{lama:get_app(),?MODULE,?LINE, undefined, Str_, Args_}})
    end).

%% Format a string to be used by the macros above.
-define(FMT(Format_,Arguments_),
	    lists:flatten(io_lib:format(Format_,Arguments_))).
-define(FLAT(String_), lists:flatten(String_)).

-ifndef(IF).
-define(IF(Condition_, Value_, True, False), case Condition_ of Value_ -> True; _ -> False end).
-endif.

%% Throwable macro containing source information
-define(THROW(Fmt_, Args_),
        throw({error, lists:flatten(io_lib:format(Fmt_++" (~w:~d)",Args_++[?MODULE,?LINE]))})).

%% Simple debugging macro for print tracing
-ifdef(debug).
-define(dbg(Fmt_, Args_), io:format("~w: " ++ Fmt_, [self()] ++ Args_)).
-else.
-endif.

%%
%% Internally used for event masking
%%
-define(LAMA_TEST,      1 bsl 5).  % Test is just for internal testing.
-define(LAMA_LOG,       1 bsl 6).
-define(LAMA_ALERT,     1 bsl 5).
-define(LAMA_ERROR,     1 bsl 4).
-define(LAMA_WARNING,   1 bsl 3).
-define(LAMA_NOTICE,    1 bsl 2).
-define(LAMA_INFO,      1 bsl 1).
-define(LAMA_DEBUG,     1 bsl 0).
