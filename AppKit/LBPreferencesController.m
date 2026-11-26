#import "LBPreferencesController.h"
#import "LBMainWindowController.h"
#import "LBStore.h"
#import "User+CoreDataClass.h"

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

/* Closing: what was typed kept, then saved with the logbook's other
   changes; refused, the window stays open, the refusal said. */
- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (![self.window makeFirstResponder:nil] || ![_userController commitEditing]) return NO;
    if (!self.user.hasChanges) return YES;
    [_logbook saveLogbook];
    return !self.user.hasChanges;
}

@end
