-module(fakes3_SUITE).

%% CT callbacks
-export([all/0,
         init_per_suite/1,
         end_per_suite/1]).

%% test callbacks
-export([t_create_and_delete_bucket_test/1]).
-export([t_put_and_delete_object_test/1]).
-export([t_stream_large_file_test/1]).
-export([t_eunit_test/1]).

-include_lib("common_test/include/ct.hrl").

-define(FAKES3_PORT, 7689).

%%%------------------------------------------------------------------------
%%% Callback functions from CT
%%%------------------------------------------------------------------------

all() ->
    [t_create_and_delete_bucket_test,
     t_put_and_delete_object_test,
     t_stream_large_file_test,
     t_eunit_test].

init_per_suite(Config) ->
    mini_s3:manual_start(),
    ok = case is_gem_installed() orelse is_fakes3_install_global() of
        true  -> ok;
        false -> error_no_gem_or_fakes3()
    end,
    InstallType = get_fakes3_install_type(Config),
    {ok, _} = start_fakes3(InstallType, Config),
    % give the fakes3 server time to crank up
    timer:sleep(5000),
    Config.

end_per_suite(Config) ->
    ok = fakes3_server:stop(),
    Config.

%%%------------------------------------------------------------------------
%%% test cases
%%%------------------------------------------------------------------------

t_eunit_test(_Config) ->
    ok = eunit:test(mini_s3).

t_create_and_delete_bucket_test(_Config) ->
    S3Conf = test_config(),
    ok = mini_s3:create_bucket("test_bucket", private, none, S3Conf),
    ok = mini_s3:delete_bucket("test_bucket",S3Conf),
    ok.

t_put_and_delete_object_test(_Config) ->
    Value = [<<"test">>, "Value"],
    BucketName = "test_bucket",
    Key = "test_key",
    S3Conf = test_config(),
    ok = mini_s3:create_bucket(BucketName, private, none, S3Conf),
    PutResults = mini_s3:put_object(BucketName,
                                             Key,
                                             Value,
                                             [],
                                             [],
                                             S3Conf),
    GetResults = mini_s3:get_object(BucketName, Key, [], S3Conf),
    [_|_] = mini_s3:delete_object(BucketName, Key, S3Conf),
    ok = mini_s3:delete_bucket(BucketName, S3Conf),
    Content = proplists:get_value(content, GetResults),
    true = iolist_to_binary(Value) =:= Content,
    PutVersion = proplists:get_value(version_id, PutResults),
    GetVersion = proplists:get_value(version_id, GetResults),
    true = PutVersion =:= GetVersion,
    ContentLength = proplists:get_value(content_length, GetResults),
    true = iolist_size(Value) =:= list_to_integer(ContentLength), 
    ok.

t_stream_large_file_test(Config) ->
    % write a 50Mb file
    {ok, Filename} = generate_large_file(Config, 1024*1024*50),
    BucketName = "stream_bucket",
    Key1 = "stream_key",
    Key2 = "stream_key",
    S3Conf = test_config(),
    ok = mini_s3:create_bucket(BucketName, private, none, S3Conf),
    _PutResults1 = mini_s3:put_object(BucketName,
                                      Key1,
                                      {stream_from, {Filename, 128*1024}},
                                      [],
                                      [],
                                    S3Conf),
    _PutResults2 = mini_s3:put_object(BucketName,
                                      Key2,
                                      {stream_from, Filename},
                                      [],
                                      [],
                                      S3Conf),
    DownloadFName2 = large_file_path(Config) ++ ".dnwld2",
    DownloadFName3 = large_file_path(Config) ++ ".dnwld3",
    DownloadFName5 = large_file_path(Config) ++ ".dnwld5",
    DownloadFName6 = large_file_path(Config) ++ ".dnwld6",
    StrmOpts2 = [{stream_to_file, DownloadFName2}],
    StrmOpts3 = [
                 {stream_to_file, DownloadFName3},
                 {partial_download, [{part_size, 128 * 1024}]}
                ],
    StrmOpts5 = [{stream_to_file, DownloadFName5}],
    StrmOpts6 = [
                 {stream_to_file, DownloadFName6},
                 {partial_download, [{part_size, 256 * 1024}]}
                ],
    GetResults1 = mini_s3:get_object(BucketName, Key1, [], S3Conf),
    [_|_] = mini_s3:get_object(BucketName, Key1, StrmOpts2, S3Conf),
    [_|_] = mini_s3:get_object(BucketName, Key1, StrmOpts3, S3Conf),
    GetResults4 = mini_s3:get_object(BucketName, Key2, [], S3Conf),
    [_|_] = mini_s3:get_object(BucketName, Key2, StrmOpts5, S3Conf),
    [_|_] = mini_s3:get_object(BucketName, Key2, StrmOpts6, S3Conf),
    Content1 = proplists:get_value(content, GetResults1),
    Hash1 = crypto:hash(md5, Content1),
    {ok, Content2} = file:read_file(DownloadFName2),
    Hash2 = crypto:hash(md5, Content2),
    {ok, Content3} = file:read_file(DownloadFName3),
    Hash3 = crypto:hash(md5, Content3),
    Content4 = proplists:get_value(content, GetResults4),
    Hash4 = crypto:hash(md5, Content4),
    {ok, Content5} = file:read_file(DownloadFName5),
    Hash5 = crypto:hash(md5, Content5),
    {ok, Content6} = file:read_file(DownloadFName6),
    Hash6 = crypto:hash(md5, Content6),
    Hash1 = Hash2 = Hash3 = Hash4 = Hash5 = Hash6,
    [_|_] = mini_s3:delete_object(BucketName, Key1, S3Conf),
    [_|_] = mini_s3:delete_object(BucketName, Key2, S3Conf),
    ok = mini_s3:delete_bucket(BucketName, S3Conf),
    ok = file:delete(DownloadFName2),
    ok = file:delete(DownloadFName3),
    ok = file:delete(DownloadFName5),
    ok = file:delete(DownloadFName6),
    ok.

%%%------------------------------------------------------------------------
%%% Private Test Helper Methods
%%%------------------------------------------------------------------------

test_config() ->
    URI ="http://localhost:"++ integer_to_list(?FAKES3_PORT),
    mini_s3:new(fake_credentials(), URI, path).

fake_credentials() ->
    {credentials, baked_in, "123", "abc"}.

%%%------------------------------------------------------------------------
%%% Private
%%%------------------------------------------------------------------------

is_gem_installed() ->
    case os:find_executable("gem") of
        false ->
            ct:pal("*************************************~n"),
            ct:pal("* Ruby's gem command not installed! *~n"),
            ct:pal("*************************************~n"),
            false;
        _ ->
            true
    end.

get_fakes3_install_type(Config) ->
    case {is_fakes3_install_global(),is_fakes3_install_local(Config)} of
        {true, _} ->
            global;
        {_, true} ->
            local;
        {false, false} ->
            ok = install_fakes3_local(Config),
            local
    end.

is_fakes3_install_local(Config) ->
    filelib:is_dir(local_fakes3_bin_dir(Config)).

is_fakes3_install_global() ->
    case os:find_executable("fakes3") of
        false -> false;
        _     -> true
    end.

get_data_dir(Config) ->
    proplists:get_value(data_dir, Config).
    
local_fakes3_install_dir(Config) ->
    filename:join(get_data_dir(Config), "fakes3") ++ "/".

local_fakes3_bin_dir(Config) ->
    filename:join([local_fakes3_install_dir(Config), "bin"])++"/".

install_fakes3_local(Config) ->
    Dir = local_fakes3_install_dir(Config),
    Cmd = io_lib:format("gem install --install-dir ~p fakes3", [Dir]),
    Output = os:cmd(Cmd),
    ct:pal("Local install output: ~p~n",[Output]),
    ok.
    
-spec start_fakes3(global|local, list()) -> {ok,pid()} | ignore | {error,any()}.
start_fakes3(InstallType, Config) ->
    Root = filename:join(get_data_dir(Config), "fake_s3_root") ++ "/",
    ok = prepare_fakes3_root(Root),
    BaseCmd0 = "fakes3 --root \"" ++ Root,
    BaseCmd1 = "\" --port " ++ integer_to_list(?FAKES3_PORT),
    BaseCmd = BaseCmd0 ++ BaseCmd1,
    Args = case InstallType of
        global ->
            {cmd, BaseCmd};
        local ->
            Cmd = filename:join(local_fakes3_bin_dir(Config), BaseCmd),
            {cmd, Cmd, gem_home, local_fakes3_install_dir(Config)}
    end,
    fakes3_server:start(Args).

error_no_gem_or_fakes3() ->
    Msg = "*******************************************************\n"
          "* Skipping FakeS3 Test Suite.                         *\n"
          "* Either `gem` or `fakes3` be installed and on the    *\n"
          "* PATH to run this test suite.                        *\n"
          "*******************************************************\n",
    ct:pal(Msg),
    error_no_gem_or_fakes3_installed.

prepare_fakes3_root(Config) ->
    Dir = filename:join(get_data_dir(Config), "fakes3_root") ++ "/",
    ok = maybe_del_dir_all(Dir),
    ok = filelib:ensure_dir(Dir).

maybe_del_dir_all(Dir) ->
    case filelib:is_dir(Dir) of
        true ->
            del_dir_all(Dir);
        false ->
            false = filelib:is_file(Dir),
            ok
    end.

del_dir_all(Dir) ->            
    {ok, Filenames0} = file:list_dir_all(Dir),
    Filenames = [filename:join(Dir, F) || F <- Filenames0],
    lists:foreach(fun(Filename)->
                      case filelib:is_dir(Filename) of
                          true ->
                              del_dir_all(Filename);
                          false ->
                              ok = file:delete(Filename)
                      end
                  end,
                  Filenames),
    file:del_dir(Dir).


large_file_path(Config) ->
    filename:join([get_data_dir(Config), "test_files", "big_file.bin"]).

generate_large_file(Config, Size) ->
    FName = large_file_path(Config),
    case filelib:is_file(FName) andalso (filelib:file_size(FName) > Size) of
        true ->
            {ok, FName};
        false ->
            ok = filelib:ensure_dir(FName),
            file:delete(FName),
            {ok, File} = file:open(FName, [write, raw, binary]),
            generate_large_file1(FName, File, Size)
    end.

generate_large_file1(FName, File, Size) ->
    Bytes = crypto:rand_bytes(1024 *256),
    ok = file:write(File, Bytes),
    case filelib:file_size(FName) > Size of
        true ->
            {ok, FName};
        false ->
            generate_large_file1(FName, File, Size)
    end.
