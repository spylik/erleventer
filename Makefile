PROJECT = erlcron

dep_teaser = git https://github.com/spylik/teaser master

SHELL_DEPS = sync teaser
SHELL_OPTS = -pa ebin/ test/ -env ERL_LIBS deps -run mlibs autotest_on_compile

include erlang.mk
