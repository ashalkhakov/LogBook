// UDCalendarView (underivable.org): a calendar of anything, as the calendar
// apps show one: a day, a week, or a month at a time. Foundation and AppKit
// only, nothing of the app it is in, to be moved to a repository of its own. Dropped into a XIB as a custom
// view, it is pointed at its items by its dataSource (what falls in the
// range it shows) and tells its delegate what is chosen.
//
// - Month: six weeks of days, each day's items a line each, as many as fit.
// - Week, day: the days side by side, their all-day items in a band at the
//   top, the rest at their times on the hours beneath (firstHour to
//   lastHour; an item before or after them at the edge).
//
// An item is anything conforming to UDCalendarItem: a moment, or a day
// for an all-day one (read in allDayTimeZone, so that a day kept as a UTC
// day is the same day here); a title; a colour; maybe tentative (in
// italics) and a detail (in day mode). A click chooses a day; a double
// click in the month or a week shows that day. Plain AppKit, drawn as
// gnustep-gui draws it.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDCalendarMode) {
    UDCalendarModeDay = 0,
    UDCalendarModeWeek = 1,
    UDCalendarModeMonth = 2,
};

@protocol UDCalendarItem <NSObject>
// When: a moment; for an all-day item, its day.
@property (nonatomic, readonly, copy) NSDate *calendarDate;
@property (nonatomic, readonly, copy) NSString *calendarTitle;
@property (nonatomic, readonly) NSColor *calendarColor;
@optional
// The whole day, no time (NO when not said).
@property (nonatomic, readonly) BOOL calendarAllDay;
// Not certain: drawn in italics.
@property (nonatomic, readonly) BOOL calendarTentative;
// More of it, for day mode.
@property (nonatomic, readonly, copy, nullable) NSString *calendarDetail;
@end

@class UDCalendarView;

@protocol UDCalendarViewDataSource <NSObject>
// The items from the start of the range shown up to (not including) its end.
- (NSArray<id<UDCalendarItem>> *)calendarView:(UDCalendarView *)view itemsFrom:(NSDate *)start to:(NSDate *)end;
@end

@protocol UDCalendarViewDelegate <NSObject>
@optional
// A day chosen (its start), or none.
- (void)calendarView:(UDCalendarView *)view didChooseDay:(nullable NSDate *)day;
// Another range shown: another mode, or back, forward, to today.
- (void)calendarViewDidChangeRange:(UDCalendarView *)view;
@end

@interface UDCalendarView : NSView
@property (nonatomic, weak, nullable) IBOutlet id<UDCalendarViewDataSource> dataSource;
@property (nonatomic, weak, nullable) IBOutlet id<UDCalendarViewDelegate> delegate;
@property (nonatomic) UDCalendarMode mode;
// A day of what is shown: the day, a day of the week, of the month.
@property (nonatomic, copy) NSDate *date;
// The day chosen (its start); nil for none.
@property (nonatomic, copy, nullable) NSDate *chosenDay;
// The calendar and its zone the days are of (the user's, by default).
@property (nonatomic, copy) NSCalendar *calendar;
// The zone an all-day item's day is read in (the calendar's, by default).
@property (nonatomic, copy) NSTimeZone *allDayTimeZone;
// The hours day and week mode show (7 to 22 by default).
@property (nonatomic) NSInteger firstHour;
@property (nonatomic) NSInteger lastHour;
// The range shown: from its first day's start to the next day after its last.
@property (nonatomic, readonly) NSDate *rangeStart;
@property (nonatomic, readonly) NSDate *rangeEnd;
// "October 2026", "Oct 18 – 24, 2026", "Wednesday, October 21, 2026".
@property (nonatomic, readonly) NSString *rangeTitle;
// The items the data source said last.
@property (nonatomic, readonly, copy) NSArray<id<UDCalendarItem>> *items;

// The items asked for again, and drawn.
- (void)reloadData;
// The range before, after, the one with today.
- (IBAction)goBack:(nullable id)sender;
- (IBAction)goForward:(nullable id)sender;
- (IBAction)goToToday:(nullable id)sender;
// The mode of the sender's selected segment (a segmented control of Day,
// Week, Month) or tag.
- (IBAction)takeModeFrom:(nullable id)sender;
// The day an item falls on (its start).
- (NSDate *)dayOfItem:(id<UDCalendarItem>)item;
// The day at a point of the view; nil where none is.
- (nullable NSDate *)dayAtPoint:(NSPoint)point;
@end

NS_ASSUME_NONNULL_END
