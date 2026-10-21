// The Calendar tab (MainWindow.xib): the chosen vehicle's month (LBMonthView)
// and, beneath it, its entries (LBCalendar.h): the chosen day's, or the
// month's when none is chosen. What it shows is worked out anew whenever
// the vehicle is chosen or read again, the month changed, a day chosen.

#import <AppKit/AppKit.h>

@class LBMainWindowController, LBMonthView, LBCalendarEntry;

NS_ASSUME_NONNULL_BEGIN

@interface LBCalendarController : NSObject
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
@property (nonatomic, strong) IBOutlet LBMonthView *monthView;
// "October 2026".
@property (nonatomic, readonly, copy) NSString *monthTitle;
// The entries listed beneath the month.
@property (nonatomic, readonly, copy) NSArray<LBCalendarEntry *> *listed;
// The month's entries, all.
@property (nonatomic, readonly, copy) NSArray<LBCalendarEntry *> *entries;

- (IBAction)previousMonth:(nullable id)sender;
- (IBAction)nextMonth:(nullable id)sender;
- (IBAction)thisMonth:(nullable id)sender;
// A day chosen in the month (its action).
- (IBAction)dayChosen:(nullable id)sender;
// The month shown, from its first day.
- (void)showMonth:(NSDate *)month;
// The vehicle chosen changed, or what the server has of it was read again.
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
