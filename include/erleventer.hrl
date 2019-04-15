% todo: suport start_ops
-type start_ops()   :: #{
        'register'      => register_as(),
        'cast_on_add'   => boolean() % default false
    }.
-type register_as() :: {'local', atom()} | {'global', term()}.


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

-type cancel_ops()      :: [
                              {'frequency', frequency()}
                            | {'pid', process()}
                            | {'method', send_method()}
                            | {'message', message()}
                            | {'function', fun()}
                            | {'module', module()}
                            | {'arguments', list()}
                            | {'tag', tag()}
                        ]
                        | #{
                            'frequency' => frequency(),
                            'pid'       => process(),
                            'method'    => send_method(),
                            'message'   => message(),
                            'function'  => fun(),
                            'module'    => module(),
                            'arguments' => list(),
                            'tag'       => tag()
                        }.

-type frequency()       :: pos_integer() | {'random_between', pos_integer(), pos_integer()}.
-type process()         :: pid() | atom().
-type message()         :: term().
-type tag()             :: term().
-type send_method()     :: 'cast' | 'call' | 'info'.

-record(task, {
        frequency   :: #{frequency() := pos_integer()} | '_',

        % send message task
        pid         :: 'undefined' | atom() | pid() | '_',
        method      :: 'undefined' | send_method() | '_',
        message     :: 'undefined' | message() | '_',

        % fun apply task
        function    :: 'undefined' | fun() | '_',

        % mfa apply task adding module
        module      :: 'undefined' | module() | '_',

        % argument for fun / mfa apply task
        arguments   :: 'undefined' | list() | '_',

        tref        :: timer:tref() | '_',                  % current tref
        cast_fun    :: fun() | '_',                         % cast function (runtime helper data)
        tag         :: tag() | '_'
    }).

-type task()  :: #task{}.


-record(state, {
        etsname :: atom()
    }).

-type state() :: #state{}.

