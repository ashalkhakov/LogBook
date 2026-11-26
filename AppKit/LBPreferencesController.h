// The signed-in user's preferences (Preferences.xib): their name, and the
// currency and units their new records are filled in with and their
// reports total in. They take effect as they are changed; closing the
// window saves them, as the logbook's window saves (its rules said; refused,
// the window stays open). No Done: a preferences window has none (HIG).

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBMainWindowController, User;

NS_ASSUME_NONNULL_BEGIN

@interface LBPreferencesController : NSWindowController
- (instancetype)initWithLogbook:(LBMainWindowController *)logbook;
// What the XIB binds to: the logbook's context, the user, the units' order.
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
@property (nonatomic, readonly, strong, nullable) User *user;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byTitle;
@property (nonatomic, strong) IBOutlet NSObjectController *userController;
@end

NS_ASSUME_NONNULL_END
