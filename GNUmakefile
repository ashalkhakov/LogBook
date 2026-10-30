# Logbook on GNUstep: the server, and its check.
#
# clang, libobjc2, gnustep-make and -base, FreeCoreData (its momc too),
# ODataKit, ORMKit (ORMRuntime, and its ormtool) and RDLKit installed: the
# releases .github/pins.env names (gnustep-release-actions' scripts/deps.sh
# linux unpacks them into /opt/gnustep):
#
#   . /path/to/GNUstep.sh
#   make                     obj/logbook-server, Logbook.momd and
#                            Logbook.ormplans beside it; Logbook.app, the
#                            desktop app
#   make check               the procedures checked over a store of their
#                            own; the server run, and asked over HTTP; two
#                            devices' offline stores synced through it; the
#                            app driven from within against one (under
#                            xvfb-run when there is no display)
#   make LB_SERVER_ONLY=yes  the server alone, on Foundation only
#
# The model is Model/Logbook.orm, and nothing else: ormtool generates from
# it, into obj/Model, the Core Data model (Logbook.xcdatamodeld, which
# coredata-model.make compiles and generates the classes of), the code and
# tables that keep its rules (Constraints/) and its listing (Logbook.forml).
#
# In docker, on ORMKit's image: .tools/gnustep.sh make check
# macOS: Makefile.apple.

ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh). macOS: make -f Makefile.apple)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

# What is generated from the model, and what generates it: ORMKit's ormtool,
# installed with its libraries.
LB_MODEL = $(GNUSTEP_OBJ_DIR)/Model
ORMTOOL ?= ormtool

ifneq ($(LB_SERVER_ONLY),yes)
APP_NAME = Logbook
endif
# The updater's GNUstep half (AppKit/LBUpdater.h); the Apple half is Makefile.apple's.
Logbook_OBJC_FILES = $(filter-out AppKit/LBUpdater-Apple.m,$(wildcard AppKit/*.m)) $(wildcard UDCalendar/*.m) $(wildcard UDQuantity/*.m) $(wildcard Shared/*.m) $(LB_MODEL)/Constraints/LogbookValidation.m
Logbook_XCDATAMODELD_FILES = $(LB_MODEL)/Logbook.xcdatamodeld
Logbook_COREDATA_CODEGEN = yes
Logbook_INCLUDE_DIRS = -I$(LB_MODEL)/Constraints -IShared -IAppKit -IUDCalendar -IUDQuantity $(ODATASYNC_INCLUDE_DIRS)
Logbook_OBJCFLAGS = $(ODATAKIT_OBJCFLAGS) -Wall -Wno-unused-parameter
# GSUpdater, the stack's: the app's updates (AppKit/LBUpdater-GNUstep.m).
Logbook_GUI_LIBS += -lORMRuntime $(ODATASYNC_LIBS) -lRDLKitUI -lRDLKit -lGSUpdater
Logbook_RESOURCE_FILES = AppKit/MainMenu.xib AppKit/MainWindow.xib AppKit/ConnectPanel.xib AppKit/Preferences.xib AppKit/Lists.xib AppKit/StockWindow.xib \
	AppKit/StockItem.xib AppKit/StockSale.xib AppKit/StockPurchase.xib AppKit/StockCount.xib AppKit/CatalogSettings.xib AppKit/Parts.xib AppKit/Logbook.png \
	$(LB_MODEL)/Constraints/Logbook.ormplans $(wildcard Reports/*.rdl)
Logbook_MAIN_MODEL_FILE = MainMenu.xib

TOOL_NAME = logbook-server lb-procedures-check lb-stock-check lb-sync-check
logbook-server_OBJC_FILES = Server/LBServer.m Server/LBPermissions.m Server/LBActions.m Server/LBStockActions.m \
	Shared/LBProcedures.m Shared/LBStockProcedures.m \
	$(LB_MODEL)/Constraints/LogbookValidation.m
logbook-server_XCDATAMODELD_FILES = $(LB_MODEL)/Logbook.xcdatamodeld
# Vehicle+CoreDataClass and the rest, generated from the model as it builds,
# as Xcode does (Codegen: Class Definition).
logbook-server_COREDATA_CODEGEN = yes
logbook-server_INCLUDE_DIRS = -I$(LB_MODEL)/Constraints -IShared $(ODATASYNC_INCLUDE_DIRS)
logbook-server_OBJCFLAGS = $(ODATAKIT_OBJCFLAGS) -Wall -Wno-unused-parameter
logbook-server_TOOL_LIBS += -lORMRuntime $(ODATASYNC_LIBS)
# The server opens FreeCoreData's SQL stores with dlopen: dlfcn-win32 on
# Windows, which names their DLLs its own way.
ifneq ($(filter mingw% windows%,$(GNUSTEP_TARGET_OS)),)
logbook-server_TOOL_LIBS += -ldl
logbook-server_CPPFLAGS += '-DLB_STORE_LIBRARY_FORMAT=@"%@-0.dll"'
endif

# The procedures checked over a store of the model's own.
lb-procedures-check_OBJC_FILES = Tests/LBProceduresCheck.m Shared/LBProcedures.m Shared/LBPlanned.m $(LB_MODEL)/Constraints/LogbookValidation.m
lb-procedures-check_XCDATAMODELD_FILES = $(LB_MODEL)/Logbook.xcdatamodeld
lb-procedures-check_COREDATA_CODEGEN = yes
lb-procedures-check_INCLUDE_DIRS = $(logbook-server_INCLUDE_DIRS)
lb-procedures-check_OBJCFLAGS = $(logbook-server_OBJCFLAGS)
lb-procedures-check_TOOL_LIBS += -lORMRuntime $(ODATASYNC_LIBS)

# The stock model's derivations and rules checked over a store of its own.
lb-stock-check_OBJC_FILES = Tests/LBStockCheck.m Shared/LBStockProcedures.m Shared/LBStockDisplay.m Shared/LBDisplay.m \
	Shared/LBProcedures.m \
	$(LB_MODEL)/Constraints/LogbookValidation.m
lb-stock-check_XCDATAMODELD_FILES = $(LB_MODEL)/Logbook.xcdatamodeld
lb-stock-check_COREDATA_CODEGEN = yes
lb-stock-check_INCLUDE_DIRS = $(logbook-server_INCLUDE_DIRS)
lb-stock-check_OBJCFLAGS = $(logbook-server_OBJCFLAGS)
lb-stock-check_TOOL_LIBS += -lORMRuntime $(ODATASYNC_LIBS)

# The offline store (the iOS app's) against a server: devices, signed in.
lb-sync-check_OBJC_FILES = Tests/LBSyncCheck.m Shared/LBLocalStore.m Shared/LBConflicts.m Shared/LBVehicleSummary.m \
	Shared/LBDisplay.m Shared/LBProcedures.m Shared/LBStockProcedures.m $(LB_MODEL)/Constraints/LogbookValidation.m
lb-sync-check_XCDATAMODELD_FILES = $(LB_MODEL)/Logbook.xcdatamodeld
lb-sync-check_COREDATA_CODEGEN = yes
lb-sync-check_INCLUDE_DIRS = $(logbook-server_INCLUDE_DIRS)
lb-sync-check_OBJCFLAGS = $(logbook-server_OBJCFLAGS)
lb-sync-check_TOOL_LIBS += -lORMRuntime $(ODATASYNC_LIBS)

include $(GNUSTEP_MAKEFILES)/coredata-model.make
-include GNUmakefile.preamble
ifneq ($(LB_SERVER_ONLY),yes)
include $(GNUSTEP_MAKEFILES)/application.make
endif
include $(GNUSTEP_MAKEFILES)/tool.make
-include GNUmakefile.postamble

# The model's outputs generated from the model where it, or ormtool, is
# newer. What reads them waits for this:
# coredata-model.make compiles the Core Data model, and generates its
# classes, before any target builds. (A rule of ours before that file
# would be make's default goal: they are all here, after it.)
.PHONY: lb-model
lb-model:
	@ormtool=$$(command -v $(ORMTOOL)) || { echo "no ormtool: ORMKit's release, installed (.github/pins.env)"; exit 1; }; \
	if [ ! -e $(LB_MODEL)/.made ] || [ Model/Logbook.orm -nt $(LB_MODEL)/.made ] || [ $$ormtool -nt $(LB_MODEL)/.made ]; then \
	  echo "Generating $(LB_MODEL) from Model/Logbook.orm"; \
	  rm -rf $(LB_MODEL) && mkdir -p $(LB_MODEL) && \
	  $(ORMTOOL) coredata Model/Logbook.orm \
	    $(LB_MODEL)/Logbook.xcdatamodeld Logbook --validation $(LB_MODEL)/Constraints >$(LB_MODEL)/mapping.txt && \
	  $(ORMTOOL) forml Model/Logbook.orm \
	    $(LB_MODEL)/Logbook.forml && \
	  touch $(LB_MODEL)/.made; \
	fi
# Generated by the make run first; the targets' own makes, which gnustep-make
# runs inside it, find them made.
LB_GENERATED = $(LB_MODEL)/Logbook.xcdatamodeld $(LB_MODEL)/Constraints/LogbookValidation.m \
	$(LB_MODEL)/Constraints/Logbook.ormplans
ifeq ($(MAKELEVEL),0)
$(LB_GENERATED): lb-model
	@:
_cd-codegen: lb-model
else
$(LB_GENERATED): ;
endif

before-all:: lb-model

# The server finds its model, tables and permissions beside itself; the
# permissions checked against the model by ODataKit's odatakit-permissions
# (installed with its libraries).
ODATAKIT_PERMISSIONS ?= odatakit-permissions
after-all::
	rm -rf obj/Logbook.momd && momc $(LB_MODEL)/Logbook.xcdatamodeld obj/Logbook.momd
	cp $(LB_MODEL)/Constraints/Logbook.ormplans obj/
	$(ODATAKIT_PERMISSIONS) check obj/Logbook.momd Server/Logbook.permissions.plist
	cp Server/Logbook.permissions.plist obj/

# Installed, the server finds them beside itself too.
LB_SERVER_FILES = Logbook.momd Logbook.ormplans Logbook.permissions.plist
after-install::
	@server=$$(find "$(GNUSTEP_TOOLS)" -type f -name logbook-server -perm -u+x | head -n 1); \
	  [ -n "$$server" ] || { echo "install: no logbook-server under $(GNUSTEP_TOOLS)"; exit 1; }; \
	  for f in $(LB_SERVER_FILES); do \
	    rm -rf "$$(dirname "$$server")/$$f" && cp -R obj/$$f "$$(dirname "$$server")/" || exit 1; \
	  done

# The app, under X: xvfb-run where there is no display.
XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))

check:: all
	obj/lb-procedures-check obj/Logbook.momd obj/Logbook.ormplans
	obj/lb-stock-check obj/Logbook.momd obj/Logbook.ormplans
	python3 Tests/serve-and-check.py obj/logbook-server
	Tests/sync-check.sh obj/logbook-server obj/lb-sync-check obj/Logbook.momd obj/Logbook.ormplans
ifneq ($(LB_SERVER_ONLY),yes)
	$(XVFB) Tests/app-check.sh obj/logbook-server Logbook.app/Logbook
endif
