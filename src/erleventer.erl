%% --------------------------------------------------------------------------------
%% File:    erleventer.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% @doc
%% Erleventer is the simple wraper around `timer:send_after` for easy management periodic events.
%% @end
%% --------------------------------------------------------------------------------

-module(erleventer).

-define(NOTEST, true).
-ifdef(TEST).
    -compile(export_all).
-endif.

-include("erleventer.hrl").

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
        add_send_message/5,
        add_send_message/6,
        add_fun_apply/3,
        add_fun_apply/4,
        cancel/2
    ]).

-define(SERVER(Id),
    list_to_atom(lists:concat([Id, "_", ?MODULE]))
).

% =============================== public api part ===============================

% @doc Start copy of erleventer and register it locally as $id_erleventer.
% Erleventer works in milliseconds scope.
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


% @doc interface for add new send_message event (notag)
-spec add_send_message(Id, Freq, Pid, Method, Message) -> Result when
    Id      :: atom(),
    Freq    :: pos_integer(),
    Pid     :: process(),
    Method  :: send_method(),
    Message :: message(),
    Result  :: {ok, timer:tref()}.

add_send_message(Id, Freq, Pid, Method, Message) ->
    add_send_message(Id, Freq, Pid, Method, Message, 'undefined').


-spec add_send_message(Id, Freq, Pid, Method, Message, Tag) -> Result when
    Id      :: atom(),
    Freq    :: pos_integer(),
    Pid     :: process(),
    Method  :: send_method(),
    Message :: message(),
    Tag     :: term(),
    Result  :: {ok, timer:tref()}.

add_send_message(Id, Freq, Pid, Method, Message, Tag) ->
    gen_server:call(?SERVER(Id), {?FUNCTION_NAME, Freq, Pid, Method, Message, Tag}).


% @doc interface for add new function for pereodic execution
-spec add_fun_apply(Id, Freq, Fun, Arguments) -> Result when
    Id          :: atom(),
    Freq        :: pos_integer(),
    Fun         :: fun(),
    Arguments   :: [term()],
    Result      :: {ok, timer:tref()}.

add_fun_apply(Id, Freq, Arguments, Fun) ->
    add_fun_apply(Id, Freq, Fun, Arguments, 'undefined').


-spec add_fun_apply(Id, Freq, Fun, Arguments, Tag) -> Result when
    Id          :: atom(),
    Freq        :: pos_integer(),
    Fun         :: fun(),
    Arguments   :: [term()],
    Tag         :: term(),
    Result      :: {ok, timer:tref()}.

add_fun_apply(Id, Freq, Fun, Arguments, Tag) ->
    gen_server:call(?SERVER(Id), {?FUNCTION_NAME, Freq, Fun, Arguments, Tag}).


% @doc delete
-spec cancel(Id, Parameters) -> Result when
    Id          :: atom(),
    Parameters  :: [parameters()],
    Result      :: 'ok'.

cancel(Id, Parameters) ->
    gen_server:call(?SERVER(Id), {cancel, Parameters}).


% %@doc interface for delete event


% @doc While init we going to create ets table
-spec init(Id) -> Result when
    Id      :: atom(),
    Result  :: {'ok', state()}.

init(Id) ->
    EtsName = ?SERVER(Id),
    _Tid = ets:new(EtsName, [set, protected, {keypos, #task.tref}, named_table]),

    {ok, #state{
            etsname=EtsName
        }
    }.

%--------------handle_call----------------

% @doc callbacks for gen_server handle_call.
-spec handle_call(Message, From, State) -> Result when
    Message     :: Add | Cancel,
    Add         :: {'add_send_message', Freq, Pid, Method, Message, Tag}
                 | {'add_fun_apply', Freq, Fun, Arguments, Tag},
    Cancel      :: {'cancel', parameters()},
    Freq        :: pos_integer(),
    Pid         :: process(),
    Fun         :: fun(),
    Method      :: send_method(),
    Message     :: message(),
    From        :: {pid(), Tag},
    Tag         :: term(),
    State       :: state(),
    Reply       :: {'added', timer:tref()}
                 | {'exists', timer:tref()}
                 | {'re_scheduled', timer:tref()}
                 | [{'canceled', timer:tref()} | {'re_scheduled', timer:tref()}]
                 | [],
    Result      :: {reply, Reply, State}.

% @doc handle add events
handle_call({'add_send_message', Freq, Pid, Method, Message, Tag}, _From, State = #state{etsname = EtsName} = State) ->
    MS = [{#task{'pid' = Pid, 'method' = Method, 'message' = Message, _ = '_'}, [], ['$_']}],

    Reply = case ets:select(EtsName, MS) of
        [Task] ->
            add_freq(Task, Freq, State);
        [] ->
            CastFun = fun(TargetFreq) -> cast_task(TargetFreq, Pid, Method, Message) end,
            {ok, TRef} = erlang:apply(CastFun, [Freq]),
            Task = #task{
                freq = #{Freq => 1},
                pid = Pid,
                method = Method,
                message = Message,
                tag = Tag,
                tref = TRef,
                cast_fun = CastFun
            },
            ets:insert(EtsName, Task),
            {'added',TRef}
    end,
    {reply, Reply, State};


handle_call({'add_fun_apply', Freq, Fun, Arguments, Tag}, _From, State = #state{etsname = EtsName} = State) ->
    MS = [{#task{'function' = Fun, 'arguments' = Arguments, _ = '_'}, [], ['$_']}],

    Reply = case ets:select(EtsName, MS) of
        [Task] ->
            add_freq(Task, Freq, State);
        [] ->
            CastFun = fun(TargetFreq) -> cast_task(TargetFreq, self(), 'info', {'cast_safe', Fun, Arguments}) end,
            {ok, TRef} = erlang:apply(CastFun, [Freq]),
            Task = #task{
                freq = #{Freq => 1},
                function = Fun,
                arguments = Arguments,
                tag = Tag,
                tref = TRef,
                cast_fun = CastFun
            },
            ets:insert(EtsName, Task),
            {'added', TRef}
    end,
    {reply, Reply, State};


handle_call({cancel, CancelOps}, _From, State = #state{etsname = EtsName} = State) ->
    MS = [{
            #task{
                'tag' = build_spec_value('tag', CancelOps),
                'pid' = build_spec_value('pid', CancelOps),
                'method' = build_spec_value('method', CancelOps),
                'message' = build_spec_value('message', CancelOps),
                'function' = build_spec_value('function', CancelOps),
                'module' = build_spec_value('module', CancelOps),
                'arguments' = build_spec_value('arguments', CancelOps),
                'tag' = build_spec_value('tag', CancelOps),
                'tref' = '_'
            }, [], ['$_']
          }],
    Freq = build_spec_value('freq', CancelOps),
    Gone = lists:map(
        fun
            (#task{tref = TRef} when Freq =:= '_') ->
                _ = timer:cancel(TRef),
                ets:delete(EtsName, TRef),
                {'canceled', TRef};
            (Task) ->
                remove_freq(Task, FreqToDelete, State)
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
    Message :: {'cast_safe', fun(), [term()]},
    State   :: term(),
    Result  :: {noreply, State}.

handle_info({'cast_safe', Fun, Arguments}, State) ->
    _ = spawn(fun() -> erlang:apply(Fun, Arguments)),
    {noreply, State};

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
        fun(#task{tref = TRef}) ->
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
-spec cast_task(Freq, Pid, Method, Message) -> Result when
    Freq    :: frequency(),
    Pid     :: process(),
    Method  :: send_method(),
    Message :: message(),
    Result  :: {ok, timer:tref()}.

cast_task(Freq, Pid, 'info', Message) ->
    timer:send_interval(Freq, Pid, Message);

cast_task(Freq, Pid, 'cast', Message) ->
    timer:apply_interval(Freq, gen_server, 'cast', [Pid,Message]);

cast_task(Freq, Pid, 'call', Message) ->
    timer:apply_interval(Freq, gen_server, 'call', [Pid,Message]).


% @doc add frequency - reschedule event in case of target freq is less than what we have or update counter
-spec add_freq(Task, NewFreq, State) -> Result when
    Task    :: task(),
    NewFreq :: frequency(),
    State   :: state(),
    Result  :: {'exists', timer:tref()}
            |  {'re_scheduled', timer:tref()}.

add_freq(#task{freq = FreqMap, cast_fun = CastFun, tref = TRef} = Task, NewFreq, #state{etsname = EtsName}) ->
    case maps:get(NewFreq, FreqMap, 'undefined') of
        'undefined' ->
            case NewFreq < hd(lists:sort(maps:keys(FreqMap))) of
                true ->
                    NewTRef = recast(Task, NewFreq),
                    ets:delete(EtsName, TRef),
                    ets:insert(
                        EtsName,
                        Task#task{
                          freq = maps:put(NewFreq, 1, FreqMap),
                          tref = NewTRef
                         }
                    ),
                    {'re_scheduled', NewTRef};
                false ->
                    ets:insert(
                      EtsName,
                      Task#task{
                        freq = maps:put(NewFreq, 1, FreqMap)
                       }
                    ),
                    {'exists', TRef}
            end;
        Qty ->
            ets:insert(
              EtsName,
              Task#task{
                freq = maps:put(NewFreq, Qty + 1, FreqMap)
               }
            ),
            {'exists', TRef}
    end.


% @doc recast task with new frequency
-spec recast(Task, NewFreq) -> Result when
      Task      :: task(),
      NewFreq   :: frequency(),
      Result    :: timer:tref().

recast(#task{cast_fun = CastFun, tref = TRef}, NewFreq) ->
    timer:cancel(TRef),
    {ok, NewTRef} = erlang:apply(CastFun, [NewFreq]),
    NewTRef.


% @doc remove frequency - reschedule event in case of target freq is less than what we have or update counter
-spec remove_freq(Task, FreqToDelete, State) -> Result when
    Task            :: task(),
    FreqToDelete    :: frequency(),
    State           :: state(),
    Result          :: {'not_found', frequency()}
                    |  {'canceled', timer:tref()}
                    |  {'re_scheduled', frequency(), timer:tref()}
                    |  {'frequency_removed', frequency()}

remove_freq(#task{freq = FreqMap, cast_fun = CastFun, tref = TRef} = Task, FreqToDelete, #state{etsname = EtsName}) ->
    case maps:get(FreqToDelete, FreqMap, 'undefined') of
        'undefined' ->
            {'not_found', FreqToDelete};
        1 ->
            NeedRescedule = lists:min(maps:keys(FreqMap)) =:= FreqToDelete,
            case NeedRescedule of
                true when map_size(FreqMap) =:= 1 ->
                    timer:cancel(TRef),
                    ets:delete(EtsName, TRef),
                    {'canceled', TRef};
                true ->
                    timer:cancel(TRef),
                    NewFreqMap = maps:remove(FreqToDelete, FreqMap),
                    NewFreq = lists:min(maps:keys(FreqMap))
                    NewTRef = recast(Task, NewFreq),
                    ets:delete(EtsName, TRef),
                    ets:insert(
                        EtsName,
                        Task#task{
                          freq = NewFreqMap,
                          tref = NewTRef
                         }
                    ),
                    {'re_scheduled', NewFreq, NewTRef};
                false ->
                    ets:insert(
                      EtsName,
                      Task#task{
                        freq = maps:remove(FreqToDelete, FreqMap)
                       }
                    ),
                    {'exists', TRef}
            end;
        Qty ->
            ets:insert(
              EtsName,
              Task#task{
                freq = maps:put(NewFreq, Qty + 1, FreqMap)
               }
            ),
            {'exists', TRef}
    end.


% @doc build value by given key for matchspec
-spec build_spec_value(Key, CancelOps) -> Result when
        Key         :: 'freq' | 'pid' | 'method' | 'message' | 'function' | 'module' | 'arguments' | 'tag',
        CancelOps   :: cancel_ops().

build_spec_value(Key, CancelOps) when is_list(CancelOps) ->
        case lists:keyfind(Key, 1, CancelOps) of
            {Key, Val} -> Val;
            false -> '_'
        end;
build_spec_value(Key, CancelOps) when is_map(CancelOps) ->
    maps:get(Key, CancelOps, '_').

