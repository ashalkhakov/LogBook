// An alert about a window shown as a sheet on it, as the HIG has it, its
// answer waited for (the code asking goes on with it). macOS: the sheet,
// with a modal session for its answer. GNUstep, or no window to attach it
// to (none, hidden, a sheet already on it): app-modal.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

static inline NSModalResponse LBAskInSheet(NSAlert *alert, NSWindow *_Nullable window) {
#ifdef GNUSTEP
    (void)window;
    return [alert runModal];
#else
    if (!window || !window.isVisible || window.attachedSheet) return [alert runModal];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse answer) {
        [NSApp stopModalWithCode:answer];
    }];
    return [NSApp runModalForWindow:alert.window];
#endif
}

// Save, Cancel, Don't Save (Command-D), as the HIG words it: the changes made
// to what is named (nil: "these changes"), lost unless saved.
static inline NSAlert *LBSaveChangesAlert(NSString *_Nullable what) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = what ? [NSString stringWithFormat:@"Do you want to save the changes you made to %@?", what]
                             : @"Do you want to save the changes you made?";
    alert.informativeText = @"Your changes will be lost if you don't save them.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    NSButton *dontSave = [alert addButtonWithTitle:@"Don't Save"];
    dontSave.keyEquivalent = @"d";
    dontSave.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    return alert;
}

NS_ASSUME_NONNULL_END
