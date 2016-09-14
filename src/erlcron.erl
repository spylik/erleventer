%% --------------------------------------------------------------------------------
%% File:    erlcron.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% @doc
%% Erlcron is the simple OTP periodic job scheduler.
%% @end
%% --------------------------------------------------------------------------------

-module(erlcron).

-define(NOTEST, true).
-ifdef(TEST).
    -compile(export_all).
-endif.

-include("utils.hrl").

% gen server is here
-behaviour(gen_server).

% gen_server api
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

% public api 
-export([
        start_link/1,
        stop/1,
        stop/2,
        add/5,
        cancel/1
    ]).

-define(SERVER(Id), 
    list_to_atom(lists:concat([Id, "_", ?MODULE]))
).

-type msgformat() :: term().
-type id() :: binary().
-type methods() :: 'cast' | 'call' | 'info'.

-record(events, {
        id      :: id(),
        freq    :: pos_integer(),
        pid     :: atom() | pid(),
        method  :: methods(),
        message :: msgformat(),
        tref    :: timer:tref()
    }).

-record(state, {
        etsname :: atom()
    }).

-type state() :: #state{}.

% ----------------------------- gen_server part --------------------------------

% @doc Start copy of erlcron and register it locally as $id_erlcron. 
% Erlcron works in milliseconds.
% - 1 hour = 3600000
% - 1 minute = 60000
% - 1 second = 1000
-spec start_link(Id) -> Result
    when 
        Id :: atom(),
        Result :: 'ignore' | {'error',_} | {'ok',pid()}.

start_link(Id) ->
    gen_server:start_link({local, ?SERVER(Id)}, ?MODULE, Id, []).

% @doc API for stop gen_server. Default is sync call.
-spec stop(Id) -> Result when 
    Id      :: atom(),
    Result  :: term().

stop(Id) ->
    stop(sync, Id).

% @doc API for stop gen_server. We support async casts and sync calls aswell.
-spec stop(SyncAsync, Id) -> Result when
    SyncAsync   :: 'sync' | 'async',
    Id          :: atom(),
    Result      :: term().

stop(sync, Id) ->
    gen_server:stop(?SERVER(Id));
stop(async, Id) ->
    gen_server:cast(?SERVER(Id), stop).

% @doc While init we going to create ets table
-spec init(Id) -> Result when 
    Id      :: atom(),
    Result  :: {'ok', state()}.

init(Id) ->
    EtsName = ?SERVER(Id),
    _Tid = ets:new(EtsName, [set, protected, {keypos, #events.id}, named_table]),
    
    {ok, #state{
            etsname=EtsName
        }
    }.

%--------------handle_call----------------

% @doc handle add events
handle_call({add, Freq, Pid, Method, Message}, _From, State = #state{etsname = EtsName}) ->
    Id = term_to_binary({Freq, Pid, Method, Message}),

    Ref = case ets:lookup(EtsName, Id) of
        [#events{tref = TRef}] -> 
            TRef;
        [] ->
            {ok, TRef} = cast_task(Freq, Pid, Method, Message),
            Task = #events{
                id = Id,
                freq = Freq,
                pid = Pid,
                method = method,
                message = Message,
                tref = TRef
            },
            ets:insert(EtsName, Task),
            TRef
    end,
    
    % create new key in timeref map
    {reply, Ref, State};

% handle_call for stop
handle_call(stop, _From, State) ->
    {stop, normal, State};

% handle_call for all other thigs
handle_call(Msg, _From, State) ->
    ?undefined(Msg),
    {reply, unmatched, State}.
%-----------end of handle_call-------------


%--------------handle_cast-----------------

% handle_cast for stop
handle_cast(stop, State) ->
    {stop, normal, State};

% handle_cast for all other thigs
handle_cast(Msg, State) ->
    ?undefined(Msg),
    {noreply, State}.
%-----------end of handle_cast-------------

%--------------handle_info-----------------

%% handle_info for all other thigs
handle_info(Msg, State) ->
    ?undefined(Msg),
    {noreply, State}.
%-----------end of handle_info-------------

% @doc on terminate going to cancel all timers before die
terminate(Reason, State = #state{etsname = EtsName}) ->
    lists:map(
        fun(#events{tref = TRef}) ->
            timer:cancel(TRef)
        end, ets:tab2list(EtsName)
    ),
    {noreply, Reason, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% ============================= end of gen_server part =========================

% @doc interface for sending message with different methods
-spec cast_task (Freq, Pid, Method, Message) -> Result when
    Freq    :: pos_integer(),
    Pid     :: atom() | pid(),
    Method  :: methods(),
    Message :: msgformat(),
    Result  :: {ok, timer:tref()}.

cast_task(Freq, Pid, 'info', Message) ->
    timer:send_interval(Freq, Pid, Message);

cast_task(Freq, Pid, 'cast', Message) ->
    timer:apply_interval(Freq, gen_server, 'cast', [Pid,Message]);

cast_task(Freq, Pid, 'call', Message) ->
    timer:apply_interval(Freq, gen_server, 'call', [Pid,Message]).

% @doc interface for add new event
-spec add(Id, Freq, Pid, Method, Message) -> Result when
    Id      :: atom(),
    Freq    :: pos_integer(),
    Pid     :: atom() | pid(),
    Method  :: methods(),
    Message :: msgformat(),
    Result  :: {ok, timer:tref()}.

add(Id, Freq, Pid, Method, Message) ->
    gen_server:call(?SERVER(Id), {add, Freq, Pid, Method, Message}).

% @doc delete
-spec cancel(Parameters) -> Result when
    Parameters :: [
        {'id', atom()} | 
        {'freq', pos_integer()} | 
        {'pid', Pid} | 
        {'method', methods()} |
        {'message', msgformat()}
    ],
    Pid :: atom() | pid(),
    Result :: 'ok'.

cancel(_Parameters) -> ok.

% %@doc interface for delete event
