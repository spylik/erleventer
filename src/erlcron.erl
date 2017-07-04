%% --------------------------------------------------------------------------------
%% File:    erlcron.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% @doc
%% Erlcron is the simple wraper around `timer:send_after` for easy management periodic events.
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
        add/6,
        cancel/2
    ]).

-define(SERVER(Id),
    list_to_atom(lists:concat([Id, "_", ?MODULE]))
).

-type process()     :: pid() | atom().
-type msgformat()   :: term().
-type methods()     :: 'cast' | 'call' | 'info'.
-type parameters()  :: {'freq', pos_integer()} |
                       {'pid', process()} |
                       {'method', methods()} |
                       {'message', msgformat()}.

-record(events, {
        tag     :: term() | '_',
        freq    :: pos_integer() | '_',
        pid     :: atom() | pid() | '_',
        method  :: methods() | '_',
        message :: msgformat() | '_',
        tref    :: timer:tref() | '_'
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
    _Tid = ets:new(EtsName, [set, protected, {keypos, #events.tref}, named_table]),

    {ok, #state{
            etsname=EtsName
        }
    }.

%--------------handle_call----------------

% @doc callbacks for gen_server handle_call.
-spec handle_call(Message, From, State) -> Result when
    Message :: Add | Cancel,
    Add     :: {'add', Freq, Pid, Method, Message, Tag},
    Cancel  :: {'cancel', parameters()},
    Freq    :: pos_integer(),
    Pid     :: process(),
    Method  :: methods(),
    Message :: msgformat(),
    From    :: {pid(), Tag},
    Tag     :: term(),
    State   :: state(),
    Reply   :: {'added', timer:tref()} | {'exists', timer:tref()} | [{'canceled', timer:tref()}] | [],
    Result  :: {reply, Reply, State}.

% @doc handle add events
handle_call({add, Freq, Pid, Method, Message, Tag}, _From, State = #state{etsname = EtsName}) ->
    MS = [{#events{'tag' = Tag, 'freq' = Freq, 'pid' = Pid, 'method' = Method, 'message' = Message, 'tref' = '_'}, [], ['$_']}],

    Reply = case ets:select(EtsName, MS) of
        [#events{tref = TRef}] ->
            {'exists', TRef};
        [] ->
            {ok, TRef} = cast_task(Freq, Pid, Method, Message),
            Task = #events{
                tag = Tag,
                freq = Freq,
                pid = Pid,
                method = Method,
                message = Message,
                tref = TRef
            },
            ets:insert(EtsName, Task),
            {'added',TRef}
    end,

    % create new key in timeref map
    {reply, Reply, State};

handle_call({cancel, Parameters}, _From, State = #state{etsname = EtsName}) ->
    Tag =
        case lists:keyfind('tag', 1, Parameters) of
            {'tag', Val0} -> Val0;
            false -> '_'
        end,
    Freq =
        case lists:keyfind('freq', 1, Parameters) of
            {'freq', Val1} -> Val1;
            false -> '_'
        end,
    Pid =
        case lists:keyfind('pid', 1, Parameters) of
            {'pid', Val2} -> Val2;
            false -> '_'
        end,
    Method =
        case lists:keyfind('method', 1, Parameters) of
            {'method', Val3} -> Val3;
            false -> '_'
        end,
    Message =
        case lists:keyfind('message', 1, Parameters) of
            {'message', Val4} -> Val4;
            false -> '_'
        end,
    MS = [{#events{'tag' = Tag, 'freq' = Freq, 'pid' = Pid, 'method' = Method, 'message' = Message, 'tref' = '_'}, [], ['$_']}],
    Gone = lists:map(
        fun(#events{tref = TRef}) ->
            _ = timer:cancel(TRef),
            ets:delete(EtsName, TRef),
            {'canceled', TRef}
        end, ets:select(EtsName, MS)
    ), {reply, Gone, State};


% handle_call for all other thigs
handle_call(Msg, _From, State) ->
    ?undefined(Msg),
    {reply, unmatched, State}.
%-----------end of handle_call-------------


%--------------handle_cast-----------------

% @doc callbacks for gen_server handle_call.
-spec handle_cast(Message, State) -> Result when
    Message :: 'stop',
    State   :: state(),
    Result  :: {noreply, State} | {stop, normal, State}.

% handle_cast for stop
handle_cast(stop, State) ->
    {stop, normal, State};

% handle_cast for unexpected things
handle_cast(Msg, State) ->
    ?undefined(Msg),
    {noreply, State}.
%-----------end of handle_cast-------------

%--------------handle_info-----------------

% @doc callbacks for gen_server handle_info.
-spec handle_info(Message, State) -> Result when
    Message :: term(),
    State   :: term(),
    Result  :: {noreply, State}.

%% handle_info for all other thigs
handle_info(Msg, State) ->
    ?undefined(Msg),
    {noreply, State}.
%-----------end of handle_info-------------

% @doc call back for gen_server terminate
-spec terminate(Reason, State) -> term() when
    Reason  :: 'normal' | 'shutdown' | {'shutdown',term()} | term(),
    State   :: term().

terminate(Reason, State = #state{etsname = EtsName}) ->
    _ = lists:map(
        fun(#events{tref = TRef}) ->
            timer:cancel(TRef)
        end, ets:tab2list(EtsName)
    ),
    {noreply, Reason, State}.

% @doc call back for gen_server code_change
-spec code_change(OldVsn, State, Extra) -> Result when
    OldVsn      :: Vsn | {down, Vsn},
    Vsn         :: term(),
    State       :: term(),
    Extra       :: term(),
    Result      :: {ok, NewState},
    NewState    :: term().

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% ============================= end of gen_server part =========================

% @doc interface for sending message with different methods
-spec cast_task (Freq, Pid, Method, Message) -> Result when
    Freq    :: pos_integer(),
    Pid     :: process(),
    Method  :: methods(),
    Message :: msgformat(),
    Result  :: {ok, timer:tref()}.

cast_task(Freq, Pid, 'info', Message) ->
    timer:send_interval(Freq, Pid, Message);

cast_task(Freq, Pid, 'cast', Message) ->
    timer:apply_interval(Freq, gen_server, 'cast', [Pid,Message]);

cast_task(Freq, Pid, 'call', Message) ->
    timer:apply_interval(Freq, gen_server, 'call', [Pid,Message]).

% @doc interface for add new event (notag)
-spec add(Id, Freq, Pid, Method, Message) -> Result when
    Id      :: atom(),
    Freq    :: pos_integer(),
    Pid     :: process(),
    Method  :: methods(),
    Message :: msgformat(),
    Result  :: {ok, timer:tref()}.
add(Id, Freq, Pid, Method, Message) ->
    add(Id, Freq, Pid, Method, Message, 'undefined').

% @doc interface for add new event
-spec add(Id, Freq, Pid, Method, Message, Tag) -> Result when
    Id      :: atom(),
    Freq    :: pos_integer(),
    Pid     :: process(),
    Method  :: methods(),
    Message :: msgformat(),
    Tag     :: term(),
    Result  :: {ok, timer:tref()}.

add(Id, Freq, Pid, Method, Message, Tag) ->
    gen_server:call(?SERVER(Id), {add, Freq, Pid, Method, Message, Tag}).

% @doc delete
-spec cancel(Id, Parameters) -> Result when
    Id          :: atom(),
    Parameters  :: [parameters()],
    Result      :: 'ok'.

cancel(Id, Parameters) ->
    gen_server:call(?SERVER(Id), {cancel, Parameters}).



% %@doc interface for delete event
