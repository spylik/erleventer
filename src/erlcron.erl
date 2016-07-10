%% --------------------------------------------------------------------------------
%% File:    erlcron.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% @doc
%% Erlcron is the simple OTP job scheduler.
%% @end
%% --------------------------------------------------------------------------------

-module(erlcron).

-define(NOTEST, true).
-ifdef(TEST).
    -compile(export_all).
-endif.

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
		add/5	% todo different remove
    ]).

-define(SERVER(Id), 
	mlibs:build_atom_key([Id, ?MODULE])
).

-type methods() :: 'cast' | 'call' | 'info'.
-type msgformat() :: mfa() | term().
-type id() :: binary().

-record(events, {
		id :: id(),
		freq :: pos_integer(),
		pid :: atom() | pid(),
		method :: methods(),
		message :: msgformat()
	}).

-record(state, {
		etsname	:: atom(),
		timeref :: #{id() => reference()}
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
-spec stop(Id) -> Reply
	when 
        Id :: atom(),
		Reply :: term().

stop(Id) ->
	stop(sync, Id).

% @doc API for stop gen_server. We support async casts and sync cals aswell.
-spec stop(SyncAsync, Id) -> Reply
	when
		SyncAsync :: 'sync' | 'async',
        Id :: atom(),
		Reply :: term().

stop(sync, Id) ->
	gen_server:call(?SERVER(Id), stop);
stop(async, Id ->
	gen_server:cast(?SERVER(Id), stop).

% @doc While init we going to create ets table
-spec init(Id) -> Reply 
	when 
		Id :: atom(),
		Reply :: {'ok', state()}.

init(Id) ->
	EtsName = ?SERVER(Id),
	_Tid = ets:new(EtsName, [set, protected, {keypos, #events.id}, named_table]),
	
	{ok, #state{
			etsname=EtsName,
			timeref=#{} % going to inicialyze empty map
		}
	}.

%--------------handle_call----------------

% @doc handle add events
handle_call({add, Freq, Pid, Method, Message}, _From, State = #state{etsname = EtsName, timeref = TimeRef}) ->
	Id = term_to_binary({Freq, Pid, Method, Message}),
	Task = #events{
		id = Id,
		freq = Freq,
		pid = Pid,
		method = Method,
		message = Message
	},
	ets:insert(EtsName, Task),
	
	% check maybe we already have reference for this task
	Ref = maps:get(Id, TimeRef ,undefined), 

	% first call we always fire immidiatly (if we do not have reference)
	_ = case Ref of
		undefined -> self() ! {{id, Id}, {freq, Freq}, {server_pid, Pid}, {method, Method}, {message, Message}};
		_ -> true
	end,

	% create new key in timeref map
	{reply, {created, Id}, 
		State#state{
			timeref = TimeRef#{Id => Ref}
		}
	};

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

% we handle here all send_after events, forward it to destination and cast new send_after for same task
handle_info({{id, Id}, {freq, Freq}, {server_pid, Pid}, {method, Method}, {message, Msg}}, #state{timeref = Timeref} = State) ->
	% if we have timer, we going to cancel it
	_ = case maps:get(Id, Timeref) of 
		undefined -> ok;
		OldRef -> erlang:cancel_timer(OldRef)
	end,

	% cast new send_after to self()	
	NewRef = erlang:send_after(Freq, self(), {{id, Id}, {freq, Freq}, {server_pid, Pid}, {method, Method}, {message, Msg}}),

	% if we generating message content from external function
	Message = case Msg of
		{M, F, A} when is_function(F) -> erlang:apply(M,F,A);
		_ -> Msg
	end,

	% sending message
	case Method of 
		cast -> gen_server:cast(Pid, Message);
		call -> gen_server:call(Pid, Message);
		info -> Pid ! Message
	end,
    {noreply, 
		State#state{
			timeref = Timeref#{Id := NewRef}
		}
	};

%% handle_info for all other thigs
handle_info(Msg, State) ->
    ?undefined(Msg),
    {noreply, State}.
%-----------end of handle_info-------------


terminate(Reason, State) ->
    {noreply, Reason, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% ============================= end of gen_server part =========================

% @doc interface for add new event
-spec add(Id, Freq, Pid, Method, Message) -> {ok, State} when
	Id :: markets_sup:market(),
	Freq :: pos_integer(),
	Pid :: atom() | pid(),
	Method :: methods(),
	Message :: msgformat(),
	State :: state().

add(Id, Freq, Pid, Method, Message) ->
	gen_server:call(?SERVER(Id), {add, Freq, Pid, Method, Message}).

% %@doc interface for delete event
