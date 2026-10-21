// The lists the forms pick from that the users write themselves (Lists.xib):
// the kinds of expense, and the checklists an inspection goes through,
// each its questions in order and an any-of question's options. Done saves
// them, as the logbook's window saves (its rules said). What a record or a
// plan already uses is not removed: it is refused, and said.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBMainWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface LBListsController : NSWindowController
- (instancetype)initWithLogbook:(LBMainWindowController *)logbook;
// What the XIB binds to: the logbook's context, the lists' order.
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byTitle;
@property (nonatomic, strong) IBOutlet NSTabView *tabs;
@property (nonatomic, strong) IBOutlet NSArrayController *expenseKinds;
@property (nonatomic, strong) IBOutlet NSArrayController *checklists;
@property (nonatomic, strong) IBOutlet NSArrayController *questions;
@property (nonatomic, strong) IBOutlet NSArrayController *options;
@property (nonatomic, strong) IBOutlet NSTableView *expenseKindsTable;
@property (nonatomic, strong) IBOutlet NSTableView *checklistsTable;
@property (nonatomic, strong) IBOutlet NSTableView *questionsTable;
@property (nonatomic, strong) IBOutlet NSTableView *optionsTable;

// The window shown, at its tab of that identifier: expenseKinds or
// checklists.
- (void)showTab:(NSString *)identifier;

- (IBAction)addExpenseKind:(nullable id)sender;
- (IBAction)removeExpenseKind:(nullable id)sender;
- (IBAction)addChecklist:(nullable id)sender;
- (IBAction)removeChecklist:(nullable id)sender;
- (IBAction)addQuestion:(nullable id)sender;
- (IBAction)removeQuestion:(nullable id)sender;
- (IBAction)moveQuestionUp:(nullable id)sender;
- (IBAction)moveQuestionDown:(nullable id)sender;
- (IBAction)addOption:(nullable id)sender;
- (IBAction)removeOption:(nullable id)sender;
- (IBAction)done:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
