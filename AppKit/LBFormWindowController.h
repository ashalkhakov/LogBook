// A form ORMKit generated from the model, in a window of its own
// (FormWindow.xib): XFormsKit's view of it, answered by LBFormHost against
// a context of the store's own, saved as the store saves (its rules
// first). What the form cannot say at a field is said under it; saved,
// the window closes and the vehicle's records show what it made.
//
// File > Record a Fill-Up with the Generated Form…: RecordFillUp, for the
// chosen vehicle (Model/Logbook.orm's form, docs/FORMS.md); Logbook's own
// view of the same form is LBFillUpWindowController.

#import <AppKit/AppKit.h>

@class LBStore, LBFormHost;

NS_ASSUME_NONNULL_BEGIN

@interface LBFormWindowController : NSWindowController

// The form named, from the app's resources, given the values it opens
// with (the vehicle it is for): nil, and why, where it cannot be run.
- (nullable instancetype)initWithFormNamed:(NSString *)name
                                     store:(LBStore *)store
                                     given:(NSDictionary<NSString *, NSString *> *)given
                                     error:(NSError **)error;
@property (nonatomic, readonly, strong) LBFormHost *host;
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
@property (nonatomic, strong) IBOutlet NSScrollView *formScroll;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
@property (nonatomic, strong) IBOutlet NSButton *closeButton;
// Called once it saved, with the key of what it saved.
@property (nonatomic, copy, nullable) void (^savedHandler)(NSString *key);

- (IBAction)close:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
