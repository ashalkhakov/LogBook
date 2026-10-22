// The Calendar tab (MainWindow.xib): a UDCalendarView of the chosen vehicle,
// or with All Vehicles of every vehicle listed (those the user owns and
// drives, each entry said with its vehicle), a day, a week or a month at a
// time; its data source and delegate. Beneath it, the entries
// (LBCalendar.h) of the range shown, or of the day chosen. Logbook's
// colours: done green, cancelled grey, open blue, overdue red, planned a
// lighter blue, records the text's; an estimated day in italics.

#import <AppKit/AppKit.h>
#import "UDCalendarView.h"

@class LBMainWindowController, LBCalendarEntry;

NS_ASSUME_NONNULL_BEGIN

@interface LBCalendarController : NSObject <UDCalendarViewDataSource, UDCalendarViewDelegate>
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
@property (nonatomic, strong) IBOutlet UDCalendarView *calendarView;
// Day, Week, Month: kept with the view's mode.
@property (nonatomic, strong) IBOutlet NSSegmentedControl *modeControl;
// The range shown, said: "October 2026".
@property (nonatomic, readonly, copy) NSString *rangeTitle;
// The entries listed beneath it.
@property (nonatomic, readonly, copy) NSArray<LBCalendarEntry *> *listed;
// The range's entries, all.
@property (nonatomic, readonly, copy) NSArray<LBCalendarEntry *> *entries;
// All the vehicles listed, each entry said with its vehicle; else the
// chosen one's.
@property (nonatomic) BOOL allVehicles;

- (IBAction)previous:(nullable id)sender;
- (IBAction)next:(nullable id)sender;
- (IBAction)today:(nullable id)sender;
// The mode of the segmented control.
- (IBAction)modeChosen:(nullable id)sender;
// The vehicle chosen changed, or what the server has of it was read again.
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
