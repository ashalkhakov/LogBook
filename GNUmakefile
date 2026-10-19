# Logbook on GNUstep: the server, and its check.
#
# clang, libobjc2, gnustep-make and -base, FreeCoreData (its momc too) and
# ODataKit installed (the releases ../NativeORM2/.github/pins.env names);
# ORMKit's runtime built from ../NativeORM2 (ORMRuntime/, built first):
#
#   . /path/to/GNUstep.sh
#   make                     obj/logbook-server, Logbook.momd and
#                            Logbook.ormplans beside it
#   make check               the server run, and asked over HTTP
#
# In docker, on ORMKit's image: .tools/gnustep.sh make check
# macOS: Makefile.apple.

ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh). macOS: make -f Makefile.apple)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

ORMKIT ?= $(CURDIR)/../NativeORM2

TOOL_NAME = logbook-server
logbook-server_OBJC_FILES = Server/LBServer.m Model/Constraints/LogbookValidation.m
logbook-server_XCDATAMODELD_FILES = Model/Logbook.xcdatamodeld
# Vehicle+CoreDataClass and the rest, generated from the model as it builds,
# as Xcode does (Codegen: Class Definition).
logbook-server_COREDATA_CODEGEN = yes
logbook-server_INCLUDE_DIRS = -IModel/Constraints -I$(ORMKIT) $(ODATASYNC_INCLUDE_DIRS)
logbook-server_LIB_DIRS = -L$(ORMKIT)/ORMRuntime/$(GNUSTEP_OBJ_DIR)
logbook-server_OBJCFLAGS = $(ODATAKIT_OBJCFLAGS) -Wall -Wno-unused-parameter
logbook-server_TOOL_LIBS += -lORMRuntime $(ODATASYNC_LIBS)

include $(GNUSTEP_MAKEFILES)/coredata-model.make
-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/tool.make
-include GNUmakefile.postamble

before-all::
	$(MAKE) -C $(ORMKIT)/ORMRuntime

# The server finds its model and tables beside itself.
after-all::
	rm -rf obj/Logbook.momd && momc Model/Logbook.xcdatamodeld obj/Logbook.momd
	cp Model/Constraints/Logbook.ormplans obj/

check:: all
	LD_LIBRARY_PATH="$(ORMKIT)/ORMRuntime/$(GNUSTEP_OBJ_DIR)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	  python3 Tests/serve-and-check.py obj/logbook-server
