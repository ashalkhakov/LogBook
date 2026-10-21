#import "LBRemindersController.h"
#import "LBMainWindowController.h"
#import "LBStore.h"
#import "LBDisplay.h"
#import "LBProcedures.h"
#import "LogbookValidation.h"
#import "Vehicle+CoreDataClass.h"

static void *LBReminderChosen = &LBReminderChosen;
static void *LBScheduleChosen = &LBScheduleChosen;
static NSString * const LBNoForm = @"none";

@implementation LBReminderForm
@end

/* A day of the calendar here (what a date field gives: its local midnight)
   as the model's day of the same date, a UTC one; and back. */
static NSDate *LBModelDayOf(NSDate *local) {
    if (!local) return nil;
    NSDateComponents *parts = [[NSCalendar currentCalendar] components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                                              fromDate:local];
    NSCalendar *utc = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    utc.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return [utc dateFromComponents:parts];
}

static NSDate *LBLocalDateOf(NSDate *day) {
    if (!day) return nil;
    NSCalendar *utc = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    utc.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDateComponents *parts = [utc components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:day];
    return [[NSCalendar currentCalendar] dateFromComponents:parts];
}

/* Events latest first. */
static NSInteger LBLatestFirst(id a, id b, void *context) {
    return [(Event *)b lb_isBeforeEvent:(Event *)a] ? NSOrderedAscending : [(Event *)a lb_isBeforeEvent:(Event *)b] ? NSOrderedDescending
                                                                                                              : NSOrderedSame;
}

@interface LBRemindersController ()
@property (nonatomic, readwrite, strong) LBReminderForm *form;
@property (nonatomic, readwrite, copy) NSArray<Event *> *doneEvents;
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
    _form = [[LBReminderForm alloc] init];
    _doneEvents = @[];
    /* A vehicle's records, each list those of its kind. */
    NSString *kind = [NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(entity)), NSStringFromSelector(@selector(name))];
    _schedules.filterPredicate = [NSPredicate predicateWithFormat:@"%K == %@", kind, NSStringFromClass([Schedule class])];
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

- (void)show:(NSString *)identifier form:(LBReminderForm *)form about:(Reminder *)reminder {
    [_windowController.window makeFirstResponder:nil];
    _formFor = reminder;
    _scheduleFor = nil;
    self.form = form;
    [_forms selectTabViewItemWithIdentifier:identifier];
}

- (LBReminderForm *)newForm {
    LBReminderForm *form = [[LBReminderForm alloc] init];
    DistanceUnit *unit = [_windowController distanceUnit];
    form.unit = unit;
    form.everyUnit = unit;
    form.replacementUnit = unit;
    return form;
}

- (IBAction)newSchedule:(id)sender {
    if (![_windowController chosenVehicle]) return;
    [self show:@"schedule" form:[self newForm] about:nil];
}

/* The schedule chosen, as it is, in the schedule's form. */
- (IBAction)editSchedule:(id)sender {
    Schedule *schedule = [self chosenSchedule];
    if (!schedule) return;
    LBReminderForm *form = [self newForm];
    form.editing = YES;
    form.task = schedule.task;
    form.expenseKind = schedule.expenseKind;
    form.checklist = schedule.checklist;
    form.every = schedule.intervalQuantity;
    if (schedule.intervalDistanceUnit) form.everyUnit = schedule.intervalDistanceUnit;
    form.months = schedule.duration > 0 ? @(schedule.duration) : nil;
    form.note = schedule.note;
    [self show:@"schedule" form:form about:nil];
    _scheduleFor = schedule;
}

- (IBAction)newReminder:(id)sender {
    if (![_windowController chosenVehicle]) return;
    [self show:@"reminder" form:[self newForm] about:nil];
}

- (IBAction)reschedule:(id)sender {
    Reminder *reminder = [self chosenReminder];
    if (!reminder.lb_isOpen) return;
    LBReminderForm *form = [self newForm];
    form.date = LBLocalDateOf(reminder.dueDate);
    form.mileage = reminder.dueMileageQuantity;
    if (reminder.dueMileageDistanceUnit) form.unit = reminder.dueMileageDistanceUnit;
    [self show:@"reschedule" form:form about:reminder];
}

- (IBAction)cancelReminder:(id)sender {
    Reminder *reminder = [self chosenReminder];
    if (!reminder.lb_isOpen) return;
    LBReminderForm *form = [self newForm];
    form.date = [NSDate date];
    if (reminder.dueMileageDistanceUnit) form.replacementUnit = reminder.dueMileageDistanceUnit;
    [self show:@"cancel" form:form about:reminder];
}

- (IBAction)markDone:(id)sender {
    Reminder *reminder = [self chosenReminder];
    if (!reminder.lb_isOpen) return;
    NSMutableArray<Event *> *events = [NSMutableArray array];
    for (Record *record in reminder.vehicle.records) {
        if ([record isKindOfClass:[Event class]] && [(Event *)record lb_mayCloseReminder:reminder]) [events addObject:(Event *)record];
    }
    [events sortUsingFunction:LBLatestFirst context:NULL];
    self.doneEvents = events;
    LBReminderForm *form = [self newForm];
    form.event = events.firstObject;
    [self show:@"done" form:form about:reminder];
}

- (IBAction)closeForm:(id)sender {
    _formFor = nil;
    _scheduleFor = nil;
    self.form = [self newForm];
    [_forms selectTabViewItemWithIdentifier:LBNoForm];
}

- (IBAction)saveForm:(id)sender {
    if (![_windowController commitEdits]) return;
    NSString *shown = _forms.selectedTabViewItem.identifier;
    BOOL done = NO;
    if ([shown isEqualToString:@"schedule"]) done = _form.editing ? [self saveScheduleChange] : [self saveSchedule];
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

/* The work the form says, given to a schedule or a reminder: NO when it
   says not one. */
- (BOOL)work:(NSString **)task kind:(ExpenseKind **)kind checklist:(Checklist **)checklist {
    NSString *named = [_form.task stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    *task = named.length ? named : nil;
    *kind = _form.expenseKind;
    *checklist = _form.checklist;
    return (*task ? 1 : 0) + (*kind ? 1 : 0) + (*checklist ? 1 : 0) == 1;
}

/* A distance's parameters: the quantity and its unit's code. */
- (void)distance:(NSDecimalNumber *)quantity unit:(DistanceUnit *)unit into:(NSMutableDictionary *)parameters
          named:(NSString *)name {
    if (!quantity) return;
    parameters[name] = quantity;
    if (unit.code) parameters[[name stringByAppendingString:@"Unit"]] = unit.code;
}

- (BOOL)saveSchedule {
    Vehicle *vehicle = [_windowController chosenVehicle];
    NSString *task;
    ExpenseKind *kind;
    Checklist *checklist;
    if (!vehicle) return NO;
    if (![self work:&task kind:&kind checklist:&checklist]) {
        return [self refuse:@"A schedule is for a task, a kind of expense or a checklist: one of them"];
    }
    if (!_form.every && _form.months.integerValue < 1) return [self refuse:@"A schedule recurs every so far, every so many months, or both"];
    if (_form.every && !_form.everyUnit) return [self refuse:@"Say the unit of the distance"];
    NSManagedObjectContext *context = _windowController.context;
    Schedule *schedule = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Schedule class]) inManagedObjectContext:context];
    schedule.vehicle = vehicle;
    schedule.enteredBy = _windowController.store.user;
    schedule.task = task;
    schedule.expenseKind = kind;
    schedule.checklist = checklist;
    if (_form.every) {
        schedule.intervalQuantity = _form.every;
        schedule.intervalDistanceUnit = _form.everyUnit;
    }
    if (_form.months.integerValue > 0) schedule.duration = (int32_t)_form.months.integerValue;
    schedule.note = _form.note.length ? _form.note : nil;
    if (![_windowController saveChanges]) {
        [context deleteObject:schedule];
        return NO;
    }
    /* Started where the form says it was last done; else as the server
       works out. */
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    if (_form.date) parameters[@"LastDoneAt"] = LBModelDayOf(_form.date);
    [self distance:_form.mileage unit:_form.unit into:parameters named:@"LastDoneMileage"];
    if ([_windowController performAction:@"Start" on:schedule parameters:parameters]) return YES;
    /* Not started: not kept, for the form to be put right. */
    [context deleteObject:schedule];
    [_windowController saveChanges];
    return NO;
}

/* The chosen schedule changed as the form says. Its reminders are for its
   work, whatever it is now: they have none of their own. */
- (BOOL)saveScheduleChange {
    Schedule *schedule = _scheduleFor;
    NSString *task;
    ExpenseKind *kind;
    Checklist *checklist;
    if (!schedule) return NO;
    if (![self work:&task kind:&kind checklist:&checklist]) {
        return [self refuse:@"A schedule is for a task, a kind of expense or a checklist: one of them"];
    }
    if (!_form.every && _form.months.integerValue < 1) return [self refuse:@"A schedule recurs every so far, every so many months, or both"];
    if (_form.every && !_form.everyUnit) return [self refuse:@"Say the unit of the distance"];
    schedule.task = task;
    schedule.expenseKind = kind;
    schedule.checklist = checklist;
    schedule.intervalQuantity = _form.every;
    schedule.intervalDistanceUnit = _form.every ? _form.everyUnit : nil;
    /* No months: none recorded, not nought (the scalar accessor would say 0). */
    if (_form.months.integerValue > 0) schedule.duration = (int32_t)_form.months.integerValue;
    else [schedule setValue:nil forKey:NSStringFromSelector(@selector(duration))];
    schedule.note = _form.note.length ? _form.note : nil;
    if ([_windowController saveChanges]) {
        [_windowController readAgain];
        return YES;
    }
    /* Refused: as the server has it, for the form to be put right. */
    [schedule.managedObjectContext refreshObject:schedule mergeChanges:NO];
    return NO;
}

- (BOOL)saveReminder {
    Vehicle *vehicle = [_windowController chosenVehicle];
    NSString *task;
    ExpenseKind *kind;
    Checklist *checklist;
    if (!vehicle) return NO;
    if (![self work:&task kind:&kind checklist:&checklist]) {
        return [self refuse:@"A reminder is for a task, a kind of expense or a checklist: one of them"];
    }
    if (!_form.date && !_form.mileage) return [self refuse:@"A reminder is due on a day, at a distance, or both"];
    NSManagedObjectContext *context = _windowController.context;
    Reminder *reminder = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Reminder class]) inManagedObjectContext:context];
    reminder.vehicle = vehicle;
    reminder.enteredBy = _windowController.store.user;
    reminder.setAt = [NSDate date];
    reminder.task = task;
    reminder.expenseKind = kind;
    reminder.checklist = checklist;
    reminder.dueDate = LBModelDayOf(_form.date);
    if (_form.mileage) {
        reminder.dueMileageQuantity = _form.mileage;
        reminder.dueMileageDistanceUnit = _form.unit;
    }
    reminder.note = _form.note.length ? _form.note : nil;
    if ([_windowController saveChanges]) {
        [_windowController readAgain];
        return YES;
    }
    [context deleteObject:reminder];
    return NO;
}

- (BOOL)saveReschedule {
    Reminder *reminder = _formFor;
    if (!reminder) return NO;
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    if (_form.date) parameters[@"DueDate"] = LBModelDayOf(_form.date);
    [self distance:_form.mileage unit:_form.unit into:parameters named:@"DueMileage"];
    if (_form.note.length) parameters[@"Note"] = _form.note;
    return [_windowController performAction:@"Reschedule" on:reminder parameters:parameters] != nil;
}

- (BOOL)saveCancel {
    Reminder *reminder = _formFor;
    if (!reminder) return NO;
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"CancelDate"] = LBModelDayOf(_form.date ?: [NSDate date]);
    if (_form.replace) {
        if (!_form.replacementDate && !_form.replacementMileage) return [self refuse:@"Say when the replacement is due"];
        if (_form.replacementDate) parameters[@"ReplacementDueDate"] = LBModelDayOf(_form.replacementDate);
        [self distance:_form.replacementMileage unit:_form.replacementUnit into:parameters named:@"ReplacementDueMileage"];
    }
    return [_windowController performAction:@"Cancel" on:reminder parameters:parameters] != nil;
}

- (BOOL)saveDone {
    Reminder *reminder = _formFor;
    if (!reminder) return NO;
    if (!_form.event) return [self refuse:@"A reminder is done by an event: choose the one that did its work"];
    return [_windowController performAction:@"Complete" on:reminder parameters:@{ @"Event": _form.event }] != nil;
}

@end
