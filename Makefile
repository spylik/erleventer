PROJECT = erleventer

# --------------------------------------------------------------------
# Compilation.
# --------------------------------------------------------------------

# if ERLC_OPTS not defined in parent project, we going to define by our-self
ERLC_OPTS ?= +warn_export_all +warn_export_vars +warn_unused_import +warn_untyped_record +warn_missing_spec +warn_missing_spec_all -Werror

# if MODE is not defined it means we are in development enviroment
ifeq ($(MODE),release)
ERLC_OPTS += +native
ERLC_OPTS += +'{hipe, [o3]}'
else
ERLC_OPTS += +debug_info
endif

TEST_ERLC_OPTS += +warn_export_vars +warn_shadow_vars +warn_obsolete_guard +debug_info

# --------------------------------------------------------------------
# Dependencies.
# --------------------------------------------------------------------

# if we part of deps directory, we using $(CURDIR)../ as DEPS_DIR
ifeq ($(shell basename $(shell dirname $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST)))))), deps)
    DEPS_DIR ?= $(shell dirname $(CURDIR))
endif

dep_teaser = git https://github.com/spylik/teaser master

TEST_DEPS = teaser

ifeq ($(USER),travis)
    TEST_DEPS += covertool
	ERLC_OPTS += +warn_export_vars +warn_shadow_vars +warn_obsolete_guard +warn_missing_spec -Werror
    dep_covertool = git https://github.com/idubrov/covertool
endif

# --------------------------------------------------------------------
# Development enviroment ("make shell" to run it).
# --------------------------------------------------------------------

SHELL_DEPS = teaser sync

SHELL_OPTS = -config ${DEPS_DIR}/teaser/sys.config +c true +C multi_time_warp -pa ebin/ test/ -eval 'mlibs:discover()' -env ERL_LIBS deps -run mlibs autotest_on_compile

# --------------------------------------------------------------------
# We using erlang.mk
# --------------------------------------------------------------------

include erlang.mk
