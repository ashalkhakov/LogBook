#import "LBRemindersController.h"
#import "LBMainWindowController.h"
#import "LBStore.h"
#import "LBDisplay.h"
#import "LBProcedures.h"
#import "LogbookValidation.h"
#import "LBFormValues.h"
#import "Vehicle+CoreDataClass.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>

static void *LBReminderChosen = &LBReminderChosen;
static void *LBScheduleChosen = &LBScheduleChosen;
static NSString * const LBNoForm = @"none";

/* Today here (the calendar's, this Mac's) as the model's day of the same
   date, a UTC one: what a form's day is, as its field says it. */
static NSDate *LBToday(void) {
    NSDateComponents *parts = [[NSCalendar currentCalendar] components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                                              fromDate:[NSDate date]];
    NSCalendar *utc = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    utc.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return [utc dateFromComponents:parts];
}

/* The control of the identifier in the view, or under it. */
static NSView *LBControlOf(NSString *identifier, NSView *view) {
    if ([view.identifier isEqualToString:identifier]) return view;
    for (NSView *subview in view.subviews) {
        NSView *found = LBControlOf(identifier, subview);
        if (found) return found;
    }
    return nil;
}

/* Events latest first. */
static NSInteger LBLatestFirst(id a, id b, void *context) {
    return [(Event *)b lb_isBeforeEvent:(Event *)a] ? NSOrderedAscending : [(Event *)a lb_isBeforeEvent:(Event *)b] ? NSOrderedDescending
                                                                                                              : NSOrderedSame;
}

@interface LBRemindersController ()
@property (nonatomic, readwrite, strong) LBFormValues *scheduleForm;
@property (nonatomic, readwrite, strong) LBFormValues *changeForm;
@property (nonatomic, readwrite, strong) LBFormValues *reminderForm;
@property (nonatomic, readwrite, strong) LBFormValues *rescheduleForm;
@property (nonatomic, readwrite, strong) LBFormValues *cancelForm;
@property (nonatomic, readwrite, strong) LBFormValues *doneForm;
@property (nonatomic, readwrite) BOOL hasVehicle;
@property (nonatomic, readwrite) BOOL chosenOpen;
@property (nonatomic, readwrite) BOOL scheduleChosen;
@end

@implementation LBRemindersController {
    Reminder *_formFor;
    Schedule *_scheduleFor;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    /* A day of the model (due on, cancelled on) is a UTC day: its field
       reads and says it so, whatever the zone here. */
    for (NSTabViewItem *form in _forms.tabViewItems) {
        for (NSString *identifier in @[ @"scheduleDate", @"reminderDate", @"rescheduleDate", @"cancelDate", @"cancelReplacementDate" ]) {
            NSTextField *field = (NSTextField *)LBControlOf(identifier, form.view);
            if ([field.formatter isKindOfClass:[NSDateFormatter class]]) {
                ((NSDateFormatter *)field.formatter).timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            }
        }
    }
    /* A vehicle's records, each list those of its kind. */
    NSString *kind = [NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(entity)), NSStringFromSelector(@selector(name))];
    /* The schedules in force: one changed went on in another (its past is
       the calendar's). */
    _schedules.filterPredicate = [NSPredicate predicateWithFormat:@"%K == %@ AND %K == nil", kind, NSStringFromClass([Schedule class]),
                                                                  NSStringFromSelector(@selector(continuation))];
    _reminders.filterPredicate = [NSPredicate predicateWithFormat:@"%K == %@", kind, NSStringFromClass([Reminder class])];
    _schedules.clearsFilterPredicateOnInsertion = NO;
    _reminders.clearsFilterPredicateOnInsertion = NO;
    _schedules.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbWork)) ascending:YES
                                                                   selector:@selector(localizedCaseInsensitiveCompare:)] ];
    /* The open first, each by when it is due. */
    _reminders.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbOrder)) ascending:YES],
                                    [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(dueDate)) ascending:YES],
                                    [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(setAt)) ascending:YES] ];
    _reschedulings.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(madeAt)) ascending:NO] ];
    [_reminders addObserver:self forKeyPath:NSStringFromSelector(@selector(selectionIndexes)) options:0 context:LBReminderChosen];
    [_schedules addObserver:self forKeyPath:NSStringFromSelector(@selector(selectionIndexes)) options:0 context:LBScheduleChosen];
}

- (void)dealloc {
    [_reminders removeObserver:self forKeyPath:NSStringFromSelector(@selector(selectionIndexes)) context:LBReminderChosen];
    [_schedules removeObserver:self forKeyPath:NSStringFromSelector(@selector(selectionIndexes)) context:LBScheduleChosen];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == LBReminderChosen) [self reminderChosen];
    else if (context == LBScheduleChosen) [self scheduleChosenChanged];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (nullable Schedule *)chosenSchedule {
    NSArray *chosen = _schedules.selectedObjects;
    return chosen.count == 1 ? chosen[0] : nil;
}

/* A schedule's form about the schedule chosen before is put away. */
- (void)scheduleChosenChanged {
    Schedule *chosen = [self chosenSchedule];
    self.scheduleChosen = chosen != nil;
    if (_scheduleFor && _scheduleFor != chosen) [self closeForm:nil];
}

- (nullable Reminder *)chosenReminder {
    NSArray *chosen = _reminders.selectedObjects;
    return chosen.count == 1 ? chosen[0] : nil;
}

/* A form about the reminder chosen before is put away. */
- (void)reminderChosen {
    Reminder *chosen = [self chosenReminder];
    self.chosenOpen = chosen.lb_isOpen;
    if (_formFor && _formFor != chosen) [self closeForm:nil];
}

- (void)refresh {
    Vehicle *vehicle = [_windowController chosenVehicle];
    self.hasVehicle = vehicle != nil;
    NSMutableSet *overdue = [NSMutableSet set];
    if (vehicle) {
        NSError *error = nil;
        ORMQueryResult *byDate = [LogbookQueries overdueRemindersInContext:_windowController.context error:&error];
        ORMQueryResult *byMileage = byDate ? [LogbookQueries overdueByMileageInContext:_windowController.context error:&error] : nil;
        if (!byMileage) NSLog(@"Logbook: overdue reminders not asked: %@", error.localizedDescription);
        for (ORMQueryResult *result in @[ byDate ?: [ORMQueryResult resultWithObjects:@[] columnTitles:@[] rows:@[]],
                                          byMileage ?: [ORMQueryResult resultWithObjects:@[] columnTitles:@[] rows:@[]] ]) {
            for (id object in result.objects) {
                if ([object isKindOfClass:[Reminder class]] && ((Reminder *)object).id) [overdue addObject:((Reminder *)object).id];
            }
        }
    }
    [Reminder lbSetOverdue:overdue shown:_reminders.arrangedObjects];
    [_schedules rearrangeObjects];
    [_reminders rearrangeObjects];
    [self reminderChosen];
    [self scheduleChosenChanged];
}

#pragma mark The forms

/* The model's form, opened on the object (nil: a new one) with what it is
   given, its values as its tab binds them (LBFormValues.h), held by the
   form, not the object: written by its save, as the store saves, or
   submitted to the procedure it stands for. nil, and why said, where it
   does not open. */
- (LBFormValues *)form:(NSString *)name on:(NSManagedObject *)object given:(NSDictionary *)given {
    NSError *error = nil;
    ORMForm *form = [ORMForm formNamed:name error:&error];
    ORMFormSession *session = form ? [[ORMFormSession alloc] initWithForm:form given:given ?: @{}] : nil;
    LBStore *store = _windowController.store;
    if (session) [LBFormValues session:session useContext:_windowController.context saving:^BOOL(NSManagedObjectContext *context, NSError **failure) {
        return [store save:failure];
    }];
    session.key = [[object valueForKey:@"id"] UUIDString];
    if (!session || ![session open:&error]) {
        [_windowController reportError:error];
        return nil;
    }
    LBFormValues *values = [[LBFormValues alloc] initWithSession:session context:_windowController.context];
    __weak NSTabView *forms = _forms;
    values.changedHandler = ^(NSString *element) {
        [LBFormValues clearProblemAt:element under:forms];
    };
    return values;
}

/* What the vehicle chosen and the user give a form that makes a record. */
- (NSDictionary *)givenRecord {
    return @{ @"vehicle" : [_windowController chosenVehicle].id.UUIDString ?: @"",
              @"enteredBy" : _windowController.store.user.email ?: @"" };
}

- (void)show:(NSString *)identifier about:(Reminder *)reminder {
    _formFor = reminder;
    _scheduleFor = nil;
    [_forms selectTabViewItemWithIdentifier:identifier];
}

/* Every form put away, as a form is shown or closed. */
- (void)putAway {
    [_windowController.window makeFirstResponder:nil];
    self.scheduleForm = nil;
    self.changeForm = nil;
    self.reminderForm = nil;
    self.rescheduleForm = nil;
    self.cancelForm = nil;
    self.doneForm = nil;
    self.replaces = NO;
}

/* A distance's unit, where the form has none yet: the logbook's. */
- (void)unit:(NSString *)element of:(LBFormValues *)form {
    if (![form valueForKey:element] && [_windowController distanceUnit]) [form setValue:[_windowController distanceUnit] forKey:element];
}

- (IBAction)newSchedule:(id)sender {
    if (![_windowController chosenVehicle]) return;
    [self putAway];
    LBFormValues *form = [self form:@"SetUpSchedule" on:nil given:[self givenRecord]];
    if (!form) return;
    [self unit:@"intervalDistanceUnit" of:form];
    [self unit:@"lastDoneMileageDistanceUnit" of:form];
    self.scheduleForm = form;
    [self show:@"schedule" about:nil];
}

/* The schedule chosen, as it is, in its change's form. */
- (IBAction)editSchedule:(id)sender {
    Schedule *schedule = [self chosenSchedule];
    if (!schedule) return;
    [self putAway];
    LBFormValues *form = [self form:@"ChangeSchedule" on:schedule given:nil];
    if (!form) return;
    [self unit:@"intervalDistanceUnit" of:form];
    self.changeForm = form;
    [self show:@"change" about:nil];
    _scheduleFor = schedule;
}

- (IBAction)newReminder:(id)sender {
    if (![_windowController chosenVehicle]) return;
    [self putAway];
    NSMutableDictionary *given = [[self givenRecord] mutableCopy];
    given[@"setAt"] = [[[NSISO8601DateFormatter alloc] init] stringFromDate:[NSDate date]];
    LBFormValues *form = [self form:@"SetReminder" on:nil given:given];
    if (!form) return;
    [self unit:@"dueMileageDistanceUnit" of:form];
    self.reminderForm = form;
    [self show:@"reminder" about:nil];
}

/* Moved: a move of the reminder, from where it is due now. */
- (IBAction)reschedule:(id)sender {
    Reminder *reminder = [self chosenReminder];
    if (!reminder.lb_isOpen) return;
    [self putAway];
    LBFormValues *form = [self form:@"RescheduleReminder" on:nil
                              given:@{ @"reminder" : reminder.id.UUIDString ?: @"",
                                       @"madeBy" : _windowController.store.user.email ?: @"",
                                       @"madeAt" : [[[NSISO8601DateFormatter alloc] init] stringFromDate:[NSDate date]] }];
    if (!form) return;
    [form setValue:reminder.dueDate forKey:@"toDate"];
    [form setValue:reminder.dueMileageQuantity forKey:@"toMileageQuantity"];
    [form setValue:reminder.dueMileageDistanceUnit forKey:@"toMileageDistanceUnit"];
    [self unit:@"toMileageDistanceUnit" of:form];
    self.rescheduleForm = form;
    [self show:@"reschedule" about:reminder];
}

/* Cancelled today, unless the form says another day. */
- (IBAction)cancelReminder:(id)sender {
    Reminder *reminder = [self chosenReminder];
    if (!reminder.lb_isOpen) return;
    [self putAway];
    LBFormValues *form = [self form:@"CancelReminder" on:reminder given:nil];
    if (!form) return;
    [form setValue:LBToday() forKey:@"cancelDate"];
    [form setValue:reminder.dueMileageDistanceUnit ?: [_windowController distanceUnit] forKey:@"replacement/dueMileageDistanceUnit"];
    self.cancelForm = form;
    [self show:@"cancel" about:reminder];
}

/* Done by one of the vehicle's events that may close it, the latest
   first. */
- (IBAction)markDone:(id)sender {
    Reminder *reminder = [self chosenReminder];
    if (!reminder.lb_isOpen) return;
    [self putAway];
    LBFormValues *form = [self form:@"MarkReminderDone" on:reminder given:@{ @"vehicle" : reminder.vehicle.id.UUIDString ?: @"" }];
    if (!form) return;
    form.arrangesChoices = ^NSArray *(NSString *name, NSArray *choices) {
        if (![name isEqualToString:@"event"]) return choices;
        NSMutableArray *events = [NSMutableArray array];
        for (Event *event in choices) {
            if ([event isKindOfClass:[Event class]] && [event lb_mayCloseReminder:reminder]) [events addObject:event];
        }
        [events sortUsingFunction:LBLatestFirst context:NULL];
        return events;
    };
    [form setValue:[form.choices[@"event"] firstObject] forKey:@"event"];
    self.doneForm = form;
    [self show:@"done" about:reminder];
}

- (IBAction)closeForm:(id)sender {
    _formFor = nil;
    _scheduleFor = nil;
    [self putAway];
    [_forms selectTabViewItemWithIdentifier:LBNoForm];
}

- (IBAction)saveForm:(id)sender {
    if (![_windowController commitEdits]) return;
    NSString *shown = _forms.selectedTabViewItem.identifier;
    BOOL done = NO;
    if ([shown isEqualToString:@"schedule"]) done = [self saveSchedule];
    else if ([shown isEqualToString:@"change"]) done = [self saveScheduleChange];
    else if ([shown isEqualToString:@"reminder"]) done = [self saveReminder];
    else if ([shown isEqualToString:@"reschedule"]) done = [self saveReschedule];
    else if ([shown isEqualToString:@"cancel"]) done = [self saveCancel];
    else if ([shown isEqualToString:@"done"]) done = [self saveDone];
    if (done) [self closeForm:nil];
}

/* What the form says that cannot be done, said. */
- (BOOL)refuse:(NSString *)why {
    [_windowController reportError:[NSError errorWithDomain:LBProceduresErrorDomain code:LBProceduresErrorRefused
                                                   userInfo:@{ NSLocalizedDescriptionKey: why }]];
    return NO;
}

/* The form saved; refused, what it refused said under its fields, the rest
   in its words. */
- (BOOL)save:(LBFormValues *)form {
    NSError *error = nil;
    if ([form.session save:&error]) return YES;
    /* What the store refused, each violation said; else under the fields. */
    NSError *failure = error ?: [LBFormValues saveFailureOf:form.session];
    if (failure) {
        [_windowController reportError:failure];
        return NO;
    }
    NSArray<NSString *> *rest = [form showErrors:form.session.errors under:_forms];
    return [self refuse:rest.count ? [rest componentsJoinedByString:@"\n"] : @"Not saved: see under its fields."];
}

/* The form submitted to the server's action on the object (its procedure,
   done here offline), the parameters its values say: what the action
   refused said by the window. */
- (BOOL)submit:(LBFormValues *)form action:(NSString *)action on:(NSManagedObject *)object
    parameters:(NSDictionary *(^)(LBFormValues *form))parameters {
    __weak LBMainWindowController *window = _windowController;
    __block BOOL done = NO;
    form.session.submitting = ^NSDictionary<NSString *, NSString *> *(NSDictionary *values, NSString **savedKey) {
        id made = [window performAction:action on:object parameters:parameters(form)];
        done = made != nil;
        if (savedKey && [made isKindOfClass:[NSManagedObject class]] && [made valueForKey:@"id"]) *savedKey = [[made valueForKey:@"id"] UUIDString];
        return done ? @{} : @{ @"" : window.lastError.localizedDescription ?: @"Refused" };
    };
    NSError *error = nil;
    if (![form.session save:&error] && error) [_windowController reportError:error];
    return done;
}

/* A distance's parameters: the quantity and its unit's code. */
static void LBDistance(LBFormValues *form, NSString *element, NSMutableDictionary *parameters, NSString *name) {
    NSDecimalNumber *quantity = [form valueForKey:[element stringByAppendingString:@"Quantity"]];
    DistanceUnit *unit = [form valueForKey:[element stringByAppendingString:@"DistanceUnit"]];
    if (!quantity) return;
    parameters[name] = quantity;
    if (unit.code) parameters[[name stringByAppendingString:@"Unit"]] = unit.code;
}

/* A distance's unit alone, where the form has no quantity of it: none. */
static void LBNoLoneUnit(LBFormValues *form, NSString *element) {
    if (![form valueForKey:[element stringByAppendingString:@"Quantity"]]) [form setValue:nil forKey:[element stringByAppendingString:@"DistanceUnit"]];
}

/* Saved by its form, then started where the form says it was last done;
   else as the server works out. Not started, not kept, for the form to be
   put right. */
- (BOOL)saveSchedule {
    LBFormValues *form = _scheduleForm;
    if (!form) return NO;
    LBNoLoneUnit(form, @"interval");
    LBNoLoneUnit(form, @"lastDoneMileage");
    if (![self save:form]) {
        [self unit:@"intervalDistanceUnit" of:form];
        [self unit:@"lastDoneMileageDistanceUnit" of:form];
        return NO;
    }
    NSManagedObjectContext *context = _windowController.context;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Schedule class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(id)),
                                                       [[NSUUID alloc] initWithUUIDString:form.session.savedKey ?: @""]];
    Schedule *schedule = [[context executeFetchRequest:fetch error:NULL] firstObject];
    if (!schedule) return [self refuse:@"The schedule saved is not there to start"];
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    if (schedule.lastDoneOn) parameters[@"LastDoneAt"] = schedule.lastDoneOn;
    if (schedule.lastDoneMileageQuantity) {
        parameters[@"LastDoneMileage"] = schedule.lastDoneMileageQuantity;
        if (schedule.lastDoneMileageDistanceUnit.code) parameters[@"LastDoneMileageUnit"] = schedule.lastDoneMileageDistanceUnit.code;
    }
    if ([_windowController performAction:@"Start" on:schedule parameters:parameters]) return YES;
    [context deleteObject:schedule];
    [_windowController saveChanges];
    return NO;
}

/* The chosen schedule changed as the form says: not in place, but a new
   one going on from it, by the server's Continue (PROCESSES.md 11). Its
   open reminder goes with it, due anew; one moved or noted by hand is
   cancelled instead, which is said first. */
- (BOOL)saveScheduleChange {
    Schedule *schedule = _scheduleFor;
    LBFormValues *form = _changeForm;
    if (!schedule || !form) return NO;
    Reminder *open = schedule.lb_openReminder;
    if (open.lb_isTouched && !_windowController.quiet) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"The open reminder was changed by hand";
        alert.informativeText = [NSString stringWithFormat:@"It is due %@ as you set it. Changing the schedule cancels it, and plans the "
                                                           @"next by the changed schedule.", open.lbDue];
        [alert addButtonWithTitle:@"Change Schedule"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return NO;
    }
    return [self submit:form action:@"Continue" on:schedule parameters:^NSDictionary *(LBFormValues *values) {
        NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
        NSString *task = [[values valueForKey:@"task"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (task.length) parameters[@"Task"] = task;
        if ([values valueForKey:@"expenseKind"]) parameters[@"ExpenseKind"] = [values valueForKey:@"expenseKind"];
        if ([values valueForKey:@"checklist"]) parameters[@"Checklist"] = [values valueForKey:@"checklist"];
        LBDistance(values, @"interval", parameters, @"Interval");
        if ([[values valueForKey:@"duration"] integerValue] > 0) parameters[@"Months"] = @([[values valueForKey:@"duration"] integerValue]);
        NSString *note = [values valueForKey:@"note"];
        if (note.length) parameters[@"Note"] = note;
        return parameters;
    }];
}

- (BOOL)saveReminder {
    LBFormValues *form = _reminderForm;
    if (!form) return NO;
    LBNoLoneUnit(form, @"dueMileage");
    if (![self save:form]) {
        [self unit:@"dueMileageDistanceUnit" of:form];
        return NO;
    }
    [_windowController readAgain];
    return YES;
}

- (BOOL)saveReschedule {
    Reminder *reminder = _formFor;
    if (!reminder || !_rescheduleForm) return NO;
    return [self submit:_rescheduleForm action:@"Reschedule" on:reminder parameters:^NSDictionary *(LBFormValues *values) {
        NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
        if ([values valueForKey:@"toDate"]) parameters[@"DueDate"] = [values valueForKey:@"toDate"];
        LBDistance(values, @"toMileage", parameters, @"DueMileage");
        NSString *note = [values valueForKey:@"note"];
        if (note.length) parameters[@"Note"] = note;
        return parameters;
    }];
}

- (BOOL)saveCancel {
    Reminder *reminder = _formFor;
    if (!reminder || !_cancelForm) return NO;
    if (_replaces && ![_cancelForm valueForKey:@"replacement/dueDate"] && ![_cancelForm valueForKey:@"replacement/dueMileageQuantity"]) {
        return [self refuse:@"Say when the replacement is due"];
    }
    BOOL replaces = _replaces;
    return [self submit:_cancelForm action:@"Cancel" on:reminder parameters:^NSDictionary *(LBFormValues *values) {
        NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
        parameters[@"CancelDate"] = [values valueForKey:@"cancelDate"] ?: LBToday();
        if (replaces) {
            if ([values valueForKey:@"replacement/dueDate"]) parameters[@"ReplacementDueDate"] = [values valueForKey:@"replacement/dueDate"];
            LBDistance(values, @"replacement/dueMileage", parameters, @"ReplacementDueMileage");
        }
        return parameters;
    }];
}

- (BOOL)saveDone {
    Reminder *reminder = _formFor;
    if (!reminder || !_doneForm) return NO;
    if (![_doneForm valueForKey:@"event"]) return [self refuse:@"A reminder is done by an event: choose the one that did its work"];
    return [self submit:_doneForm action:@"Complete" on:reminder parameters:^NSDictionary *(LBFormValues *values) {
        return @{ @"Event" : [values valueForKey:@"event"] };
    }];
}

@end
