-module(erlcron_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TESTMODULE, erlcron).
-define(TESTID, limpopo).
-define(TESTSERVER, limpopo_erlcron).

% --------------------------------- fixtures ----------------------------------

erlcron_start_stop_test_() ->
    {setup,
        fun disable_output/0,
        fun stop_server/1,
        {inorder,
            [
                {<<"erlcron gen_server able to start and register with right name">>, 
                    fun() ->
                        ?TESTMODULE:start_link(?TESTID),
                        ?assertEqual(
                            true,
                            is_pid(whereis(?TESTSERVER))
                        ) 
                end},
                {<<"erlcron gen_server able to stop via ?TESTMODULE:stop(?TESTID)">>,
                    fun() ->
                        ?assertExit({normal,{gen_server,call,[?TESTSERVER,stop]}}, ?TESTMODULE:stop(?TESTID)),
                        ?assertEqual(
                            false,
                            is_pid(whereis(?TESTSERVER))
                        )
                end},
                {<<"erlcron gen_server able to start and stop via ?TESTMODULE:start_link(?TESTID) / ?TESTMODULE:stop(sync, ?TESTID)">>,
                    fun() ->
                        ?TESTMODULE:start_link(?TESTID),
                        ?assertExit({normal,{gen_server,call,[?TESTSERVER, stop]}}, ?TESTMODULE:stop(sync, ?TESTID)),
                        ?assertEqual(
                            false,
                            is_pid(whereis(?TESTSERVER))
                        )
                end},
                {<<"erlcron able to start and stop via ?TESTMODULE:start_link(Market) ?TESTMODULE:stop(async,Market)">>,
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

gen_server_unknown_message_test_ () ->
    {setup,
        fun setup_start/0,
        fun stop_server/1,
        {inparallel,
            [
                {<<"gen_server should be registered">>, 
                    fun() ->
                        ?assertEqual(
                            true,
                            is_pid(whereis(?TESTSERVER))
                        ) 
                    end},

                {<<"Ets Table should be present when erlcron started">>,
                    fun() ->
                        ?assertNotEqual(
                           undefined,
                           ets:info(?TESTSERVER)
                          )
                    end},

                {<<"Unknown gen_calls messages must do not crash gen_server">>,
                    fun() ->
                        _ = gen_server:call(?TESTSERVER, {unknown, message}),
                        timer:sleep(1), % for async cast
                        ?assertEqual(
                            true,
                            is_pid(whereis(?TESTSERVER))
                        )
                    end},

                {<<"Unknown gen_cast messages must do not crash gen_server">>,
                    fun() ->
                        gen_server:cast(?TESTSERVER, {unknown, message}),
                        timer:sleep(1), % for async cast
                        ?assertEqual(
                            true,
                            is_pid(whereis(?TESTSERVER))
                        )
                    end},

                {<<"Unknown gen_info messages must do not crash gen_server">>,
                    fun() ->
                        ?TESTSERVER ! {unknown, message},
                        timer:sleep(1), % for async cast
                        ?assertEqual(
                            true,
                            is_pid(whereis(?TESTSERVER))
                        )
                    end}
            ]
        }
    }.


eventer_test_ () ->
    {setup,
        fun setup_start/0,
        fun stop_server/1,
        {inorder,
            [
                {<<"Able to create new task and send data">>, 
                    fun() ->
                        LoopWait = 4,
                        Freq = 2,
                        CountTill = 10,
                        TestMsg = {case1, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        ?TESTMODULE:add(?TESTID, Freq, self(), info, TestMsg),
                        Data = recieve_loop([],TestMsg,LoopWait,CountTill,0),
                        Await = [TestMsg || _N <- lists:seq(1,CountTill)],
                        ?assertEqual(Await,Data)
                end},
                {<<"Able to create new task with new MestMsg">>, 
                    fun() ->
                        LoopWait = 4,
                        Freq = 2,
                        CountTill = 3,
                        TestMsg = {case2, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        ?TESTMODULE:add(?TESTID, Freq, self(), info, TestMsg),
                        Data = recieve_loop([],TestMsg,LoopWait,CountTill,0),
                        Await = [TestMsg || _N <- lists:seq(1,CountTill)],
                        ?assertEqual(Await,Data),
                        ok
                end},
                {<<"If we call TESTMODULE:add twice with same arguments, it won't create new event in ets and still have only 3 reference in state">>, 
                    fun() ->
                        Freq = 1000,
                        TestMsg = {case3, {erlang:monotonic_time(), erlang:unique_integer([monotonic,positive])}},
                        ?TESTMODULE:add(?TESTID, Freq, self(), info, TestMsg),

                        EtsData = ets:tab2list(?TESTSERVER),
                        ?assert(is_list(EtsData)),
                        ?assertNotEqual([], EtsData),
                        
                        ?TESTMODULE:add(?TESTID, Freq, self(), info, TestMsg),
                        EtsData2 = ets:tab2list(?TESTSERVER),
                        ?assert(is_list(EtsData2)),
                        ?assertNotEqual([], EtsData2),
                        ?assertEqual(EtsData, EtsData2),

                        {state, ?TESTSERVER, State} = sys:get_state(?TESTSERVER),
                        ?assertEqual(3, maps:size(State))
                end}
            ]
        }
    }.


setup_start() ->
    disable_output(),
    start_server().

disable_output() ->
    error_logger:tty(false).

stop_server(_) ->
    case whereis(?TESTSERVER) of
        undefined -> ok;
        _ -> ?assertExit({normal,{gen_server,call,[?TESTSERVER,stop]}}, ?TESTMODULE:stop(?TESTID))
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
