% todo: suport start_ops
-type start_ops()   :: #{
        'register'      => register_as(),
        'cast_on_add'   => boolean() % default false
    }.
-type register_as() :: {'local', atom()} | {'global', term()}.


-type cancel_ops()      :: [
                              {'frequency', frequency()}
                            | {'pid', process()}
                            | {'method', send_method()}
                            | {'message', message()}
                            | {'function', fun()}
                            | {'moduke', module()}
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

-type frequency()       :: pos_integer().
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

