% debug macros (development only, will not available once compiled in release mode)
-ifndef(release).
    -define(here, error_logger:info_msg("(~p)~p: we are here", [?LINE,?MODULE]), true).
    -define(debug(Msg), error_logger:info_msg(lists:concat(["(~p)~p: ", Msg])), true).
    -define(debug(Msg,Arg),
        error_logger:info_msg(lists:concat(["(~p)~p: ", Msg]), lists:append([?LINE,?MODULE], Arg)), true
    ).
-else.
    -define(here, true).
    -define(debug(Msg), true).
    -define(debug(Msg,Arg), true).
-endif.

% warning macros (will be available both in development and release mode)
-define(warning(Msg,Arg),
        error_logger:warning_msg(lists:concat(["(~p)~p: ", Msg]), lists:append([?LINE,?MODULE], Arg))
    ).

% got undefined message with standart format
-define(undefined(Arg),
        {current_function, {M, F, A}} = process_info(self(), current_function),
        RegisteredName = case process_info(self(), registered_name) of 
            [] -> unregistered;
            {registered_name, Name} -> Name
        end,
        error_logger:warning_msg("(~p)~p:~p/~p (~p, ~p) something undefined:~n~p", [?LINE,M,F,A,self(),RegisteredName,Arg])
    ).
% got undefined message with custom format
-define(undefined(Msg,Arg),
        {current_function, {M, F, A}} = process_info(self(), current_function),
        RegisteredName = case process_info(self(), registered_name) of 
            [] -> unregistered;
            {registered_name, Name} -> Name
        end,
        error_logger:warning_msg(lists:concat(["(~p)~p:~p/~p (~p, ~p)", Msg]), [?LINE,M,F,A,self(),RegisteredName,Arg])
    ).
