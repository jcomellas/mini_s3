-module(hash_SUITE).

%% CT callbacks
-export([all/0]).

%% test callbacks
-export([t_hash_file_test/1]).

-include_lib("common_test/include/ct.hrl").


%%%------------------------------------------------------------------------
%%% Callback functions from CT
%%%------------------------------------------------------------------------

all() ->
    [t_hash_file_test].

%%%------------------------------------------------------------------------
%%% test cases
%%%------------------------------------------------------------------------

t_hash_file_test(Config) ->
    DataDir = get_data_dir(Config),
    TestFName = filename:join(DataDir, "cam.png"),
    {ok, Data} = file:read_file(TestFName),
    Expected = "J38lnA4e2jmqPqn9LKYzZg==",
    Result1 = base64:encode_to_string(crypto:hash(md5,Data)),
    Result2 = mini_s3:base64_hash_file(TestFName, 2048, md5),
    true = Expected =:= Result1 andalso Expected =:= Result2,
    ok.

%%%------------------------------------------------------------------------
%%% private
%%%------------------------------------------------------------------------
get_data_dir(Config) ->
    proplists:get_value(data_dir, Config).