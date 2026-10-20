#import "LBPreferencesController.h"
#import "LBMainWindowController.h"
#import "LBStore.h"

@implementation LBPreferencesController {
    LBMainWindowController *_logbook;
}

- (instancetype)initWithLogbook:(LBMainWindowController *)logbook {
    if ((self = [super initWithWindowNibName:@"Preferences"])) _logbook = logbook;
    return self;
}

- (NSManagedObjectContext *)context {
    return _logbook.context;
}

- (User *)user {
    return _logbook.store.user;
}

- (NSArray<NSSortDescriptor *> *)byTitle {
    return _logbook.byTitle;
}

/* What was typed kept, then saved with the logbook's other changes. */
- (IBAction)done:(id)sender {
    if (![self.window makeFirstResponder:nil] || ![_userController commitEditing]) return;
    [_logbook save:sender];
    if (!_logbook.lastError) [self close];
}

@end
