PROJECT = erlcron

TEST_ERLC_OPTS += +warn_export_vars +warn_shadow_vars +warn_obsolete_guard +debug_info

#ERLC_OPTS += +warn_export_vars +warn_shadow_vars +warn_obsolete_guard +warn_missing_spec -Werror

dep_teaser = git https://github.com/spylik/teaser master

TEST_DEPS = teaser

ifeq ($(USER),travis)
    TEST_DEPS += covertool
	ERLC_OPTS += +warn_export_vars +warn_shadow_vars +warn_obsolete_guard +warn_missing_spec -Werror
    dep_covertool = git https://github.com/idubrov/covertool
endif

SHELL_DEPS = sync lager

SHELL_OPTS = -pa ebin/ test/ -env ERL_LIBS deps -eval 'mlibs:discover(),lager:start()' -run mlibs autotest_on_compile

include erlang.mk
