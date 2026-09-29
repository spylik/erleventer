-module(erleventer_tests).

-include_lib("eunit/include/eunit.hrl").
-include("erleventer.hrl").
-define(TESTMODULE, erleventer).
-define(TESTID, limpopo).
-define(TESTSERVER, limpopo_erleventer).

-export([add_to_ets/1]).

% --------------------------------- fixtures ----------------------------------

erleventer_start_stop_test_() ->
    {setup,
        fun disable_output/0,
        fun stop_server/1,
        {inorder,
            [
                {<<"erleventer gen_server able to start and register with right name">>,
                    fun() ->
                        ?TESTMODULE:start_link(?TESTID),
                        ?assertEqual(
                            true,
                            is_pid(whereis(?TESTSERVER))
                        )
                end},
                {<<"erleventer gen_server able to stop via ?TESTMODULE:stop(?TESTID)">>,
                    fun() ->
                        ok = ?TESTMODULE:stop(?TESTID),
                        ?assertEqual(
                            false,
                            is_pid(whereis(?TESTSERVER))
                        )
                end},
                {<<"erleventer gen_server able to start and stop via ?TESTMODULE:start_link(?TESTID) / ?TESTMODULE:stop(sync, ?TESTID)">>,
                    fun() ->
                        ?TESTMODULE:start_link(?TESTID),
                        ok = ?TESTMODULE:stop(sync, ?TESTID),
                        ?assertEqual(
                            false,
                            is_pid(whereis(?TESTSERVER))
                        )
                end},
                {<<"erleventer able to start and stop via ?TESTMODULE:start_link(Market) ?TESTMODULE:stop(async,Market)">>,
                    fun() ->
                        ?TESTMODULE:start_link(?TESTID),
                        ?TESTMODULE:stop(async,?TESTID),
                        timer:sleep(1), % for async cast
                        ?assertEqual(
                            false,
                            is_pid(whereis(?TESTSERVER))
                        )
                end}
            ]
        }
    }.


eventer_seq_test_() ->
    {setup,
        fun setup_start/0,
        fun stop_server/1,
        {inorder,
            [
                {<<"Able to create new task and send data">>,
                    fun() ->
                        LoopWait = 1000,
                        Freq = 2,
                        CountTill = 10,
                        TestMsg = {case1, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        {'added', _Ref} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        Data = recieve_loop([],TestMsg,LoopWait,CountTill,0),
                        Await = [TestMsg || _N <- lists:seq(1,CountTill)],
                        ?assertEqual(Await,Data)
                end},
                {<<"Able to create new task with new MestMsg">>,
                    fun() ->
                        LoopWait = 1000,
                        Freq = 2,
                        CountTill = 3,
                        TestMsg = {case2, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        {'added', _Ref} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        Data = recieve_loop([],TestMsg,LoopWait,CountTill,0),
                        Await = [TestMsg || _N <- lists:seq(1,CountTill)],
                        ?assertEqual(Await,Data),
                        ok
                end},
                {<<"If we call TESTMODULE:add twice with same arguments, it won't create new event in ets and still have only 3 reference in state">>,
                    fun() ->
                        Freq = 1000,
                        TestMsg = {case3, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        {'added', Ref} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        EtsData = ets:tab2list(?TESTSERVER),
                        ?assertEqual(3, length(EtsData)),
                        {'frequency_counter_updated', Freq, 2} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        EtsData2 = ets:tab2list(?TESTSERVER),
                        ?assertNotEqual(EtsData, EtsData2),
                        ?assertEqual(3, length(EtsData2)),

                        [{'frequency_counter_updated', Freq, 1}] = ?TESTMODULE:cancel(?TESTID, #{'frequency' => Freq, 'pid' => self(), 'method' => info, 'message' => TestMsg}),
                        EtsData3 = ets:tab2list(?TESTSERVER),
                        ?assertNotEqual(EtsData2, EtsData3),
                        ?assertEqual(3, length(EtsData3)),
                        [{'cancelled', Ref}] = ?TESTMODULE:cancel(?TESTID, #{'frequency' => Freq, 'pid' => self(),
'method' => info, 'message' => TestMsg}),
                        EtsData4 = ets:tab2list(?TESTSERVER),
                        ?assertEqual(2, length(EtsData4))
                end},
                {<<"Able to delete task via cancel/2 with full parameters">>,
                    fun() ->
                        LoopWait = 1000,
                        Freq = 10,
                        CountTill = 3,
                        TestMsg = {case4, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        {'added', Ref} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        EtsData = ets:tab2list(?TESTSERVER),
                        ?assertEqual(3, length(EtsData)),
                        Data = recieve_loop([],TestMsg,LoopWait,CountTill,0),
                        Await = [TestMsg || _N <- lists:seq(1,CountTill)],
                        ?assertEqual(Await,Data),
                        [{'cancelled', Ref}] = ?TESTMODULE:cancel(?TESTID, #{'frequency' => Freq, 'pid' => self(), 'method' => info, 'message' => TestMsg}),
                        ok = assert_stopped_sending(TestMsg),
                        EtsData3 = ets:tab2list(?TESTSERVER),
                        ?assertEqual(2, length(EtsData3))
                end},
                {<<"Able to delete task via cancel/2 with less parameter">>,
                    fun() ->
                        LoopWait = 1000,
                        Freq = 10,
                        CountTill = 3,
                        TestMsg = {case5, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        {'added', _Ref} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        EtsData = ets:tab2list(?TESTSERVER),
                        ?assertEqual(3, length(EtsData)),
                        Data = recieve_loop([],TestMsg,LoopWait,CountTill,0),
                        Await = [TestMsg || _N <- lists:seq(1,CountTill)],
                        ?assertEqual(Await,Data),
                        _ = ?TESTMODULE:cancel(?TESTID, #{'pid' => self()}),
                        ok = assert_stopped_sending(TestMsg),
                        EtsData3 = ets:tab2list(?TESTSERVER),
                        ?assertEqual(0, length(EtsData3))
                end},
                {<<"Able to delete task via cancel/2 with less parameters">>,
                    fun() ->
                        LoopWait = 1000,
                        Freq = 10,
                        CountTill = 3,
                        TestMsg = {case6, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        {'added', Ref} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        EtsData = ets:tab2list(?TESTSERVER),
                        ?assertEqual(1, length(EtsData)),
                        {'frequency_counter_updated', Freq, 2} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        EtsData2 = ets:tab2list(?TESTSERVER),
                        ?assertNotEqual(EtsData, EtsData2),
                        ?assertEqual(1, length(EtsData2)),
                        Data = recieve_loop([],TestMsg,LoopWait,CountTill,0),
                        Await = [TestMsg || _N <- lists:seq(1,CountTill)],
                        ?assertEqual(Await,Data),
                        [{'cancelled', Ref}] = ?TESTMODULE:cancel(?TESTID, #{'method' => info, 'message' => TestMsg}),
                        ok = assert_stopped_sending(TestMsg),
                        EtsData3 = ets:tab2list(?TESTSERVER),
                        ?assertEqual(0, length(EtsData3))
                end},
                {<<"When going to terminate erleventer process, must cleanup queue in timer">>,
                    fun() ->
                        LoopWait = 1000,
                        Freq = 10,
                        CountTill = 3,
                        TestMsg = {case7, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        {'added', _Ref} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        EtsData = ets:tab2list(?TESTSERVER),
                        ?assertEqual(1, length(EtsData)),
                        {'frequency_counter_updated', Freq, 2} = ?TESTMODULE:add_send_message(?TESTID, Freq, self(), info, TestMsg),
                        EtsData2 = ets:tab2list(?TESTSERVER),
                        ?assertNotEqual(EtsData, EtsData2),
                        ?assertEqual(1, length(EtsData2)),
                        Data = recieve_loop([],TestMsg,LoopWait,CountTill,0),
                        Await = [TestMsg || _N <- lists:seq(1,CountTill)],
                        ?assertEqual(Await,Data),
                        ?TESTMODULE:stop(?TESTID),
                        ok = assert_stopped_sending(TestMsg)
                end}
            ]
        }
    }.

frequencer_one_test_() ->
     {setup,
        fun setup_start/0,
        fun stop_server/1,
        {inparallel,
            [
                 {<<"a closure is applied periodically, and no more once cancelled">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        {'added', _} = ?TESTMODULE:add_fun_apply(?TESTID, 10, fun(Table) -> erleventer_tests:add_to_ets(Table) end, [Tid], #{tag => Tag}),
                        ?assert(?TESTMODULE:is_task_exist(?TESTID, #{tag => Tag})),
                        ok = wait_ticks(Tid, 2),
                        [{'cancelled', _}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag}),
                        ok = assert_stopped_applying(Tid),
                        ?assertNot(?TESTMODULE:is_task_exist(?TESTID, #{tag => Tag}))
                    end
                 },
                 {<<"a module:function/arity fun is applied periodically, and no more once cancelled">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        {'added', _} = ?TESTMODULE:add_fun_apply(?TESTID, 10, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        ok = wait_ticks(Tid, 2),
                        [{'cancelled', _}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag}),
                        ok = assert_stopped_applying(Tid)
                    end
                 },
                 {<<"cancelling a frequency the task does not have changes nothing">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        {'added', TRef} = ?TESTMODULE:add_fun_apply(?TESTID, 10, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        [{'not_found', 100}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 100}),
                        ?assertMatch(#task{tref = TRef, frequency = #{10 := 1}}, task(Tag)),
                        ok = wait_ticks(Tid, 2),
                        [{'cancelled', TRef}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        ok = assert_stopped_applying(Tid)
                    end
                 },
                 {<<"a faster frequency reschedules; cancelling the slower one keeps the faster">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        {'added', TRef10} = ?TESTMODULE:add_fun_apply(?TESTID, 10, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        {'re_scheduled', 5, TRef5} = ?TESTMODULE:add_fun_apply(?TESTID, 5, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        ?assertNotEqual(TRef10, TRef5),
                        ?assertMatch(#task{tref = TRef5, frequency = #{10 := 1, 5 := 1}}, task(Tag)),
                        [{'frequency_removed', 10}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        ?assertEqual(#{5 => 1}, (task(Tag))#task.frequency),
                        ?assertEqual(TRef5, (task(Tag))#task.tref),
                        ok = wait_ticks(Tid, 2),
                        [{'cancelled', TRef5}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 5}),
                        ok = assert_stopped_applying(Tid)
                    end
                 },
                 {<<"cancelling the faster frequency falls back to the slower one">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        {'added', _} = ?TESTMODULE:add_fun_apply(?TESTID, 10, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        {'re_scheduled', 5, TRef5} = ?TESTMODULE:add_fun_apply(?TESTID, 5, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        [{'re_scheduled', 10, TRefBack}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 5}),
                        ?assertNotEqual(TRef5, TRefBack),
                        ?assertMatch(#task{tref = TRefBack, frequency = #{10 := 1}}, task(Tag)),
                        ?assertEqual(1, map_size((task(Tag))#task.frequency)),
                        ok = wait_ticks(Tid, 2),
                        [{'cancelled', TRefBack}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        ok = assert_stopped_applying(Tid)
                    end
                 }
            ]
        }
     }.

frequencer_two_test_() ->
     {setup,
        fun setup_start/0,
        fun stop_server/1,
        {inparallel,
            [
                 {<<"a random frequency faster than the static one reschedules; cancelling it falls back">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        {'added', _} = ?TESTMODULE:add_fun_apply(?TESTID, 10, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        {'re_scheduled', {random, 4, 5}, _} = ?TESTMODULE:add_fun_apply(?TESTID, {random, 4, 5}, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        ok = wait_ticks(Tid, 2),
                        [{'re_scheduled', 10, TRef10}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => {random, 4, 5}}),
                        ?assertEqual(#{10 => 1}, (task(Tag))#task.frequency),
                        ok = wait_ticks(Tid, 2),
                        [{'cancelled', TRef10}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        ok = assert_stopped_applying(Tid)
                    end
                 },
                 {<<"cancelling the static frequency keeps the faster random one">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        {'added', _} = ?TESTMODULE:add_fun_apply(?TESTID, 10, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        {'re_scheduled', {random, 4, 5}, TRefRandom} = ?TESTMODULE:add_fun_apply(?TESTID, {random, 4, 5}, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        [{'frequency_removed', 10}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        ?assertMatch(#task{tref = TRefRandom}, task(Tag)),
                        ok = wait_ticks(Tid, 2),
                        [{'cancelled', TRefRandom}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => {random, 4, 5}}),
                        ok = assert_stopped_applying(Tid)
                    end
                 },
                 {<<"a slower frequency only counts; cancelling the faster one reschedules to it">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        {'added', TRef5} = ?TESTMODULE:add_fun_apply(?TESTID, 5, fun erleventer_tests:add_to_ets/1, [Tid], #{tag => Tag}),
                        {'frequency_counter_updated', 10, 1} = ?TESTMODULE:add_fun_apply(?TESTID, 10, fun erleventer_tests:add_to_ets/1, [Tid], Tag),
                        ?assertMatch(#task{tref = TRef5, frequency = #{5 := 1, 10 := 1}}, task(Tag)),
                        ok = wait_ticks(Tid, 2),
                        [{'re_scheduled', 10, TRef10}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 5}),
                        ok = wait_ticks(Tid, 2),
                        [{'cancelled', TRef10}] = ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        ok = assert_stopped_applying(Tid)
                    end
                 }
            ]
        }
     }.

task(Tag) ->
    [Task] = ets:match_object(?TESTSERVER, #task{tag = Tag, _ = '_'}),
    Task.

wait_ticks(Tid, N) ->
    Target = ets:info(Tid, size) + N,
    wait_until(fun() -> ets:info(Tid, size) >= Target end).

assert_stopped_applying(Tid) ->
    _ = sys:get_state(?TESTSERVER),
    ok = wait_until(fun() -> quiet(fun() -> ets:info(Tid, size) end, 30) end),
    Settled = ets:info(Tid, size),
    receive after 60 -> ok end,
    case ets:info(Tid, size) of
        Settled -> ok;
        More -> {still_applied, Settled, More}
    end.

assert_stopped_sending(Msg) ->
    _ = whereis(?TESTSERVER) =/= undefined andalso sys:get_state(?TESTSERVER),
    ok = wait_until(fun() -> flush_quiet(Msg, 30) end),
    receive Msg -> {still_sent, Msg} after 60 -> ok end.

quiet(Count, Ms) ->
    Before = Count(),
    receive after Ms -> ok end,
    Count() =:= Before.

flush_quiet(Msg, Ms) ->
    receive Msg -> false after Ms -> true end.

subscriber_test_() ->
    {foreach,
        fun setup_start/0,
        fun stop_server/1,
        [
            {<<"a task goes when its subscriber dies">>,
                fun() ->
                    Sub = subscriber(),
                    Msg = {tick, make_ref()},
                    {'added', _} = ?TESTMODULE:add_send_message(?TESTID, 5, self(), info, Msg, #{subscriber => Sub, tag => t1}),
                    ?assertEqual(Msg, receive Msg -> Msg after 200 -> timeout end),
                    exit(Sub, kill),
                    ok = wait_until(fun() -> not ?TESTMODULE:is_task_exist(?TESTID, #{tag => t1}) end),
                    flush(Msg),
                    ?assertEqual(timeout, receive Msg -> Msg after 50 -> timeout end)
                end},
            {<<"a task stays while another of its subscribers lives">>,
                fun() ->
                    Sub1 = subscriber(),
                    Sub2 = subscriber(),
                    Msg = {tick, make_ref()},
                    {'added', _} = ?TESTMODULE:add_send_message(?TESTID, 10, self(), info, Msg, #{subscriber => Sub1, tag => t2}),
                    {'frequency_counter_updated', 10, 2} = ?TESTMODULE:add_send_message(?TESTID, 10, self(), info, Msg, #{subscriber => Sub2, tag => t2}),
                    exit(Sub1, kill),
                    ok = wait_until(fun() -> frequencies(t2) =:= #{10 => 1} end),
                    exit(Sub2, kill),
                    ok = wait_until(fun() -> not ?TESTMODULE:is_task_exist(?TESTID, #{tag => t2}) end)
                end},
            {<<"what was added without a subscriber keeps the task">>,
                fun() ->
                    Sub = subscriber(),
                    Msg = {tick, make_ref()},
                    {'added', _} = ?TESTMODULE:add_send_message(?TESTID, 10, self(), info, Msg, #{tag => t3}),
                    {'frequency_counter_updated', 10, 2} = ?TESTMODULE:add_send_message(?TESTID, 10, self(), info, Msg, #{subscriber => Sub, tag => t3}),
                    exit(Sub, kill),
                    ok = wait_until(fun() -> frequencies(t3) =:= #{10 => 1} end),
                    ?assertEqual(Msg, receive Msg -> Msg after 200 -> timeout end)
                end},
            {<<"a subscriber's faster frequency goes with it and the task falls back to the slower one">>,
                fun() ->
                    Sub = subscriber(),
                    Msg = {tick, make_ref()},
                    {'added', _} = ?TESTMODULE:add_send_message(?TESTID, 60000, self(), info, Msg, #{tag => t4}),
                    {'re_scheduled', 5, _} = ?TESTMODULE:add_send_message(?TESTID, 5, self(), info, Msg, #{subscriber => Sub, tag => t4}),
                    ?assertEqual(Msg, receive Msg -> Msg after 200 -> timeout end),
                    exit(Sub, kill),
                    ok = wait_until(fun() -> frequencies(t4) =:= #{60000 => 1} end),
                    flush(Msg),
                    ?assertEqual(timeout, receive Msg -> Msg after 50 -> timeout end)
                end},
            {<<"a subscriber of several tasks takes all of them">>,
                fun() ->
                    Sub = subscriber(),
                    {'added', _} = ?TESTMODULE:add_send_message(?TESTID, 60000, self(), info, a, #{subscriber => Sub, tag => t5}),
                    {'added', _} = ?TESTMODULE:add_send_message(?TESTID, 60000, self(), info, b, #{subscriber => Sub, tag => t6}),
                    exit(Sub, kill),
                    ok = wait_until(fun() -> not ?TESTMODULE:is_task_exist(?TESTID, #{tag => t5})
                                             andalso not ?TESTMODULE:is_task_exist(?TESTID, #{tag => t6}) end)
                end},
            {<<"a task cancelled before its subscriber dies stays cancelled, and erleventer carries on">>,
                fun() ->
                    Sub = subscriber(),
                    {'added', _} = ?TESTMODULE:add_send_message(?TESTID, 60000, self(), info, c, #{subscriber => Sub, tag => t7}),
                    [{'cancelled', _}] = ?TESTMODULE:cancel(?TESTID, #{tag => t7}),
                    Server = whereis(?TESTSERVER),
                    exit(Sub, kill),
                    ok = wait_until(fun() -> not maps:is_key(Sub, (sys:get_state(?TESTSERVER))#state.monitors) end),
                    ?assertEqual(Server, whereis(?TESTSERVER)),
                    ?assertNot(?TESTMODULE:is_task_exist(?TESTID, #{tag => t7}))
                end}
        ]
    }.

subscriber() ->
    spawn(fun() -> receive stop -> ok end end).

frequencies(Tag) ->
    case ets:match_object(?TESTMODULE:ets_name(?TESTID), #task{tag = Tag, _ = '_'}) of
        [#task{frequency = Frequencies}] -> Frequencies;
        [] -> gone
    end.

flush(Msg) ->
    receive Msg -> flush(Msg) after 0 -> ok end.

wait_until(Fun) -> wait_until(Fun, 2000).

wait_until(Fun, Left) when Left > 0 ->
    case Fun() of
        true -> ok;
        false -> receive after 10 -> wait_until(Fun, Left - 10) end
    end;
wait_until(_Fun, _Left) ->
    timeout.

compare_frequencies_test() ->
    ?assert(?TESTMODULE:compare_freq({'random', 5, 10}, 10)),
    ?assert(?TESTMODULE:compare_freq({'random', 5, 9}, 10)),

    ?assertNot(?TESTMODULE:compare_freq(10, {'random', 5, 10})),
    ?assertNot(?TESTMODULE:compare_freq(10, {'random', 5, 9})),

    ?assert(?TESTMODULE:compare_freq(10, {'random', 10, 11})),
    ?assertNot(?TESTMODULE:compare_freq({'random', 10, 11}, 10)),
    ?assertNot(?TESTMODULE:compare_freq({'random', 11, 12}, 10)).

add_to_ets(Tid) ->
    ets:insert(Tid, {erlang:make_ref()}).

setup_start() ->
    disable_output(),
    start_server().

disable_output() ->
    error_logger:tty(false).

stop_server(_) ->
    case whereis(?TESTSERVER) of
        undefined -> ok;
        _ -> ?TESTMODULE:stop(?TESTID)
    end,
    ok.

start_server() ->
    ?TESTMODULE:start_link(?TESTID).

% recieve loop
recieve_loop(Acc,WaitFor,LoopWait,Max,Current) when Max > Current ->
    receive
        WaitFor -> recieve_loop([WaitFor|Acc],WaitFor,LoopWait,Max,Current+1)
        after LoopWait -> Acc
    end;
recieve_loop(Acc, _, _, _, _) -> Acc.
