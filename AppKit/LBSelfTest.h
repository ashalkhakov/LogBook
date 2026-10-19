// The app driven from within, against a running server (Tests/app-check.py
// starts one): what a user does, through the window's controls (their
// identifiers in the XIBs), and what the server has after. Each check a
// line ("ok" or "FAIL"); the app quits, 1 when one failed.
//
//   Logbook --self-test http://127.0.0.1:8080/odata/

#import <AppKit/AppKit.h>

@class LBMainWindowController;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSURL *_Nullable LBSelfTestRoot;
FOUNDATION_EXPORT void LBRunSelfTest(LBMainWindowController *window);

NS_ASSUME_NONNULL_END
