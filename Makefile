PROJECT = erlcron

dep_teaser = git https://github.com/spylik/teaser master

SHELL_DEPS = teaser sync
SHELL_OPTS = -pa ebin/ test/ -env ERL_LIBS deps -eval 'code:ensure_loaded(erlcron)' -run mlibs autotest_on_compile

include erlang.mk
