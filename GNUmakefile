# Logbook on GNUstep: the server, and its check.
#
# clang, libobjc2, gnustep-make and -base, FreeCoreData (its momc too) and
# ODataKit installed (the releases ../NativeORM2/.github/pins.env names);
# ORMKit's runtime built from ../NativeORM2 (ORMRuntime/, built first):
#
#   . /path/to/GNUstep.sh
#   make                     obj/logbook-server, Logbook.momd and
#                            Logbook.ormplans beside it; Logbook.app, the
#                            desktop app
#   make check               the server run, and asked over HTTP; the app
#                            driven from within against one (under X:
#                            xvfb-run -a make check)
#   make LB_SERVER_ONLY=yes  the server alone, on Foundation only
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

ifneq ($(LB_SERVER_ONLY),yes)
APP_NAME = Logbook
endif
Logbook_OBJC_FILES = $(wildcard AppKit/*.m) $(wildcard Shared/*.m) Model/Constraints/LogbookValidation.m
Logbook_XCDATAMODELD_FILES = Model/Logbook.xcdatamodeld
Logbook_COREDATA_CODEGEN = yes
Logbook_INCLUDE_DIRS = -IModel/Constraints -IShared -IAppKit -I$(ORMKIT) $(ODATASYNC_INCLUDE_DIRS)
Logbook_LIB_DIRS = -L$(ORMKIT)/ORMRuntime/$(GNUSTEP_OBJ_DIR)
Logbook_OBJCFLAGS = $(ODATAKIT_OBJCFLAGS) -Wall -Wno-unused-parameter
Logbook_GUI_LIBS += -lORMRuntime $(ODATASYNC_LIBS) -lRDLKitUI -lRDLKit
Logbook_RESOURCE_FILES = AppKit/MainMenu.xib AppKit/MainWindow.xib AppKit/ConnectPanel.xib AppKit/Preferences.xib \
	Model/Constraints/Logbook.ormplans $(wildcard Reports/*.rdl)
Logbook_MAIN_MODEL_FILE = MainMenu.xib

TOOL_NAME = logbook-server
logbook-server_OBJC_FILES = Server/LBServer.m Server/LBPermissions.m Model/Constraints/LogbookValidation.m
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
ifneq ($(LB_SERVER_ONLY),yes)
include $(GNUSTEP_MAKEFILES)/application.make
endif
include $(GNUSTEP_MAKEFILES)/tool.make
-include GNUmakefile.postamble

before-all::
	$(MAKE) -C $(ORMKIT)/ORMRuntime

# The server finds its model and tables beside itself.
after-all::
	rm -rf obj/Logbook.momd && momc Model/Logbook.xcdatamodeld obj/Logbook.momd
	cp Model/Constraints/Logbook.ormplans obj/

LB_RUN = LD_LIBRARY_PATH="$(ORMKIT)/ORMRuntime/$(GNUSTEP_OBJ_DIR)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"

check:: all
	$(LB_RUN) python3 Tests/serve-and-check.py obj/logbook-server
ifneq ($(LB_SERVER_ONLY),yes)
	$(LB_RUN) Tests/app-check.sh obj/logbook-server Logbook.app/Logbook
endif
