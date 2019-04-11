-type frequency()       :: pos_ingeger().
-type process()         :: pid() | atom().
-type message()         :: term().
-type tag()             :: term().
-type send_method()     :: 'cast' | 'call' | 'info'.
-type cancel_ops()      :: [
                            {'freq', frequency()}
                            | {'pid', process()}
                            | {'method', send_method()}
                            | {'message', message()}
                            | {'function', fun()}
                            | {'moduke', module()}
                            | {'arguments', list()}
                            | {'tag', tag()}
                        ]
                        | #{
                            'freq'      => frequency(),
                            'pid'       => process(),
                            'method'    => send_method(),
                            'message'   => message(),
                            'function'  => fun(),
                            'module'    => module(),
                            'arguments' => list(),
                            'tag'       => tag()
                        }.

-record(task, {
        freq        :: #{frequency() := pos_integer()} | '_',

        % send message task
        pid         :: 'undefined' | atom() | pid() | '_',
        method      :: 'undefined' | send_method() | '_',
        message     :: 'undefined' | message() | '_',

        % fun apply task
        function    :: 'undefined' | fun() | '_',

        % mfa apply task
        module      :: 'undefined' | module() | '_',
        function    :: 'undefined' | atom() | '_',

        % argument for fun / mfa apply task
        arguments   :: 'undefined' | list() | '_',

        tref        :: timer:tref() | '_',                  % current tref
        cast_fun    :: fun(),                               % cast function (runtime helper data)
        tag         :: tag() | '_'
    }).

-type task()  :: #task{}.


-record(state, {
        etsname :: atom()
    }).

-type state() :: #state{}.

