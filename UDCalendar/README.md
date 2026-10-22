# UDCalendar

`UDCalendarView` (underivable.org): a calendar view of anything, a day, a
week or a month at a time, as the calendar apps show one. Foundation and
AppKit only, for macOS and GNUstep; it lives in Logbook for now and is to
move to a repository of its own.

## Using it

Drop a custom view of class `UDCalendarView` into a XIB, and connect its
`dataSource` (and, if you like, its `delegate`) outlet:

```objc
@interface MyCalendar : NSObject <UDCalendarViewDataSource, UDCalendarViewDelegate>
@end

@implementation MyCalendar
- (NSArray<id<UDCalendarItem>> *)calendarView:(UDCalendarView *)view itemsFrom:(NSDate *)start to:(NSDate *)end {
    return [self.appointments filteredFromDay:start toDay:end];   // anything conforming to UDCalendarItem
}
- (void)calendarView:(UDCalendarView *)view didChooseDay:(NSDate *)day { /* a day clicked */ }
- (void)calendarViewDidChangeRange:(UDCalendarView *)view { /* back, forward, another mode */ }
@end
```

An item conforms to `UDCalendarItem`: `calendarDate`, `calendarTitle`,
`calendarColor`; optionally `calendarAllDay`, `calendarTentative` (in
italics) and `calendarDetail` (in day mode).

- `mode`: `UDCalendarModeDay`, `UDCalendarModeWeek`, `UDCalendarModeMonth`
  (`-takeModeFrom:` takes it from a segmented control's selected segment).
- `-goBack:`, `-goForward:`, `-goToToday:`; `rangeTitle` says what is shown.
- `calendar` (the user's by default) and `allDayTimeZone`, the zone an
  all-day item's day is read in: a store that keeps days as UTC days sets
  it to UTC, and a day stays the same day wherever the user is.
- `firstHour`, `lastHour`: the hours day and week mode show.

Week and day mode put all-day items in a band at the top and the rest at
their times; items at the same time go side by side, as many as are wide
enough to read, and how many more after them. A double click on a day of
the month or a week shows that day.
