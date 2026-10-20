// The Reports tab: the reports in the app's resources (Reports/*.rdl), one
// chosen, shown by RDLKit's viewer (RDLReportViewController) with its own
// pages, zoom, parameters, export and print. The viewer asks it for each
// dataset's rows (LBReportData), again whenever a parameter changes; the
// chosen vehicle is the reports' hidden Vehicle parameter.

#import <AppKit/AppKit.h>
#import <RDLKit/RDLKit.h>
#import <RDLKitUI/RDLKitUI.h>

@class LBMainWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface LBReportsController : NSObject <RDLReportDataSource>
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
// A report by its title; its tag the report's index in -reports.
@property (nonatomic, strong) IBOutlet NSPopUpButton *reportPicker;
// Where the viewer goes.
@property (nonatomic, strong) IBOutlet NSView *reportArea;
@property (nonatomic, readonly, strong) RDLReportViewController *viewer;

// The reports there are: their files, in the order the picker offers them.
@property (nonatomic, readonly, copy) NSArray<NSURL *> *reports;
- (IBAction)chooseReport:(nullable id)sender;
// The vehicle chosen in the window changed: the report shown, of it.
- (void)vehicleChosen;
@end

NS_ASSUME_NONNULL_END
