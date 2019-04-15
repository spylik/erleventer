%% --------------------------------------------------------------------------------
%% File:    erleventer.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% @doc
%% Erleventer is the simple wraper around `timer:send_after` for easy management periodic events.
%% todo:
%% 1. rid from timer, switch to erlang:send_after
%% 2. track last_event_time
%% 3. during changing frequency calculate time for the next event based on NewFreq and last_event_time
%% 4. more flexible api for registering name
%% @end
%% --------------------------------------------------------------------------------

-module(erleventer).

-define(NOTEST, true).
-ifdef(TEST).
    -compile(export_all).
-endif.

-include("erleventer.hrl").
-include("deps/teaser/include/utils.hrl"). % for debug

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
        add_fun_apply/4,
        add_fun_apply/5,
        cancel/2
    ]).

-export_type([
        frequency/0,
        result_of_add/0,
        result_of_cancel/0
    ]).

-define(SERVER(Id),
    list_to_atom(lists:concat([Id, "_", ?MODULE]))
).

% ============================== public api part ===============================

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
-spec add_send_message(Id, Frequency, Pid, Method, Message) -> Result when
    Id          :: atom(),
    Frequency   :: frequency(),
    Pid         :: process(),
    Method      :: send_method(),
    Message     :: message(),
    Result      :: result_of_add().

add_send_message(Id, Frequency, Pid, Method, Message) ->
    add_send_message(Id, Frequency, Pid, Method, Message, #{}).


-spec add_send_message(Id, Frequency, Pid, Method, Message, Options) -> Result when
    Id          :: atom(),
    Frequency   :: frequency(),
    Pid         :: process(),
    Method      :: send_method(),
    Message     :: message(),
    Options     :: add_options(),
    Result      :: result_of_add().

add_send_message(Id, Frequency, Pid, Method, Message, Options) ->
    add_fun_apply(
      Id,
      Frequency,
      gen_fun_for_method(Method),
      [Pid, Message],
      Options
    ).

% @doc interface for add new function for pereodic execution
-spec add_fun_apply(Id, Frequency, Fun, Arguments) -> Result when
    Id          :: atom(),
    Frequency   :: frequency(),
    Fun         :: fun(),
    Arguments   :: list(),
    Result      :: result_of_add().

add_fun_apply(Id, Frequency, Fun, Arguments) ->
    add_fun_apply(Id, Frequency, Fun, Arguments, #{}).


-spec add_fun_apply(Id, Frequency, Fun, Arguments, Options) -> Result when
    Id          :: atom(),
    Frequency   :: frequency(),
    Fun         :: fun(),
    Arguments   :: list(),
    Options     :: add_options(),
    Result      :: result_of_add().

add_fun_apply(Id, Frequency, Fun, Arguments, Options) ->
    gen_server:call(?SERVER(Id), {?FUNCTION_NAME, Frequency, Fun, Arguments, Options}).


% @doc interface for delete event
-spec cancel(Id, Options) -> Result when
    Id          :: atom(),
    Options     :: cancel_ops(),
    Result      :: 'ok'.

cancel(Id, Options) ->
    Pid = maps:get('pid', Options, '_'),
    Method = maps:get('method', Options, '_'),
    Message = maps:get('message', Options, '_'),

    case Pid =/= '_' orelse Method =/= '_' orelse Message =/= '_' of
        false ->
            gen_server:call(?SERVER(Id), {cancel, Options});
        true ->
            cancel(Id,
                maps:put('fun', gen_fun_for_method(Method),
                    maps:put('arguments',
                        [Pid, Message],
                        maps:without(['pid', 'method', 'message'], Options)
                    )
                )
            )
    end.

% -------------------------- end of public api part ----------------------------

% ============================== gen_server part ===============================

% @doc While init we going to create ets table
-spec init(Id) -> Result when
    Id      :: atom(),
    Result  :: {'ok', state()}.

init(Id) ->
    {ok, #state{
            ets_name = ets:new(?SERVER(Id), [set, protected, {keypos, #task.tref}, named_table])
        }
    }.

%--------------handle_call----------------

% @doc callbacks for gen_server handle_call.
-spec handle_call(Message, From, State) -> Result when
    Message     :: Add | Cancel,
    Add         :: {'add_fun_apply', frequency(), fun(), Arguments, add_options()},
    Cancel      :: {'cancel', cancel_ops()},

    Arguments   :: list(),

    From        :: {pid(), Tag},
    Tag         :: term(),
    State       :: state(),
    Reply       :: {'added', timer:tref()}
                 | {'frequency_counter_updated', frequency(), pos_integer()}
                 | result_of_add()
                 | result_of_cancel(),
    Result      :: {reply, Reply, State}.


handle_call({'add_fun_apply', Frequency, Fun, Arguments, Options}, _From, State = #state{ets_name = EtsName} = State) ->
    MS = [{#task{'function' = Fun, 'arguments' = Arguments, _ = '_'}, [], ['$_']}],

    Reply = case ets:select(EtsName, MS) of
        [Task] ->
            add_freq(Task, Frequency, State);
        [] ->
            CastFun = fun(TargetFrequency) ->
                timer:send_interval(
                  may_rondimize_frequency(TargetFrequency),
                  self(),
                  {'cast_safe', Fun, Arguments}
                )
            end,
            {ok, TRef} = erlang:apply(CastFun, [Frequency]),
            Task = #task{
                frequency = #{Frequency => 1},
                function = Fun,
                arguments = Arguments,
                tag = maps:get('tag', Options, 'undefined'),
                tref = TRef,
                cast_fun = CastFun
            },
            ets:insert(EtsName, Task),
            {'added', TRef}
    end,
    {reply, Reply, State};


handle_call({cancel, CancelOps}, _From, State = #state{ets_name = EtsName} = State) ->
    MS = [{
            #task{
                'function' = maps:get('function', CancelOps, '_'),
                'arguments' = maps:get('arguments', CancelOps, '_'),
                'tag' = maps:get('tag', CancelOps, '_'),
                _ = '_'
            }, [], ['$_']
          }],

    Frequency = maps:get('frequency', CancelOps, '_'),
    Gone = lists:map(
        fun
            (#task{tref = TRef}) when Frequency =:= '_' ->
                _ = timer:cancel(TRef),
                ets:delete(EtsName, TRef),
                {'cancelled', TRef};
            (Task) ->
                remove_freq(Task, Frequency, State)
        end, ets:select(EtsName, MS)
    ), {reply, Gone, State}.

%-----------end of handle_call-------------


%--------------handle_cast-----------------

% @doc callbacks for gen_server handle_call.
-spec handle_cast(Message, State) -> Result when
    Message :: 'stop',
    State   :: state(),
    Result  :: {noreply, State} | {stop, normal, State}.

% handle_cast for stop
handle_cast(stop, State) ->
    {stop, normal, State}.
%-----------end of handle_cast-------------

%--------------handle_info-----------------

% @doc callbacks for gen_server handle_info.
-spec handle_info(Message, State) -> Result when
    Message :: {'cast_safe', fun(), list()},
    State   :: term(),
    Result  :: {noreply, State}.

handle_info({'cast_safe', Fun, Arguments}, State) ->
    _ = spawn(fun() -> erlang:apply(Fun, Arguments) end),
    {noreply, State}.

%-----------end of handle_info-------------


% @doc call back for gen_server terminate
-spec terminate(Reason, State) -> term() when
    Reason  :: 'normal' | 'shutdown' | {'shutdown',term()} | term(),
    State   :: term().

terminate(Reason, State = #state{ets_name = EtsName}) ->
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

% ----------------------- end of gen_server part -------------------------------

% ============================= INTERNALS ======================================


% @doc randomize frequency in period
-spec may_rondimize_frequency(Frequency) -> Result when
      Frequency :: frequency(),
      Result    :: pos_integer().

may_rondimize_frequency({'random_between', Lower, Upper}) ->
    rand:uniform(Upper-Lower) + Lower;
may_rondimize_frequency(Frequency) -> Frequency.

% @doc add frequency - reschedule event in case of target freq is less than what we have or update counter
-spec add_freq(Task, NewFrequency, State) -> Result when
    Task            :: task(),
    NewFrequency    :: frequency(),
    State           :: state(),
    Result          :: {'frequency_counter_updated', frequency(), pos_integer()}
                    |  {'re_scheduled', frequency(), timer:tref()}.

add_freq(#task{frequency = FrequencyMap, tref = TRef} = Task, NewFrequency, #state{ets_name = EtsName}) ->
    case maps:get(NewFrequency, FrequencyMap, 'undefined') of
        'undefined' ->
            case NewFrequency < hd(lists:sort(maps:keys(FrequencyMap))) of
                true ->
                    NewTRef = recast(Task, NewFrequency),
                    ets:delete(EtsName, TRef),
                    ets:insert(
                        EtsName,
                        Task#task{
                          frequency = maps:put(NewFrequency, 1, FrequencyMap),
                          tref = NewTRef
                         }
                    ),
                    {'re_scheduled', NewFrequency, NewTRef};
                false ->
                    ets:insert(
                      EtsName,
                      Task#task{
                        frequency = maps:put(NewFrequency, 1, FrequencyMap)
                       }
                    ),
                    {'frequency_counter_updated', NewFrequency, 1}
            end;
        Qty ->
            NewQty = Qty + 1,
            ets:insert(
              EtsName,
              Task#task{
                frequency = maps:put(NewFrequency, NewQty, FrequencyMap)
               }
            ),
            {'frequency_counter_updated', NewFrequency, NewQty}
    end.


% @doc recast task with new frequency
-spec recast(Task, NewFrequency) -> Result when
      Task          :: task(),
      NewFrequency  :: frequency(),
      Result        :: timer:tref().

recast(#task{cast_fun = CastFun, tref = TRef}, NewFrequency) ->
    _ = timer:cancel(TRef),
    {ok, NewTRef} = erlang:apply(CastFun, [NewFrequency]),
    NewTRef.


% @doc remove frequency - reschedule event in case of target freq is less than what we have or update counter
-spec remove_freq(Task, FrequencyToDelete, State) -> Result when
    Task                :: task(),
    FrequencyToDelete   :: frequency(),
    State               :: state(),
    Result              :: {'not_found', frequency()}
                        |  {'cancelled', timer:tref()}
                        |  {'re_scheduled', frequency(), timer:tref()}
                        |  {'frequency_removed', frequency()}
                        |  {'frequency_counter_updated', frequency(), pos_integer()}.

remove_freq(#task{frequency = FrequencyMap, tref = TRef} = Task, FrequencyToDelete, #state{ets_name = EtsName}) ->
    case maps:get(FrequencyToDelete, FrequencyMap, 'undefined') of
        'undefined' ->
            {'not_found', FrequencyToDelete};
        1 ->
            NeedRescedule = lists:min(maps:keys(FrequencyMap)) =:= FrequencyToDelete,
            case NeedRescedule of
                true when map_size(FrequencyMap) =:= 1 ->
                    _ = timer:cancel(TRef),
                    _ = ets:delete(EtsName, TRef),
                    {'cancelled', TRef};
                true ->
                    _ = timer:cancel(TRef),
                    NewFrequencyMap = maps:remove(FrequencyToDelete, FrequencyMap),
                    NewFrequency = lists:min(maps:keys(NewFrequencyMap)),
                    NewTRef = recast(Task, NewFrequency),
                    _ = ets:delete(EtsName, TRef),
                    _ = ets:insert(
                        EtsName,
                        Task#task{
                          frequency = NewFrequencyMap,
                          tref = NewTRef
                         }
                    ),
                    {'re_scheduled', NewFrequency, NewTRef};
                false ->
                    _ = ets:insert(
                      EtsName,
                      Task#task{
                        frequency = maps:remove(FrequencyToDelete, FrequencyMap)
                       }
                    ),
                    {'frequency_removed', FrequencyToDelete}
            end;
        Qty ->
            NewQty = Qty - 1,
            _ = ets:insert(
              EtsName,
              Task#task{
                frequency = maps:put(FrequencyToDelete, NewQty, FrequencyMap)
               }
            ),
            {'frequency_counter_updated', FrequencyToDelete, NewQty}
    end.

% @doc generate function for sending message method
-spec gen_fun_for_method(Method) -> Result when
    Method  :: send_method() | '_',
    Result  :: fun() | '_'.

gen_fun_for_method('info') -> fun erlang:send/2;
gen_fun_for_method('cast') -> fun gen_server:cast/2;
gen_fun_for_method('call') -> fun gen_server:call/2;
gen_fun_for_method('_') -> '_'.
