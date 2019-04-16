-module(erleventer_tests).

-include_lib("eunit/include/eunit.hrl").
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
                        LoopWait = 20,
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
                        LoopWait = 20,
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
                        LoopWait = 20,
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
                        Data2 = recieve_loop([],TestMsg,LoopWait,1,0),
                        ?assertEqual([], Data2),
                        EtsData3 = ets:tab2list(?TESTSERVER),
                        ?assertEqual(2, length(EtsData3))
                end},
                {<<"Able to delete task via cancel/2 with less parameter">>,
                    fun() ->
                        LoopWait = 20,
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
                        Data2 = recieve_loop([],TestMsg,LoopWait,1,0),
                        ?assertEqual([], Data2),
                        EtsData3 = ets:tab2list(?TESTSERVER),
                        ?assertEqual(0, length(EtsData3))
                end},
                {<<"Able to delete task via cancel/2 with less parameters">>,
                    fun() ->
                        LoopWait = 20,
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
                        Data2 = recieve_loop([],TestMsg,LoopWait,1,0),
                        ?assertEqual([], Data2),
                        EtsData3 = ets:tab2list(?TESTSERVER),
                        ?assertEqual(0, length(EtsData3))
                end},
                {<<"When going to terminate erleventer process, must cleanup queue in timer">>,
                    fun() ->
                        LoopWait = 20,
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
                        Data2 = recieve_loop([],TestMsg,LoopWait,1,0),
                        ?assertEqual([], Data2)
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
                 {<<"Simply periodic apply fun()">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, 10,
                           fun(Table) -> erleventer_tests:add_to_ets(Table) end,
                           [Tid], #{tag => Tag}
                        ),
                        timer:sleep(25),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag}),
                        ?assertEqual(2, length(ets:tab2list(Tid)))
                    end
                 },
                 {<<"Simply periodic apply fun() with wait after cancel">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, 10,
                           fun(Table) -> erleventer_tests:add_to_ets(Table) end,
                            [Tid], #{tag => Tag}
                        ),
                        timer:sleep(25),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag}),
                        timer:sleep(25),
                        ?assertEqual(2, length(ets:tab2list(Tid)))
                    end
                 },
                 {<<"Simply periodic apply fun module:function/arity">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        ?TESTMODULE:add_fun_apply(
                            ?TESTID, 10,
                            fun erleventer_tests:add_to_ets/1,
                            [Tid], #{tag => Tag}
                        ),
                        timer:sleep(25),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag}),
                        ?assertEqual(2, length(ets:tab2list(Tid)))
                    end
                 },
                 {<<"Simply periodic apply fun module:function/arity. Trying to cancel some unexistent freq">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        ?TESTMODULE:add_fun_apply(
                            ?TESTID, 10,
                            fun erleventer_tests:add_to_ets/1,
                            [Tid], #{tag => Tag}
                        ),
                        timer:sleep(22),
                        ?assertEqual(2, length(ets:tab2list(Tid))),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 100}),
                        timer:sleep(22),
                        ?assertEqual(4, length(ets:tab2list(Tid))),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        timer:sleep(22),
                        ?assertEqual(4, length(ets:tab2list(Tid)))
                    end
                 },
                 {<<"Add frequency for apply (<current) - lead to changing freq. First cancel higher">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, 10,
                           fun erleventer_tests:add_to_ets/1,
                           [Tid], #{tag => Tag}
                        ),
                        timer:sleep(25),
                        ?assertEqual(2, length(ets:tab2list(Tid))),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, 5,
                           fun erleventer_tests:add_to_ets/1,
                           [Tid], #{tag => Tag}
                        ),
                        timer:sleep(27),
                        ?assertEqual(7, length(ets:tab2list(Tid))),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        timer:sleep(15),
                        ?assertEqual(10, length(ets:tab2list(Tid))),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 5}),
                        timer:sleep(25),
                        ?assertEqual(10, length(ets:tab2list(Tid)))
                    end
                 },
                 {<<"Add frequency for apply (<current) - lead to changing freq. First cancel lower">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, 10,
                           fun erleventer_tests:add_to_ets/1,
                           [Tid], #{tag => Tag}
                        ),
                        timer:sleep(25),
                        ?assertEqual(2, length(ets:tab2list(Tid))),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, 5,
                           fun erleventer_tests:add_to_ets/1,
                           [Tid], #{tag => Tag}
                        ),
                        timer:sleep(27),
                        ?assertEqual(7, length(ets:tab2list(Tid))),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 5}),
                        timer:sleep(17),
                        ?assertEqual(8, length(ets:tab2list(Tid))),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        timer:sleep(25),
                        ?assertEqual(8, length(ets:tab2list(Tid)))
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
                 {<<"Test for comparing random frequencies with static (first cancel random).">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, 10,
                           fun erleventer_tests:add_to_ets/1,
                           [Tid], #{tag => Tag}
                        ),
                        timer:sleep(25),
                        ?assertEqual(2, length(ets:tab2list(Tid))),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, {random, 4, 5},
                           fun erleventer_tests:add_to_ets/1,
                           [Tid], #{tag => Tag}
                        ),
                        timer:sleep(27),
                        Length0 = length(ets:tab2list(Tid)),
                        ?assert(6 =:= Length0 orelse 7 =:= Length0),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => {random, 4, 5}}),
                        timer:sleep(17),
                        Length1 = length(ets:tab2list(Tid)),
                        ?assert(7 =:= Length1 orelse 8 =:= Length1),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        timer:sleep(25),
                        Length2 = length(ets:tab2list(Tid)),
                        ?assert(7 =:= Length2 orelse 8 =:= Length2)

                    end
                 },
                 {<<"Test for comparing random frequencies with static (first cancel random).">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, 10,
                           fun erleventer_tests:add_to_ets/1,
                           [Tid], #{tag => Tag}
                        ),
                        timer:sleep(25),
                        ?assertEqual(2, length(ets:tab2list(Tid))),
                        ?TESTMODULE:add_fun_apply(
                           ?TESTID, {random, 4, 5},
                           fun erleventer_tests:add_to_ets/1,
                           [Tid], #{tag => Tag}
                        ),
                        timer:sleep(27),
                        Length0 = length(ets:tab2list(Tid)),
                        ?assert(6 =:= Length0 orelse 7 =:= Length0),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        timer:sleep(17),
                        Length1 = length(ets:tab2list(Tid)),
                        ?assert(9 =:= Length1 orelse 10 =:= Length1 orelse 11 =:= Length1),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => {random, 4, 5}}),
                        timer:sleep(25),
                        Length2 = length(ets:tab2list(Tid)),
                        ?assert(9 =:= Length1 orelse 10 =:= Length1 orelse 11 =:= Length1)
                    end
                 },

                 {<<"Add frequency for apply (>current). First cancel lower">>,
                    fun() ->
                        Tid = ets:new(?MODULE, [bag, public]),
                        Tag = erlang:make_ref(),
                        ?TESTMODULE:add_fun_apply(
                            ?TESTID, 5,
                            fun erleventer_tests:add_to_ets/1,
                            [Tid], #{tag => Tag}
                        ),
                        timer:sleep(26),
                        Length1 = length(ets:tab2list(Tid)),
                        ?assert(4 =:= Length1 orelse 5 =:= Length1),
                        ?TESTMODULE:add_fun_apply(?TESTID, 10, fun erleventer_tests:add_to_ets/1, [Tid], Tag),
                        timer:sleep(26),
                        Length2 = length(ets:tab2list(Tid)),
                        ?assert(9 =:= Length2 orelse 10 =:= Length2),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 5}),
                        timer:sleep(25),
                        ?assertEqual(12, length(ets:tab2list(Tid))),
                        ?TESTMODULE:cancel(?TESTID, #{'tag' => Tag, frequency => 10}),
                        timer:sleep(25),
                        ?assertEqual(12, length(ets:tab2list(Tid)))
                    end
                 }
            ]
        }
     }.

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
