// A list's word on the sync, as the HIG has it: its status ("Synced 10:37.
// 2 changes waiting.") as the title of the list's refresh control, seen as
// it is pulled down to sync now; and, while the last sync failed, the
// navigation bar's prompt, a sentence saying what to do. No button for the
// conflicts here: the Vehicle tab's badge and its Conflicts row are theirs.

#import <UIKit/UIKit.h>

@class LBLocalStore;

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (LBSyncStatus)
// Said again (on each reload): a table's refresh control made the first
// time, a pull syncing the store.
- (void)lb_showSyncStatus:(nullable LBLocalStore *)store;
@end

NS_ASSUME_NONNULL_END
