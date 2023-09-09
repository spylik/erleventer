% todo: suport start_ops
-type start_ops()   :: #{
        'register'      => register_as()
    }.
-type register_as() :: {'local', atom()} | {'global', term()}.

-type add_options() :: #{
        'tag'           => term(),
        'run_on_init'   => boolean()
       }.

-type result_of_add()       :: {'added', timer:tref()}
                            |  {'frequency_counter_updated', frequency(), pos_integer()}
                            |  {'re_scheduled', frequency(), timer:tref()}.

-type result_of_cancel()   :: [
                                   {'not_found', frequency()}
                                 | {'cancelled', timer:tref()}
                                 | {'re_scheduled', frequency(), timer:tref()}
                                 | {'frequency_removed', frequency()}
                                 | {'frequency_counter_updated', frequency(), pos_integer()}
                            ] | [].

-type search_task_spec()     :: #{
                            'method'    => send_method(),
                            'pid'       => process(),
                            'message'   => message(),
                            'frequency' => frequency(),
                            'function'  => fun(),
                            'arguments' => list(),
                            'tag'       => tag()
                        }.

-type frequency()       :: pos_integer() | {'random', pos_integer(), pos_integer()}.
-type process()         :: pid() | atom().
-type message()         :: term().
-type tag()             :: term().
-type send_method()     :: 'cast' | 'call' | 'info'.

-record(task, {
        key         :: undefined | {fun(), list()} | '_',  %{fun, arguments}

        frequency   :: #{frequency() := pos_integer()} | '_',

        tref        :: timer:tref() | '_',                  % current tref
        cast_fun    :: fun() | '_',                         % cast function (runtime helper data)
        tag         :: tag() | '_'
    }).

-type task()  :: #task{}.


-record(state, {
        ets_name :: atom()
    }).

-type state() :: #state{}.

