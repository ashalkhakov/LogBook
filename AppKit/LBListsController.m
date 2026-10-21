#import "LBListsController.h"
#import "LBMainWindowController.h"
#import "LBStore.h"
#import "LBDisplay.h"
#import "LBProcedures.h"
#import "ExpenseKind+CoreDataClass.h"
#import "Option+CoreDataClass.h"
#import "ExchangeRate+CoreDataClass.h"

@implementation LBListsController {
    LBMainWindowController *_logbook;
}

- (instancetype)initWithLogbook:(LBMainWindowController *)logbook {
    if ((self = [super initWithWindowNibName:@"Lists"])) _logbook = logbook;
    return self;
}

- (NSManagedObjectContext *)context {
    return _logbook.context;
}

- (NSArray<NSSortDescriptor *> *)byTitle {
    return _logbook.byTitle;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    /* The user's own checklists: drivers go through their owners'. */
    User *user = _logbook.store.user;
    if (user) _checklists.fetchPredicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(user)), user];
    NSString *position = NSStringFromSelector(@selector(position));
    _questions.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:position ascending:YES] ];
    _options.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:position ascending:YES] ];
    /* The latest rates first; each on a day of the model's (a UTC one), a
       factor of up to six places. */
    _exchangeRates.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(date)) ascending:NO] ];
    NSDateFormatter *day = [[NSDateFormatter alloc] init];
    day.dateStyle = NSDateFormatterShortStyle;
    day.timeStyle = NSDateFormatterNoStyle;
    day.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    [[_exchangeRatesTable tableColumnWithIdentifier:NSStringFromSelector(@selector(date))].dataCell setFormatter:day];
    NSNumberFormatter *factor = [[NSNumberFormatter alloc] init];
    factor.numberStyle = NSNumberFormatterDecimalStyle;
    factor.generatesDecimalNumbers = YES;
    factor.maximumFractionDigits = 6;
    [[_exchangeRatesTable tableColumnWithIdentifier:NSStringFromSelector(@selector(factor))].dataCell setFormatter:factor];
    _expenseKindsTable.delegate = self;
    _exchangeRatesTable.delegate = self;
}

/* A kind of expense or an exchange rate is typed over only before it is
   saved: the server keeps them as they were added. */
- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSArrayController *controller = tableView == _expenseKindsTable ? _expenseKinds : tableView == _exchangeRatesTable ? _exchangeRates : nil;
    if (!controller || row < 0 || row >= (NSInteger)[controller.arrangedObjects count]) return YES;
    return [(NSManagedObject *)controller.arrangedObjects[(NSUInteger)row] isInserted];
}

- (void)showTab:(NSString *)identifier {
    [self showWindow:nil];
    [_tabs selectTabViewItemWithIdentifier:identifier];
}

/* What cannot be done, said as the logbook says it. */
- (void)refuse:(NSString *)why {
    [_logbook reportError:[NSError errorWithDomain:LBProceduresErrorDomain code:LBProceduresErrorRefused
                                          userInfo:@{ NSLocalizedDescriptionKey: why }]];
}

/* The object new in a list chosen, its name ready to be typed over. */
- (void)choose:(id)object in:(NSArrayController *)controller table:(NSTableView *)table {
    /* An entity's controller has it once the context has said so. */
    [self.context processPendingChanges];
    [controller rearrangeObjects];
    [controller setSelectedObjects:@[ object ]];
    NSUInteger row = [controller.arrangedObjects indexOfObjectIdenticalTo:object];
    if (row != NSNotFound) [table editColumn:0 row:(NSInteger)row withEvent:nil select:YES];
}

- (id)chosenIn:(NSArrayController *)controller {
    NSArray *chosen = controller.selectedObjects;
    return chosen.count == 1 ? chosen[0] : nil;
}

/* A name not taken yet in the list, from the one given. */
- (NSString *)name:(NSString *)name freeIn:(NSArray *)objects {
    NSSet *taken = [NSSet setWithArray:[objects valueForKey:NSStringFromSelector(@selector(lbTitle))]];
    NSString *free = name;
    for (NSUInteger n = 2; [taken containsObject:free]; n++) free = [NSString stringWithFormat:@"%@ %lu", name, (unsigned long)n];
    return free;
}

/* The next position at the end of a list kept in order. */
static int32_t LBNextPosition(NSSet *objects) {
    int32_t last = 0;
    for (id object in objects) last = MAX(last, [[object valueForKey:NSStringFromSelector(@selector(position))] intValue]);
    return last + 1;
}

#pragma mark Kinds of expense

- (IBAction)addExpenseKind:(id)sender {
    if (![self.window makeFirstResponder:nil]) return;
    ExpenseKind *kind = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([ExpenseKind class])
                                                      inManagedObjectContext:self.context];
    kind.name = [self name:@"New kind" freeIn:_expenseKinds.arrangedObjects];
    [self choose:kind in:_expenseKinds table:_expenseKindsTable];
}

- (IBAction)removeExpenseKind:(id)sender {
    ExpenseKind *kind = [self chosenIn:_expenseKinds];
    if (!kind) return;
    if (!kind.isInserted) {
        [self refuse:[NSString stringWithFormat:@"“%@” is saved: kinds of expense are kept once saved, as others' records may be of them.",
                                                kind.name]];
        return;
    }
    NSUInteger uses = kind.expenses.count + kind.schedules.count + kind.reminders.count;
    if (uses) {
        [self refuse:[NSString stringWithFormat:@"“%@” is the kind of %lu expenses, schedules or reminders: it stays.", kind.name,
                                                (unsigned long)uses]];
        return;
    }
    [self.context deleteObject:kind];
}

#pragma mark Checklists

- (IBAction)addChecklist:(id)sender {
    if (![self.window makeFirstResponder:nil]) return;
    Checklist *checklist = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Checklist class])
                                                         inManagedObjectContext:self.context];
    checklist.user = _logbook.store.user;
    checklist.checklistName = [self name:@"New checklist" freeIn:_checklists.arrangedObjects];
    [self choose:checklist in:_checklists table:_checklistsTable];
}

- (IBAction)removeChecklist:(id)sender {
    Checklist *checklist = [self chosenIn:_checklists];
    if (!checklist) return;
    NSUInteger uses = checklist.inspections.count + checklist.schedules.count + checklist.reminders.count;
    if (uses) {
        [self refuse:[NSString stringWithFormat:@"“%@” was gone through, or is planned, %lu times: it stays.", checklist.checklistName,
                                                (unsigned long)uses]];
        return;
    }
    for (Question *question in checklist.questions) {
        for (Option *option in question.options) [self.context deleteObject:option];
        [self.context deleteObject:question];
    }
    [self.context deleteObject:checklist];
}

#pragma mark Questions

- (IBAction)addQuestion:(id)sender {
    Checklist *checklist = [self chosenIn:_checklists];
    if (!checklist || ![self.window makeFirstResponder:nil]) return;
    Question *question = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Question class])
                                                       inManagedObjectContext:self.context];
    question.position = LBNextPosition(checklist.questions);
    question.questionText = @"New question";
    question.answerKind = LBYesOrNo;
    question.checklist = checklist;
    [self choose:question in:_questions table:_questionsTable];
}

- (IBAction)removeQuestion:(id)sender {
    Question *question = [self chosenIn:_questions];
    if (!question) return;
    if (question.answers.count) {
        [self refuse:[NSString stringWithFormat:@"“%@” was answered in %lu inspections: it stays.", question.questionText,
                                                (unsigned long)question.answers.count]];
        return;
    }
    for (Option *option in question.options) [self.context deleteObject:option];
    [self.context deleteObject:question];
}

/* The chosen question changes places with the one before or after it. */
- (void)moveQuestionBy:(NSInteger)step {
    Question *question = [self chosenIn:_questions];
    NSArray<Question *> *ordered = _questions.arrangedObjects;
    NSUInteger at = question ? [ordered indexOfObjectIdenticalTo:question] : NSNotFound;
    if (at == NSNotFound || (step < 0 && at == 0) || (step > 0 && at + 1 >= ordered.count)) return;
    Question *other = ordered[at + step];
    int32_t position = question.position;
    question.position = other.position;
    other.position = position;
    [_questions rearrangeObjects];
    [_questions setSelectedObjects:@[ question ]];
}

- (IBAction)moveQuestionUp:(id)sender {
    [self moveQuestionBy:-1];
}

- (IBAction)moveQuestionDown:(id)sender {
    [self moveQuestionBy:1];
}

#pragma mark Options

- (IBAction)addOption:(id)sender {
    Question *question = [self chosenIn:_questions];
    if (!question.lbTakesOptions || ![self.window makeFirstResponder:nil]) return;
    Option *option = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Option class])
                                                   inManagedObjectContext:self.context];
    option.position = LBNextPosition(question.options);
    option.optionText = @"New option";
    option.question = question;
    [self choose:option in:_options table:_optionsTable];
}

- (IBAction)removeOption:(id)sender {
    Option *option = [self chosenIn:_options];
    if (!option) return;
    if (option.answers.count) {
        [self refuse:[NSString stringWithFormat:@"“%@” was chosen in %lu inspections: it stays.", option.optionText,
                                                (unsigned long)option.answers.count]];
        return;
    }
    [self.context deleteObject:option];
}

#pragma mark Exchange rates

/* Today's rate, 1 to 1 into the user's currency: the base and the factor
   are typed over. */
- (IBAction)addExchangeRate:(id)sender {
    if (![self.window makeFirstResponder:nil]) return;
    NSCalendar *utc = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    utc.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDateComponents *today = [[NSCalendar currentCalendar] components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                                              fromDate:[NSDate date]];
    ExchangeRate *rate = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([ExchangeRate class])
                                                       inManagedObjectContext:self.context];
    rate.date = [utc dateFromComponents:today];
    rate.quoteCurrency = _logbook.store.user.lbCurrency;
    rate.baseCurrency = [rate.quoteCurrency isEqualToString:@"EUR"] ? @"USD" : @"EUR";
    rate.factor = [NSDecimalNumber one];
    [self.context processPendingChanges];
    [_exchangeRates rearrangeObjects];
    [_exchangeRates setSelectedObjects:@[ rate ]];
    NSUInteger row = [_exchangeRates.arrangedObjects indexOfObjectIdenticalTo:rate];
    NSInteger column = [_exchangeRatesTable columnWithIdentifier:NSStringFromSelector(@selector(baseCurrency))];
    if (row != NSNotFound && column >= 0) [_exchangeRatesTable editColumn:column row:(NSInteger)row withEvent:nil select:YES];
}

- (IBAction)removeExchangeRate:(id)sender {
    ExchangeRate *rate = [self chosenIn:_exchangeRates];
    if (!rate) return;
    if (!rate.isInserted) {
        [self refuse:@"This rate is saved: exchange rates are kept once saved, as costs are counted at them."];
        return;
    }
    [self.context deleteObject:rate];
}

/* What was typed kept, then saved with the logbook's other changes. */
- (IBAction)done:(id)sender {
    if (![self.window makeFirstResponder:nil]) return;
    for (NSArrayController *controller in @[ _expenseKinds, _checklists, _questions, _options, _exchangeRates ]) {
        if (![controller commitEditing]) return;
    }
    [_logbook save:sender];
    if (!_logbook.lastError) [self close];
}

@end
