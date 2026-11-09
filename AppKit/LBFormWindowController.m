#import "LBFormWindowController.h"
#import "LBFormHost.h"
#import "LBStore.h"

@implementation LBFormWindowController {
    LBStore *_store;
    XFFormView *_formView;
}

- (instancetype)initWithFormNamed:(NSString *)name
                            store:(LBStore *)store
                            given:(NSDictionary<NSString *, NSString *> *)given
                            error:(NSError **)error {
    LBFormHost *host = [[LBFormHost alloc] initWithFormNamed:name inBundle:[NSBundle mainBundle] given:given error:error];
    if (!host) return nil;
    if ((self = [super initWithWindowNibName:@"FormWindow"])) {
        _store = store;
        _host = host;
        /* A context of its own: what the form saves is saved alone, not
           what the main window has not saved yet. */
        _context = [store newContext];
        LBStore *saving = store;
        [_host useContext:_context saving:^BOOL(NSManagedObjectContext *context, NSError **failure) {
            return [saving saveContext:context error:failure];
        }];
        if (![_host makeProcessor:error]) return nil;
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    _formView = [[XFFormView alloc] initWithProcessor:_host.processor];
    _formView.frame = NSMakeRect(0, 0, NSWidth(self.formScroll.contentView.bounds), NSHeight(_formView.frame));
    _formView.autoresizingMask = NSViewWidthSizable;
    self.formScroll.documentView = _formView;
    __weak LBFormWindowController *weakSelf = self;
    _formView.instanceChangedHandler = ^{
        [weakSelf formChanged];
    };
    [_formView reloadFromProcessor];
    self.messageLabel.stringValue = @"";
}

/* After the form did something: saved, the window done; refused, what it
   says of no field said here (the rest at their fields). */
- (void)formChanged {
    if (_host.savedKey) {
        NSString *key = _host.savedKey;
        if (self.savedHandler) self.savedHandler(key);
        [self close:nil];
        return;
    }
    self.messageLabel.stringValue = [_host.formMessages componentsJoinedByString:@"\n"];
}

- (IBAction)close:(id)sender {
    [_context rollback];
    [self.window orderOut:sender];
    [self.window close];
}

@end
