-module(lama_SUITE).

-export([all/1]).

-export([init_per_testcase/2, fin_per_testcase/2]).

-export([test/1]).

-include_lib("test_server/include/test_server.hrl").

init_per_testcase(_Case, Config) ->
    Config.

fin_per_testcase(_Case, _Config) ->
    ok.

all(doc) ->
    ["Logs and Alerts Managment Application tests."];
all(suite) ->
    %% Test specification on test suite level
    [test].

test(doc)    ->  ["Sample test"];
test(suite)  ->  [];
test(_Config) ->  ?line ok = ok.

