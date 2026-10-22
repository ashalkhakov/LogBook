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
// The self-test to be run, against the server at root, before the app
// starts: its user named for this run, the user's saved settings noted (a
// self-test leaves them as they were, and checks it did).
FOUNDATION_EXPORT void LBSelfTestBegin(NSURL *root);
FOUNDATION_EXPORT void LBRunSelfTest(LBMainWindowController *window);

// A setting kept: the user's, saved; during a self-test for this run only
// (the argument domain, over everything else and never saved), so that a
// self-test leaves the user's settings as they were, and theirs do not
// reach it. nil removes it.
FOUNDATION_EXPORT void LBSetDefault(NSString *key, id _Nullable value);

NS_ASSUME_NONNULL_END
