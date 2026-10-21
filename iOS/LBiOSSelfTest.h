// Logbook for iOS, --self-test <service root>: the app driven from within,
// as the desktop's is (AppKit/LBSelfTest.h), against a server with no
// sign-in (Tests/ios-self-test.sh starts one): signed in by email; a
// vehicle added; a fill-up logged with sync off, sent once it is on; a
// service of a schedule's task closing its reminder here, the server
// agreeing (the same reminders, by id); a record changed here and at the
// server, each way of settling the conflict; the vehicle shared by its
// owner, and a driver's session offering no sharing; a receipt's photo; a
// deontic rule said before saving, a refusal with the rule's words. PASS or
// FAIL a line on standard error, then "self-test: passed" or "FAILED"; the
// app exits with the number that failed.

#pragma once
#import "LBiOSApp.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSURL *_Nullable LBSelfTestRoot;
FOUNDATION_EXPORT void LBStartSelfTest(LBiOSAppDelegate *app);

NS_ASSUME_NONNULL_END
