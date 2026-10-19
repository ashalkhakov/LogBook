// The owner's window (MainWindow.xib): the vehicles, and what is recorded
// of the one chosen. What it shows and edits is bound in the XIB to array
// controllers over the store's context; this saves, reverts, and asks
// before closing on changes not saved.

#import <AppKit/AppKit.h>

@class LBStore;

NS_ASSUME_NONNULL_BEGIN

@interface LBMainWindowController : NSWindowController
- (instancetype)initWithStore:(LBStore *)store;
@property (nonatomic, readonly, strong) LBStore *store;
// What the XIB's controllers bind to.
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
@property (nonatomic, strong) IBOutlet NSArrayController *vehicles;

// The changes sent; the rules' refusals and the warnings said.
- (IBAction)save:(nullable id)sender;
- (IBAction)revertChanges:(nullable id)sender;
// Whether it may close: nothing unsaved, or the user says so.
- (BOOL)shouldClose;
@end

// The vehicles' controller: a new one is the signed-in user's.
@interface LBVehicleController : NSArrayController
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
@end

NS_ASSUME_NONNULL_END
