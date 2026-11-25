// Where the time goes, for a user to send: LB_TIMING=1 in the environment
// (./Logbook-*.AppImage with LB_TIMING=1 before it), and the desktop app
// writes to standard error, a line each, with the time of day to the
// millisecond:
//
//   TIMING 14:02:31.415 click asks to change the vehicles' selection (row 2 clicked)
//   TIMING 14:02:31.482 vehicle chosen: reports 66.2 ms
//   TIMING 14:02:31.502 window up to date, 87.4 ms after the change began
//
// What is timed: a click on the vehicle list (as it asks to change the
// selection, and as it has), choosing a vehicle and each part of it (its
// drivers, the reports, reminders and calendar), choosing a record, the
// record list read again, the fields' issues, the window up to date (all
// of it done and drawn) after the change began, a sync (its status as it
// changes) and what it reads again. Off, nothing is written and nothing
// timed.

#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Whether LB_TIMING is set (read once).
FOUNDATION_EXPORT BOOL LBTimingOn(void);
// A line: the time of day, then the text.
FOUNDATION_EXPORT void LBTimingNote(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
// The work done, and how long it took, as a line ("what 12.3 ms").
FOUNDATION_EXPORT void LBTimed(NSString *what, void (^work)(void));

NS_ASSUME_NONNULL_END
