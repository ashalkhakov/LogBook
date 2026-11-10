// Logbook's own view of the model's RecordFillUp form (ORMKit's
// docs/FORMS.md, the contract and its views): a window of its own
// (FillUpWindow.xib) laid out as the fill-up's tab is, its controls bound
// to the form's values (LBFormValues), its drivers the form's choices, run
// by an ORMFormSession against a context of the store's own, saved as the
// store saves. A refusal is said under the control it is about, each
// control and what is said of it named in the XIB by the elements'
// names ("driver", "problem-driver"), the rest under the form. Saved, the
// window closes and the vehicle's records show the new one. What was said
// under a control is gone once its value changes.
//
// File > Record a Fill-Up…; the generated form of the same contract is
// File > Record a Fill-Up with the Generated Form… (LBFormWindowController).

#import <AppKit/AppKit.h>

@class LBStore, LBFormValues;

NS_ASSUME_NONNULL_BEGIN

@interface LBFillUpWindowController : NSWindowController

// For the vehicle, entered by the user (RecordFillUp's inputs): nil, and
// why, where the form is not in the app or cannot be opened.
- (nullable instancetype)initWithStore:(LBStore *)store
                                 given:(NSDictionary<NSString *, NSString *> *)given
                                 error:(NSError **)error;
@property (nonatomic, readonly, strong) LBFormValues *values;
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
// Who may have driven: the form's choices for the vehicle.
@property (nonatomic, readonly, copy) NSArray<NSManagedObject *> *drivers;
// The units in their order, as the main window lists them.
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byTitle;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
@property (nonatomic, strong) IBOutlet NSButton *saveButton;
// Called once it saved, with the key of what it saved.
@property (nonatomic, copy, nullable) void (^savedHandler)(NSString *key);

// What the last save refused said at a control: the text under the
// element's control, "" for none.
- (NSString *)problemAt:(NSString *)element;

- (IBAction)save:(nullable id)sender;
- (IBAction)close:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
