#import "LBMainWindowController.h"
#import "LBStore.h"
#import "Vehicle+CoreDataClass.h"

@implementation LBMainWindowController

- (instancetype)initWithStore:(LBStore *)store {
    if ((self = [super initWithWindowNibName:@"MainWindow"])) _store = store;
    return self;
}

- (NSManagedObjectContext *)context {
    return _store.context;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.title = [NSString stringWithFormat:@"Logbook — %@", _store.serviceRoot.host ?: @""];
    _vehicles.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(vehicleName)) ascending:YES
                                                                  selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

/* What is being typed, kept: the field editor ended, the controllers told. */
- (BOOL)commitEdits {
    return [self.window makeFirstResponder:nil] && [_vehicles commitEditing];
}

- (IBAction)save:(id)sender {
    if (![self commitEdits]) return;
    NSArray<NSError *> *warnings = [_store warnings];
    if (warnings.count && !_quiet && ![self proceedDespite:warnings]) return;
    NSError *error = nil;
    _lastError = [_store save:&error] ? nil : [self willPresentError:error];
    if (_lastError && !_quiet) [self presentError:error];
}

/* The deontic rules a change breaks: what ought not to be, but may. */
- (BOOL)proceedDespite:(NSArray<NSError *> *)warnings {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = warnings.count == 1 ? @"This ought not to be so" : @"These ought not to be so";
    alert.informativeText = [[warnings valueForKey:NSStringFromSelector(@selector(localizedDescription))] componentsJoinedByString:@"\n"];
    [alert addButtonWithTitle:@"Save Anyway"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

/* A save's refusal, each violation said: Core Data's message names none. */
- (NSError *)willPresentError:(NSError *)error {
    NSArray *each = error.userInfo[NSDetailedErrorsKey] ?: error.userInfo[@"NSDetailedErrors"] ?: error.userInfo[@"NSDetailedErrorsKey"];
    if (!each.count) return error;
    NSString *said = [[each valueForKey:NSStringFromSelector(@selector(localizedDescription))] componentsJoinedByString:@"\n"];
    return [NSError errorWithDomain:error.domain code:error.code
                           userInfo:@{ NSLocalizedDescriptionKey: @"The changes break the logbook's rules",
                                       NSLocalizedRecoverySuggestionErrorKey: said }];
}

- (IBAction)revertChanges:(id)sender {
    [self.window makeFirstResponder:nil];
    [_store.context rollback];
}

- (BOOL)shouldClose {
    if (![self commitEdits]) return NO;
    if (!_store.context.hasChanges) return YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save the changes before closing?";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Don't Save"];
    NSModalResponse answer = [alert runModal];
    if (answer == NSAlertSecondButtonReturn) return NO;
    if (answer == NSAlertThirdButtonReturn) return YES;
    NSError *error = nil;
    if ([_store save:&error]) return YES;
    [self presentError:error];
    return NO;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    return [self shouldClose];
}

@end

@implementation LBVehicleController

- (id)newObject {
    Vehicle *vehicle = [super newObject];
    vehicle.owner = _windowController.store.user;
    return vehicle;
}

@end
