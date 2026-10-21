// The lists the users write themselves (Lists.xib): the kinds of expense
// and the checklists the forms pick from, each checklist's questions in
// order and an any-of question's options; and the exchange rates costs are
// counted at. Done saves them, as the logbook's window saves (its rules
// said). What a record or a plan already uses is not removed: it is
// refused, and said. Kinds of expense and exchange rates are the server's
// to keep once saved (others' records are of them): only one not saved
// yet is typed over or removed.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBMainWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface LBListsController : NSWindowController <NSTableViewDelegate>
- (instancetype)initWithLogbook:(LBMainWindowController *)logbook;
// What the XIB binds to: the logbook's context, the lists' order.
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byTitle;
@property (nonatomic, strong) IBOutlet NSTabView *tabs;
@property (nonatomic, strong) IBOutlet NSArrayController *expenseKinds;
@property (nonatomic, strong) IBOutlet NSArrayController *checklists;
@property (nonatomic, strong) IBOutlet NSArrayController *questions;
@property (nonatomic, strong) IBOutlet NSArrayController *options;
@property (nonatomic, strong) IBOutlet NSArrayController *exchangeRates;
@property (nonatomic, strong) IBOutlet NSTableView *expenseKindsTable;
@property (nonatomic, strong) IBOutlet NSTableView *checklistsTable;
@property (nonatomic, strong) IBOutlet NSTableView *questionsTable;
@property (nonatomic, strong) IBOutlet NSTableView *optionsTable;
@property (nonatomic, strong) IBOutlet NSTableView *exchangeRatesTable;

// The window shown, at its tab of that identifier: expenseKinds,
// checklists or exchangeRates.
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
- (IBAction)addExchangeRate:(nullable id)sender;
- (IBAction)removeExchangeRate:(nullable id)sender;
- (IBAction)done:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
