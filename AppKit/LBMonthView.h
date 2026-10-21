// A month as a calendar grid (the Calendar tab, MainWindow.xib): six weeks
// from the week the month starts in, a day a cell, its number and its
// entries (LBCalendar.h) a line each, as many as fit, coloured by what
// they are: done green, cancelled grey, open blue, overdue red, planned a
// lighter blue, records the text's own colour; an estimated day's planned
// one in italics. A day clicked is chosen, and the action sent. Days are
// the model's, UTC days. Drawn with plain AppKit, as gnustep-gui draws it.

#import <AppKit/AppKit.h>

@class LBCalendarEntry;

NS_ASSUME_NONNULL_BEGIN

@interface LBMonthView : NSView
// The month's first day.
@property (nonatomic, copy) NSDate *month;
// What falls on the days shown.
@property (nonatomic, copy) NSArray<LBCalendarEntry *> *entries;
// The day chosen; nil for none.
@property (nonatomic, copy, nullable) NSDate *chosenDay;
// Today, marked.
@property (nonatomic, copy, nullable) NSDate *today;
// Several vehicles' entries: each said with its vehicle ("Golf: Oil change").
@property (nonatomic) BOOL showsVehicles;
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
// The first day shown and the day after the last (six weeks).
@property (nonatomic, readonly) NSDate *firstDay;
@property (nonatomic, readonly) NSDate *endDay;
// The day at a point of the view; nil off the grid.
- (nullable NSDate *)dayAtPoint:(NSPoint)point;
@end

NS_ASSUME_NONNULL_END
