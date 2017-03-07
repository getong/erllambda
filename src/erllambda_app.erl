%%%---------------------------------------------------------------------------
%% @doc erllambda_app - Erllambda Application behavior
%%
%% This module implements the Erlang <code>application</code> behavior, and
%% starts the simple http server endpoint used by the javascript driver.
%%
%%
%% @copyright 2017 Alert Logic, Inc
%% @author Paul Fisher <pfisher@alertlogic.com>
%%%---------------------------------------------------------------------------
-module(erllambda_app).
-author('Paul Fisher <pfisher@alertlogic.com>').

-behavior(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    Routes = [
              {"/eee/v1/[...]", erllambda_v1_http, []}
             ],
    Dispatch = cowboy_router:compile( [{'_', Routes}] ),
    lists:foreach( fun( Protocol ) ->
                           {ok, _} = cowboy_start( Protocol, Dispatch )
                   end, protocols() ),
    erllambda_sup:start_link().


%%--------------------------------------------------------------------
stop(_State) ->
    lists:foreach( fun( Protocol ) -> cowboy:stop_listener( Protocol ) end,
                   protocols() ).


%%====================================================================
%% Internal functions
%%====================================================================
protocols() ->
    {ok, Protocols} = application:get_env( erllambda, listen_protocols ),
    [to_atom(P)
     || P <- string:tokens(
               os:getenv( "ERLLAMBDA_LISTEN_PROTOCOLS", Protocols ), ", " )].

cowboy_start( tcp, Dispatch ) ->
    {ok, ConfigPort} = application:get_env( erllambda, tcp_port ),
    Port = os:getenv( "ERLLAMBDA_TCP_PORT", ConfigPort ),
    Options = [{port, to_integer(Port)}],
    cowboy:start_clear( tcp, 1, Options, #{env => #{dispatch => Dispatch}} );
cowboy_start( unix, Dispatch ) ->
    %% socket file configured needs to be cleared out if we are to
    %% start and the directory needs to exist
    {ok, File} = application:get_env( erllambda, socket_file ),
    _ = file:delete( File ),
    ok = filelib:ensure_dir( File ),
    %% the following sequence is neccessary because cowboy does not
    %% permit the ifaddr option to pass through to ranch so that it
    %% can establish the unix domain socket itself
    %%
    %% Options = [{ifaddr, {local, File}}],
    TcpOptions = [binary, {nodelay, true}, {backlog, 1024},
                  {send_timeout, 30000}, {send_timeout_close, true},
                  {active, false}, {packet, raw},
                  {reuseaddr, true}, {ifaddr, {local, File}}],
    {ok, Socket} = gen_tcp:listen( 0, TcpOptions ),
    Options = [{socket, Socket}],
    cowboy:start_clear( unix, 1, Options, #{env => #{dispatch => Dispatch}} ).

to_atom( V ) when is_atom(V) -> V;
to_atom( V ) when is_list(V) -> list_to_atom( V );
to_atom( V ) when is_binary(V) -> binary_to_atom( V, latin1 ).

to_integer( V ) when is_integer(V) -> V;
to_integer( V ) when is_list(V) -> list_to_integer(V);
to_integer( V ) when is_binary(V) -> binary_to_integer(V).
    
