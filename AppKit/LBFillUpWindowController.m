#import "LBFillUpWindowController.h"
#import "LBFormValues.h"
#import "LBStore.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>

@implementation LBFillUpWindowController {
    ORMFormSession *_session;
    NSArray<NSManagedObject *> *_drivers;
}

- (instancetype)initWithStore:(LBStore *)store
                        given:(NSDictionary<NSString *, NSString *> *)given
                        error:(NSError **)error {
    ORMForm *form = [ORMForm formNamed:@"RecordFillUp" error:error];
    if (!form) return nil;
    if ((self = [super initWithWindowNibName:@"FillUpWindow"])) {
        /* A context of its own: what the form saves is saved alone, not
           what the main window has not saved yet. */
        _context = [store newContext];
        _session = [[ORMFormSession alloc] initWithForm:form given:given];
        LBStore *saving = store;
        [_session useContext:_context saving:^BOOL(NSManagedObjectContext *context, NSError **failure) {
            return [saving saveContext:context error:failure];
        }];
        if (![_session open:error]) return nil;
        _values = [[LBFormValues alloc] initWithSession:_session context:_context];
        _byTitle = @[ [NSSortDescriptor sortDescriptorWithKey:@"lbTitle" ascending:YES] ];
        _drivers = [_values choicesNamed:@"driver" error:error];
        if (!_drivers) return nil;
    }
    return self;
}

- (NSArray<NSManagedObject *> *)drivers {
    return _drivers;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self showProblems:@{}];
    /* What was said of a field gone once it is changed. */
    __weak LBFillUpWindowController *weakSelf = self;
    _values.changedHandler = ^(NSString *element) {
        [weakSelf clearProblemAt:element];
    };
}

- (void)clearProblemAt:(NSString *)element {
    NSDictionary<NSString *, NSView *> *views = [self viewsByIdentifier];
    for (NSString *identifier in views) {
        if ([identifier hasPrefix:@"problem-"]
            && [[[identifier substringFromIndex:[@"problem-" length]] componentsSeparatedByString:@"-"] containsObject:element]) {
            ((NSTextField *)views[identifier]).stringValue = @"";
        }
    }
}

/* Every control and problem label under the view, by identifier. */
static void LBViewsByIdentifier(NSView *view, NSMutableDictionary<NSString *, NSView *> *found) {
    for (NSView *subview in view.subviews) {
        if (subview.identifier.length) found[subview.identifier] = subview;
        LBViewsByIdentifier(subview, found);
    }
}

- (NSDictionary<NSString *, NSView *> *)viewsByIdentifier {
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    LBViewsByIdentifier(self.window.contentView, found);
    return found;
}

/* What is said of each element under its control ("problem-driver",
   "problem-mileageQuantity-mileageDistanceUnit"), what no control is
   there for under the form. */
- (void)showProblems:(NSDictionary<NSString *, NSString *> *)errors {
    NSMutableDictionary *left = [errors mutableCopy];
    NSView *first = nil;
    NSDictionary<NSString *, NSView *> *views = [self viewsByIdentifier];
    for (NSString *identifier in views) {
        if (![identifier hasPrefix:@"problem-"]) continue;
        NSMutableArray *said = [NSMutableArray array];
        for (NSString *element in [[identifier substringFromIndex:[@"problem-" length]] componentsSeparatedByString:@"-"]) {
            if (errors[element]) {
                [said addObject:errors[element]];
                [left removeObjectForKey:element];
                if (!first) first = views[element];
            }
        }
        ((NSTextField *)views[identifier]).stringValue = [said componentsJoinedByString:@" "];
    }
    NSMutableArray *rest = [NSMutableArray array];
    for (NSString *element in left) {
        ORMFormElement *known = [_session.form elementNamed:element];
        [rest addObject:known && element.length ? [NSString stringWithFormat:@"%@: %@", known.label, left[element]] : left[element]];
    }
    self.messageLabel.stringValue = [rest componentsJoinedByString:@"\n"];
    if (first) [self.window makeFirstResponder:first];
}

- (NSString *)problemAt:(NSString *)element {
    NSDictionary<NSString *, NSView *> *views = [self viewsByIdentifier];
    for (NSString *identifier in views) {
        if (![identifier hasPrefix:@"problem-"]) continue;
        if ([[[identifier substringFromIndex:[@"problem-" length]] componentsSeparatedByString:@"-"] containsObject:element]) {
            return ((NSTextField *)views[identifier]).stringValue ?: @"";
        }
    }
    return @"";
}

- (IBAction)save:(id)sender {
    /* What is being typed is the value saved. */
    if (![self.window makeFirstResponder:nil]) return;
    NSError *error = nil;
    if (![_session save:&error]) {
        [self showProblems:error ? @{ @"" : error.localizedDescription ?: @"Not saved." } : _session.errors];
        return;
    }
    [_values reload];
    NSString *key = _session.savedKey;
    if (self.savedHandler) self.savedHandler(key);
    [self.window orderOut:sender];
    [self.window close];
}

- (IBAction)close:(id)sender {
    [_context rollback];
    [self.window orderOut:sender];
    [self.window close];
}

@end
