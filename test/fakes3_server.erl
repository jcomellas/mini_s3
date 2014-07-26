-module(fakes3_server).

-export([start_fakes3/1]).

-behaviour(gen_server).

% API
-export([start/1]).
-export([stop/0]).

% gen_server callbacks
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([terminate/2]).
-export([handle_info/2]).
-export([code_change/3]).

%%
%% API
%%

-spec start(Cmd::string()) -> {ok, pid()}.
start(Cmd) ->
    gen_server:start({local, ?MODULE}, ?MODULE, Cmd, []).

-spec stop() -> ok.
stop() ->
    gen_server:call(?MODULE, stop).

%%
%% gen_server callbacks
%%

init(Args) ->
    Port = start_fakes3(Args),
    {ok, Port}.

handle_call(stop, _From, {port, Port, pid, OSPid}) ->
    ok = stop_fakes3({port, Port, pid, OSPid}),
    {stop, normal, ok, {port, Port, pid, OSPid}}.

handle_info(_Info, State) ->
    {noreply, State}.

handle_cast(_, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    {ok, State}.

code_change(_, State, _) ->
    {ok, State}.

%%
%% Private 
%%

-spec start_fakes3(Cmd::string()) -> port().
start_fakes3({cmd, Cmd}) ->
    Port = open_port({spawn, Cmd}, []),
    {os_pid, OSPid} = erlang:port_info(Port, os_pid),
    {port, Port, pid, OSPid};
start_fakes3({cmd, Cmd, gem_home, GemHome}) ->
    Port = open_port({spawn, Cmd}, [{env, [{"GEM_HOME", GemHome}]}]),
    {os_pid, OSPid} = erlang:port_info(Port, os_pid),
    {port, Port, pid, OSPid}.

stop_fakes3({port, Port, pid, OSPid}) ->
    port_close(Port),
    case os:type() of 
        {unix, _}  -> os:cmd(io_lib:format("kill -9 ~p", [OSPid]));
        {win32, _} -> os:cmd(io_lib:format("taskkill /PID ~p", [OSPid]))
    end,
    ok.
