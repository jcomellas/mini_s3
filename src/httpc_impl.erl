-module(httpc_impl).

-export([start/0]).
-export([send_req/5]).

-include("internal.hrl").
-include_lib("lhttpc/include/lhttpc_types.hrl").

-type chunk_size_bytes() :: pos_integer().
-type filename()         :: file:filename().

-spec start() -> ok.
start() ->
    ok = lhttpc:start(),
    ok.

-spec send_req(URI    :: string(),
               Method :: mini_s3:method(),
               Hdrs   :: headers(),
               Body   :: iolist()
                       | {stream_from, filename()}
                       | {stream_from, {filename(), chunk_size_bytes()}},
               Opts   :: mini_s3:httpc_opts()) ->  
    mini_s3:response() | {error, any()}.
send_req(URI, Method, Hdrs, {stream_from, {Filename, ChunkSize}}, Opts) ->
    {Timeout, Opts1} = get_timeout(Opts),
    {ok, File} = file:open(Filename, [read, binary, raw]),
    case file:read(File, ChunkSize) of
        {ok, Data} ->
            {ok, State} = lhttpc:request(URI,
                                          Method,
                                          Hdrs,
                                          Data,
                                          Timeout,
                                          [{partial_upload, infinity}]++Opts1),
            stream_file(File, ChunkSize, {ok, Data}, State);
        eof ->
             % On an empty file, don't try to stream.
             lhttpc:request(URI, Method, Hdrs, [], Timeout);
        {error, Error} ->
            {error, Error}
    end;
send_req(URI, put, Hdrs, {stream_from, Filename}, Opts) ->
    Body = {stream_from, {Filename, ?DEFAULT_CHUNK_SIZE}},
    send_req(URI, put, Hdrs, Body, Opts);
send_req(URI, get, Hdrs, Body, [_|_] = Opts) ->
    {Timeout, Opts1} = get_timeout(Opts),
    case proplists:get_value(stream_to_file, Opts) of
        undefined ->
            Resp = lhttpc:request(URI, get, Hdrs, Body, Timeout, Opts1),
            wrap_response(Resp);
        Filename ->
            Opts2 = proplists:delete(stream_to_file, Opts1),
            partial_download(URI, Hdrs, Filename, Timeout, Opts2)
    end;
send_req(URI, Method, Headers, Body, Opts) ->
    {Timeout, Opts1} = get_timeout(Opts),
    Resp = lhttpc:request(URI, Method, Headers, Body, Timeout, Opts1),
    wrap_response(Resp).

-spec partial_download(httpc:url(), headers(), file:filename(), pos_integer(), proplists:proplist()) ->
    mini_s3:response().
partial_download(URI, Hdrs, Filename, Timeout, Opts) ->
    Opts1 = case proplists:is_defined(partial_download, Opts) of
        true ->
            Opts;
        false ->
            [{partial_download, []} | Opts]
    end,
    {ok, File} = file:open(Filename, [write, binary, raw]),
    Resp = lhttpc:request(URI, get, Hdrs, [], Timeout, Opts1),
    {ok, {{StatusCode, _Reason}, RespHdrs, Pid}} =  Resp,
    case StatusCode >= 200 andalso StatusCode < 300 of
        true  ->
            recv_partial(File, StatusCode, Pid, RespHdrs);
        false ->
            {error, {http_status, StatusCode}}
    end. 

-spec recv_partial(file:file(), pos_integer(), pid(), minis3:canonical_headers()) ->
    mini_s3:response().
recv_partial(File, Status, Pid, Headers) ->
    case lhttpc:get_body_part(Pid) of
        {ok, {http_eob, Trailers}} ->
            _ = file:close(File),
            {ok, {Status, Headers++Trailers, <<>>}};
        {ok, Bin} ->
            ok = file:write(File, Bin),
            recv_partial(File, Status, Pid, Headers);
        {error, Reason} ->
            _ = file:close(File),
            {error, Reason}
    end.

get_timeout(Opts) ->
    NewOpts = proplists:delete(timeout, Opts),
    Timeout = proplists:get_value(timeout, Opts, ?DEFAULT_HTTP_TIMEOUT),
    {Timeout, NewOpts}.

-spec stream_file(File      :: file:file(),
                  ChunkSize :: pos_integer(),
                  Data      :: {ok, [byte()]} | eof | {error, any()},
                  State     :: any()) ->
    ok | {error, any()}.
stream_file(File, _ChunkSize, {error, Reason}, State) ->
    {ok, _} = lhttpc:send_body_part(State, http_eob, infinity),
    _ = file:close(File),
    {error, Reason};
stream_file(File, ChunkSize, {ok, Data}, State) ->
    {ok, NextState} = lhttpc:send_body_part(State, [Data], infinity),
    Read = file:read(File, ChunkSize),
    stream_file(File, ChunkSize, Read, NextState);
stream_file(File, _ChunkSize, eof, State) ->
    _ = file:close(File),
    Resp = lhttpc:send_body_part(State, http_eob, infinity),
    wrap_response(Resp).

-spec wrap_response(lhtttpc:result()) ->
    mini_s3:httpresponse().
wrap_response({ok, {{Code, _Reason}, Hdrs, Payload}}) ->
    {ok, {Code, Hdrs, Payload}};
wrap_response({error,Reason}) ->
    {error, Reason}.
