#!/usr/bin/env python3
"""Write Logbook.xcodeproj and Logbook.xcworkspace from the source lists the
makefiles keep.

    python3 .tools/genxcodeproj.py

Regenerate after adding a source file rather than editing project.pbxproj by
hand. Object ids are derived from names, so the output is stable and diffs
stay small. The makefiles stay what builds Logbook (and all GNUstep reads);
the project is for working on it in Xcode.

The Model target generates what the others build on from Model/Logbook.orm,
by make -f Makefile.apple xcode-model (with ORMKit's ormtool, .deps/bin).
ORMKit's ORMRuntime, ODataKit's frameworks and RDLKit's are the XCFrameworks
in .deps, by the versions the pins name (gnustep-release-actions'
scripts/deps.sh apple): each target links and embeds the slice for the
platform chosen.
"""
import glob
import hashlib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = "Logbook"


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def make_value(path, var):
    """A makefile variable's text, continuation lines joined."""
    text = open(os.path.join(ROOT, path)).read().replace("\\\n", " ")
    words = []
    for m in re.finditer(r"^%s\s*[:+]?=\s*(.*)$" % re.escape(var), text, re.M):
        words.append(m.group(1))
    return " ".join(words)


def expand(text):
    """Source paths of a list as the makefiles write it: $(wildcard ...) and
    $(filter-out ...) evaluated, what the build generates (the model's
    paths) left out, as Xcode/LogbookModel.m compiles that."""
    def wildcard(m):
        return " ".join(sorted(os.path.relpath(p, ROOT) for p in glob.glob(os.path.join(ROOT, m.group(1)))))

    def filter_out(m):
        out = set(m.group(1).split())
        return " ".join(w for w in m.group(2).split() if w not in out)

    text = re.sub(r"\$\(wildcard ([^)]*)\)", wildcard, text)
    text = re.sub(r"\$\(filter-out ([^,]*),([^)]*)\)", filter_out, text)
    return [w for w in text.split() if not w.startswith("$(")]


APP_SOURCES = expand(make_value("GNUmakefile", "Logbook_OBJC_FILES"))
APP_RESOURCES = expand(make_value("GNUmakefile", "Logbook_RESOURCE_FILES"))
SERVER_SOURCES = expand(make_value("GNUmakefile", "logbook-server_OBJC_FILES"))
PROCEDURES_SOURCES = expand(make_value("GNUmakefile", "lb-procedures-check_OBJC_FILES"))
SYNC_SOURCES = expand(make_value("GNUmakefile", "lb-sync-check_OBJC_FILES"))
IOS_SOURCES = expand(make_value("Makefile.apple", "IOS_SOURCES"))
MODEL_CODE = "Xcode/LogbookModel.m"
DOCS = ["README.md", "Makefile.apple", "GNUmakefile"] + sorted(os.path.relpath(p, ROOT)
                                                              for p in glob.glob(os.path.join(ROOT, "docs", "*.md")))
ODATAKIT = ["ODataKit", "OTelKit", "ODataIncrementalStore", "HTTPServerKit", "ODataService", "ODataSync"]
RDLKIT = ["RDLKit", "RDLKitUI"]

objects = {}  # id -> (comment, fields)


def add(ident, comment, fields):
    objects[ident] = (comment, fields)
    return ident


def q(s):
    if re.fullmatch(r"[A-Za-z0-9_./$]+", s):
        return s
    return '"' + s.replace('"', '\\"') + '"'


def names(ids):
    return ["%s /* %s */" % (i, objects[i][0]) for i in ids]


FILE_TYPES = {".m": "sourcecode.c.objc", ".h": "sourcecode.c.h", ".md": "net.daringfireball.markdown",
              ".plist": "text.plist.xml", ".xib": "file.xib", ".xcconfig": "text.xcconfig",
              ".xcassets": "folder.assetcatalog", ".rdl": "text.xml", ".orm": "text.xml", ".py": "text.script.python",
              ".sh": "text.script.sh"}


def fileref(path):
    name = os.path.basename(path)
    return add(oid("ref", path), name, [
        ("isa", "PBXFileReference"),
        ("lastKnownFileType", FILE_TYPES.get(os.path.splitext(name)[1], "text")),
        ("path", q(name)),
        ("sourceTree", '"<group>"'),
    ])


def product(name, file_type, path):
    return add(oid("product", name), path, [
        ("isa", "PBXFileReference"),
        ("explicitFileType", q(file_type)),
        ("includeInIndex", "0"),
        ("path", q(path)),
        ("sourceTree", "BUILT_PRODUCTS_DIR"),
    ])


def buildfile(target, ref, settings=None):
    fields = [("isa", "PBXBuildFile"), ("fileRef", "%s /* %s */" % (ref, objects[ref][0]))]
    if settings:
        fields.append(("settings", settings))
    return add(oid("build", target, ref), objects[ref][0], fields)


def phase(isa, target, name, files, extra=()):
    fields = [("isa", isa), ("buildActionMask", "2147483647"), ("files", names(files))]
    fields.extend(extra)
    fields.append(("runOnlyForDeploymentPostprocessing", "0"))
    return add(oid("phase", target, name), name, fields)


def script(target, name, text, always=True):
    return phase("PBXShellScriptBuildPhase", target, name, [], [
        ("alwaysOutOfDate", "1" if always else "0"),
        ("inputFileListPaths", []), ("inputPaths", []), ("name", q(name)),
        ("outputFileListPaths", []), ("outputPaths", []),
        ("shellPath", "/bin/sh"),
        ("shellScript", '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")),
        ("showEnvVarsInLog", "0"),
    ])


# File references, each once, by path.
ALL_FILES = sorted(set(APP_SOURCES + APP_RESOURCES + SERVER_SOURCES + PROCEDURES_SOURCES + SYNC_SOURCES + IOS_SOURCES
                       + [MODEL_CODE, "AppKit/Info.plist", "iOS/Info.plist", "iOS/Logbook-iOS.xcconfig",
                          "iOS/Assets.xcassets", "Model/Logbook.orm"]
                       + [os.path.relpath(h, ROOT) for d in ("AppKit", "Shared", "Server", "iOS", "UDCalendar",
                                                             "UDQuantity", "Tests")
                          for h in glob.glob(os.path.join(ROOT, d, "*.h"))]
                       + [os.path.relpath(r, ROOT) for r in glob.glob(os.path.join(ROOT, "UD*", "README.md"))]))
refs = {f: fileref(f) for f in ALL_FILES}
doc_refs = {d: fileref(d) for d in DOCS}
for d in DOCS:
    objects[doc_refs[d]] = (objects[doc_refs[d]][0], [(k, q(d) if k == "path" else v)
                                                        for k, v in objects[doc_refs[d]][1]])


def sdkframework(name):
    return add(oid("sdk", name), name + ".framework", [
        ("isa", "PBXFileReference"),
        ("lastKnownFileType", "wrapper.framework"),
        ("name", name + ".framework"),
        ("path", "System/Library/Frameworks/%s.framework" % name),
        ("sourceTree", "SDKROOT"),
    ])


def xcframework(name, directory):
    return add(oid("xcframework", name), name + ".xcframework", [
        ("isa", "PBXFileReference"),
        ("lastKnownFileType", "wrapper.xcframework"),
        ("name", name + ".xcframework"),
        ("path", "%s/%s.xcframework" % (directory, name)),
        ("sourceTree", "SOURCE_ROOT"),
    ])


sdk = {f: sdkframework(f) for f in ("Foundation", "CoreData", "AppKit", "UIKit", "Security")}
odatakit = {f: xcframework(f, ".deps") for f in ODATAKIT}
rdlkit = {f: xcframework(f, ".deps") for f in RDLKIT}
# ORMKit's runtime, of its release: macOS and iOS slices.
ormruntime = xcframework("ORMRuntime", ".deps")

p_app = product("Logbook", "wrapper.application", "Logbook.app")
p_ios = product("Logbook-iOS", "wrapper.application", "Logbook.app")
p_server = product("logbook-server", "compiled.mach-o.executable", "logbook-server")
p_procedures = product("lb-procedures-check", "compiled.mach-o.executable", "lb-procedures-check")
p_sync = product("lb-sync-check", "compiled.mach-o.executable", "lb-sync-check")

EMBED = "{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }"

# What the build generates, beside a tool or in an app's resources.
COPY_MODEL = """# The model, compiled, and its tables (made by the Model target).
dest="$TARGET_BUILD_DIR/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-.}"
mkdir -p "$dest"
rsync -a --delete "$SRCROOT/build/Logbook.momd/" "$dest/Logbook.momd/"
cp "$SRCROOT/build/Logbook.ormplans" "$dest/"
"""


def sources(target, files):
    return phase("PBXSourcesBuildPhase", target, "Sources",
                 [buildfile(target, refs[s]) for s in files + [MODEL_CODE]])


def frameworks(target, linked):
    return phase("PBXFrameworksBuildPhase", target, "Frameworks", [buildfile(target, f) for f in linked])


def embed(target, embedded):
    return phase("PBXCopyFilesBuildPhase", target, "Embed Frameworks",
                 [buildfile(target + ".embed", f, EMBED) for f in embedded],
                 [("dstPath", '""'), ("dstSubfolderSpec", "10"), ("name", q("Embed Frameworks"))])


ODATA = [odatakit[f] for f in ODATAKIT]

model_script = script("Model", "Generate from Model/Logbook.orm", """# Generated by make, as on the command line, and out of Xcode's own
# environment, which would mislead the tools it runs (momc, ormtool).
exec env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" DEVELOPER_DIR="$DEVELOPER_DIR" \\
  make -C "$SRCROOT" -f Makefile.apple xcode-model
""")

app_phases = [
    sources("Logbook", APP_SOURCES),
    phase("PBXResourcesBuildPhase", "Logbook", "Resources", [buildfile("Logbook", refs[r]) for r in APP_RESOURCES]),
    script("Logbook", "Copy the model", COPY_MODEL),
    frameworks("Logbook", [ormruntime] + ODATA + [rdlkit[f] for f in RDLKIT]
               + [sdk["AppKit"], sdk["CoreData"], sdk["Foundation"]]),
    embed("Logbook", [ormruntime] + ODATA + [rdlkit[f] for f in RDLKIT]),
]
ios_phases = [
    sources("Logbook-iOS", IOS_SOURCES),
    phase("PBXResourcesBuildPhase", "Logbook-iOS", "Resources", [buildfile("Logbook-iOS", refs["iOS/Assets.xcassets"])]),
    script("Logbook-iOS", "Copy the model", COPY_MODEL + """# The self-test's photo of a receipt, in the simulator's app only.
if [ "$PLATFORM_NAME" = iphonesimulator ]; then cp "$SRCROOT/Tests/receipt-photo.jpg" "$dest/SelfTestReceipt.jpg"; fi
"""),
    frameworks("Logbook-iOS", [ormruntime] + ODATA + [sdk["UIKit"], sdk["CoreData"], sdk["Foundation"], sdk["Security"]]),
    embed("Logbook-iOS", [ormruntime] + ODATA),
]


def tool_phases(name, files):
    return [sources(name, files), script(name, "Copy the model", COPY_MODEL),
            frameworks(name, [ormruntime] + ODATA + [sdk["CoreData"], sdk["Foundation"]])]


# Groups.
def group(key, name, children, path=None):
    fields = [("isa", "PBXGroup"), ("children", names(children))]
    fields.append(("path", q(path)) if path else ("name", q(name)))
    fields.append(("sourceTree", '"<group>"'))
    return add(oid("group", key), name, fields)


def by_stem(files):
    return sorted(files, key=lambda n: (os.path.splitext(n)[0], os.path.splitext(n)[1] != ".h"))


dir_groups = []
for d in sorted({os.path.dirname(f) for f in ALL_FILES}):
    members = [f for f in ALL_FILES if os.path.dirname(f) == d]
    dir_groups.append(group(d, d, [refs[f] for f in by_stem(members)], d))
g_docs = group("Docs", "Docs", [doc_refs[d] for d in DOCS])
g_frameworks = group("Frameworks", "Frameworks", [ormruntime] + ODATA + [rdlkit[f] for f in RDLKIT]
                     + [sdk[f] for f in ("Foundation", "CoreData", "AppKit", "UIKit", "Security")])
g_products = group("Products", "Products", [p_app, p_ios, p_server, p_procedures, p_sync])
g_main = group("main", PROJECT, [g_docs] + dir_groups + [g_frameworks, g_products])
objects[g_main] = ("", [(k, v) for k, v in objects[g_main][1] if k != "name"])


# Build settings.
def settings(d):
    return "{\n" + "".join("\t\t\t\t%s = %s;\n" % (k, v) for k, v in sorted(d.items())) + "\t\t\t}"


HEADERS = '("$(SRCROOT)/Shared", "$(SRCROOT)/AppKit", "$(SRCROOT)/UDCalendar", "$(SRCROOT)/UDQuantity", ' \
          '"$(SRCROOT)/Server", "$(SRCROOT)/iOS", "$(SRCROOT)/build/Model/Constraints", "$(SRCROOT)/build/Generated")'
COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
    "CODE_SIGN_IDENTITY": q("-"),
    "CODE_SIGN_STYLE": "Manual",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "HEADER_SEARCH_PATHS": HEADERS,
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "WARNING_CFLAGS": q("-Wall -Wno-unused-parameter"),
    "SDKROOT": "macosx",
}
DEBUG = dict(COMMON, **{"DEBUG_INFORMATION_FORMAT": "dwarf", "GCC_OPTIMIZATION_LEVEL": "0", "ONLY_ACTIVE_ARCH": "YES",
                        "GCC_PREPROCESSOR_DEFINITIONS": q("DEBUG=1")})
RELEASE = dict(COMMON, **{"DEBUG_INFORMATION_FORMAT": q("dwarf-with-dsym")})

TOOL = {"LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path")', "PRODUCT_NAME": q("$(TARGET_NAME)")}
TARGET_SETTINGS = {
    "Model": {"PRODUCT_NAME": q("$(TARGET_NAME)"), "SDKROOT": "auto",
              "SUPPORTED_PLATFORMS": q("macosx iphoneos iphonesimulator")},
    "Logbook": {
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": q("AppKit/Info.plist"),
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks")',
        "PRODUCT_BUNDLE_IDENTIFIER": "io.github.ashalkhakov.Logbook",
        "PRODUCT_NAME": "Logbook",
    },
    # The rest is iOS/Logbook-iOS.xcconfig's (its base configuration): the
    # name, the bundle id, versions, the deployment target, the server it
    # offers first, and Local.xcconfig's team, which signs it for a device.
    "Logbook-iOS": {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_IDENTITY": q("Apple Development"),
        "CODE_SIGN_STYLE": "Automatic",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": q("iOS/Info.plist"),
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": q("iphoneos iphonesimulator"),
    },
    "logbook-server": TOOL,
    "lb-procedures-check": TOOL,
    "lb-sync-check": TOOL,
}
xcconfig_ref = refs["iOS/Logbook-iOS.xcconfig"]


def configs(key, debug, release, base=None):
    ids = []
    for name, values in (("Debug", debug), ("Release", release)):
        fields = [("isa", "XCBuildConfiguration")]
        if base:
            fields.append(("baseConfigurationReference", "%s /* %s */" % (base, objects[base][0])))
        fields += [("buildSettings", settings(values)), ("name", name)]
        ids.append(add(oid("cfg", key, name), name, fields))
    return add(oid("cfglist", key), "Build configuration list for " + key, [
        ("isa", "XCConfigurationList"),
        ("buildConfigurations", names(ids)),
        ("defaultConfigurationIsVisible", "0"),
        ("defaultConfigurationName", "Release"),
    ])


project_id = oid("project")


def dependency(target, on_id, on_name):
    proxy = add(oid("proxy", target, on_name), "PBXContainerItemProxy", [
        ("isa", "PBXContainerItemProxy"),
        ("containerPortal", "%s /* Project object */" % project_id),
        ("proxyType", "1"),
        ("remoteGlobalIDString", on_id),
        ("remoteInfo", on_name),
    ])
    return add(oid("dep", target, on_name), "PBXTargetDependency", [
        ("isa", "PBXTargetDependency"),
        ("target", "%s /* %s */" % (on_id, on_name)),
        ("targetProxy", "%s /* PBXContainerItemProxy */" % proxy),
    ])


t_model = oid("target", "Model")
add(t_model, "Model", [
    ("isa", "PBXAggregateTarget"),
    ("buildConfigurationList", '%s /* Build configuration list for PBXAggregateTarget "Model" */'
     % configs("Model", TARGET_SETTINGS["Model"], TARGET_SETTINGS["Model"])),
    ("buildPhases", names([model_script])),
    ("dependencies", []),
    ("name", "Model"),
    ("productName", "Model"),
])


def target(name, phases, prod, ptype, base=None):
    cfglist = configs(name, TARGET_SETTINGS[name], TARGET_SETTINGS[name], base)
    return add(oid("target", name), name, [
        ("isa", "PBXNativeTarget"),
        ("buildConfigurationList", '%s /* Build configuration list for PBXNativeTarget "%s" */' % (cfglist, name)),
        ("buildPhases", names(phases)),
        ("buildRules", []),
        ("dependencies", names([dependency(name, t_model, "Model")])),
        ("name", q(name)),
        ("productName", q(name)),
        ("productReference", "%s /* %s */" % (prod, objects[prod][0])),
        ("productType", '"%s"' % ptype),
    ])


t_app = target("Logbook", app_phases, p_app, "com.apple.product-type.application")
t_ios = target("Logbook-iOS", ios_phases, p_ios, "com.apple.product-type.application", xcconfig_ref)
t_server = target("logbook-server", tool_phases("logbook-server", SERVER_SOURCES), p_server,
                  "com.apple.product-type.tool")
t_procedures = target("lb-procedures-check", tool_phases("lb-procedures-check", PROCEDURES_SOURCES), p_procedures,
                      "com.apple.product-type.tool")
t_sync = target("lb-sync-check", tool_phases("lb-sync-check", SYNC_SOURCES), p_sync, "com.apple.product-type.tool")

cl_project = configs("project", DEBUG, RELEASE)
add(project_id, "Project object", [
    ("isa", "PBXProject"),
    ("attributes", "{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t}"),
    ("buildConfigurationList", '%s /* Build configuration list for PBXProject "%s" */' % (cl_project, PROJECT)),
    ("compatibilityVersion", '"Xcode 14.0"'),
    ("developmentRegion", "en"),
    ("hasScannedForEncodings", "0"),
    ("knownRegions", ["en", "Base"]),
    ("mainGroup", g_main),
    ("productRefGroup", "%s /* Products */" % g_products),
    ("projectDirPath", '""'),
    ("projectRoot", '""'),
    ("targets", names([t_model, t_app, t_ios, t_server, t_procedures, t_sync])),
])


def value(v, indent):
    if isinstance(v, list):
        if not v:
            return "(\n%s)" % ("\t" * indent)
        inner = "".join("%s%s,\n" % ("\t" * (indent + 1), x) for x in v)
        return "(\n%s%s)" % (inner, "\t" * indent)
    return v


def render():
    by_isa = {}
    for ident, (comment, fields) in objects.items():
        by_isa.setdefault(dict(fields)["isa"], []).append((ident, comment, fields))
    out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;",
           "\tobjects = {"]
    for isa in sorted(by_isa):
        out.append("")
        out.append("/* Begin %s section */" % isa)
        for ident, comment, fields in sorted(by_isa[isa]):
            head = "\t\t%s /* %s */ = {" % (ident, comment) if comment else "\t\t%s = {" % ident
            out.append(head)
            for k, v in fields:
                out.append("\t\t\t%s = %s;" % (k, value(v, 3)))
            out.append("\t\t};")
        out.append("/* End %s section */" % isa)
    out += ["\t};", "\trootObject = %s /* Project object */;" % project_id, "}", ""]
    return "\n".join(out)


proj = os.path.join(ROOT, PROJECT + ".xcodeproj")
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(proj, "project.pbxproj"), "w") as f:
    f.write(render())

# The workspace: this project.
workspace = os.path.join(ROOT, PROJECT + ".xcworkspace")
os.makedirs(workspace, exist_ok=True)
with open(os.path.join(workspace, "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n'
            '   <FileRef\n      location = "group:%s.xcodeproj">\n   </FileRef>\n'
            '</Workspace>\n' % PROJECT)


def reference(target_id, name, path):
    return ('<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "%s" '
            'BlueprintName = "%s" ReferencedContainer = "container:%s.xcodeproj"></BuildableReference>'
            % (target_id, path, name, PROJECT))


def scheme(name, builds, run=None, arguments=(), directory=None):
    entries = "".join('<BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" '
                      'buildForArchiving = "YES" buildForAnalyzing = "YES">%s</BuildActionEntry>' % b for b in builds)
    runnable = '<BuildableProductRunnable runnableDebuggingMode = "0">%s</BuildableProductRunnable>' % run if run else ""
    workdir = ('useCustomWorkingDirectory = "YES" customWorkingDirectory = "%s"' % directory if directory
               else 'useCustomWorkingDirectory = "NO"')
    args = ""
    if arguments:
        args = "<CommandLineArguments>%s</CommandLineArguments>" % "".join(
            '<CommandLineArgument argument = "%s" isEnabled = "YES"></CommandLineArgument>' % a for a in arguments)
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion = "1600" version = "1.7">'
           '<BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">'
           '<BuildActionEntries>%s</BuildActionEntries></BuildAction>'
           '<TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
           'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">'
           '<Testables></Testables></TestAction>'
           '<LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
           'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" '
           '%s ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" '
           'debugServiceExtension = "internal" allowLocationSimulation = "YES">%s%s</LaunchAction>'
           '<ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" '
           'useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES"></ProfileAction>'
           '<AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>'
           '<ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>'
           '</Scheme>\n') % (entries, workdir, runnable, args)
    with open(os.path.join(proj, "xcshareddata", "xcschemes", name + ".xcscheme"), "w") as f:
        f.write(xml)


model_ref = reference(t_model, "Model", "Model")
app_ref = reference(t_app, "Logbook", "Logbook.app")
ios_ref = reference(t_ios, "Logbook-iOS", "Logbook.app")
server_ref = reference(t_server, "logbook-server", "logbook-server")
procedures_ref = reference(t_procedures, "lb-procedures-check", "lb-procedures-check")
sync_ref = reference(t_sync, "lb-sync-check", "lb-sync-check")
scheme("Model", [model_ref])
scheme("Logbook", [app_ref], run=app_ref)
scheme("Logbook-iOS", [ios_ref], run=ios_ref)
# Its store in build/ (the default's place is the working directory), on
# the port the apps offer first; anonymous requests allowed, to try it.
scheme("logbook-server", [server_ref], run=server_ref, directory="$(SRCROOT)/build",
       arguments=["-StoreURL", "$(SRCROOT)/build/Logbook.sqlite", "-Port", "8080"])
scheme("lb-procedures-check", [procedures_ref], run=procedures_ref,
       arguments=["$(BUILT_PRODUCTS_DIR)/Logbook.momd", "$(BUILT_PRODUCTS_DIR)/Logbook.ormplans"])
scheme("lb-sync-check", [sync_ref], run=sync_ref)
print("wrote", proj)
