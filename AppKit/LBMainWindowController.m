#import "LBMainWindowController.h"
#import "LBStore.h"
#import "LBDisplay.h"
#import "LBReportsController.h"
#import "LBRemindersController.h"
#import "LBAnswersController.h"
#import "LBCalendarController.h"
#import <ODataIncrementalStore/ODataOperationCall.h>
#import <ODataKit/ODataError.h>
#import "Schedule+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"
#import "Rescheduling+CoreDataClass.h"
#import "LBProcedures.h"
#import "VehicleDriver+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "Expense+CoreDataClass.h"
#import "Income+CoreDataClass.h"
#import "Trip+CoreDataClass.h"
#import "TyreChange+CoreDataClass.h"
#import "MeterReading+CoreDataClass.h"
#import "Inspection+CoreDataClass.h"
#import "Attachment+CoreDataClass.h"
#import "LBPartsPanelController.h"
#import "LBStockEditor.h"
#import "LBStockProcedures.h"

static void *LBVehicleChosen = &LBVehicleChosen;
static void *LBRecordChosen = &LBRecordChosen;
static void *LBRecordsChanged = &LBRecordsChanged;

@interface LBMainWindowController ()
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, id> *chosenRecords;
@property (nonatomic, readwrite, copy) NSArray<User *> *drivers;
@property (nonatomic, readwrite, copy) NSArray<TyreSet *> *tyreSets;
@property (nonatomic, readwrite, copy) NSArray<Trip *> *trips;
@property (nonatomic, readwrite, copy) NSArray<CostKind *> *serviceKinds;
@end

@implementation LBMainWindowController {
    NSArray<NSString *> *_tyreSetTitles;
    NSArray<NSString *> *_tripTitles;
}

- (instancetype)initWithStore:(LBStore *)store {
    if ((self = [super initWithWindowNibName:@"MainWindow"])) {
        _store = store;
        _chosenRecords = @{};
        _drivers = @[];
        _tyreSets = @[];
        _trips = @[];
        _serviceKinds = @[];
    }
    return self;
}

- (void)dealloc {
    if (!self.isWindowLoaded) return;
    NSString *selection = NSStringFromSelector(@selector(selectionIndexes));
    [_vehicles removeObserver:self forKeyPath:selection context:LBVehicleChosen];
    [_records removeObserver:self forKeyPath:selection context:LBRecordChosen];
    [_records removeObserver:self forKeyPath:NSStringFromSelector(@selector(arrangedObjects)) context:LBRecordsChanged];
}

- (NSManagedObjectContext *)context {
    return _store.context;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.title = [NSString stringWithFormat:@"Logbook — %@", _store.serviceRoot.host ?: @""];
    _vehicles.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(vehicleName)) ascending:YES
                                                                  selector:@selector(localizedCaseInsensitiveCompare:)] ];
    /* No smaller than drawn in MainWindow.xib (a frame saved before may
       be): the forms' fields keep their widths. */
    NSSize drawn = NSMakeSize(1060, 680);
    NSSize now = [self.window.contentView frame].size;
    self.window.contentMinSize = drawn;
    if (now.width < drawn.width || now.height < drawn.height) {
        [self.window setContentSize:NSMakeSize(MAX(now.width, drawn.width), MAX(now.height, drawn.height))];
    }
    _records.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbDate)) ascending:NO] ];
    /* A vehicle's schedules and reminders are the Reminders tab's. */
    NSString *kind = [NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(entity)), NSStringFromSelector(@selector(name))];
    _records.filterPredicate = [NSPredicate predicateWithFormat:@"NOT (%K IN %@)", kind,
                                                                @[ NSStringFromClass([Schedule class]), NSStringFromClass([Reminder class]) ]];
    _records.clearsFilterPredicateOnInsertion = NO;
    NSArray<NSString *> *kinds = [Record lbKinds];
    for (NSUInteger i = 0; i < kinds.count; i++) {
        NSMenuItem *item = [_addRecordButton.menu addItemWithTitle:[Record lbKindOfEntityNamed:kinds[i]] action:@selector(addRecord:)
                                                     keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)i;
    }
    [_reports chooseReport:nil];
    /* Reference data, the model's: read once. */
    self.serviceKinds = [CostKind lbServiceKindsInContext:self.context];
    _attachments.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(fileName)) ascending:YES] ];
    /* A day of the model (bought on, issued, expires) is a UTC day: its
       field reads and says it so, whatever the zone here. */
    for (NSTabViewItem *form in _recordForms.tabViewItems) {
        for (NSString *identifier in @[ @"TyreSetDate", @"DocumentDate", @"DocumentExpires" ]) {
            NSTextField *field = (NSTextField *)[self controlOf:identifier in:form.view];
            ((NSDateFormatter *)field.formatter).timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        }
    }
    _attachmentsTable.target = self;
    _attachmentsTable.doubleAction = @selector(openAttachment:);
    NSString *selection = NSStringFromSelector(@selector(selectionIndexes));
    [_vehicles addObserver:self forKeyPath:selection options:NSKeyValueObservingOptionInitial context:LBVehicleChosen];
    [_records addObserver:self forKeyPath:selection options:NSKeyValueObservingOptionInitial context:LBRecordChosen];
    [_records addObserver:self forKeyPath:NSStringFromSelector(@selector(arrangedObjects)) options:NSKeyValueObservingOptionInitial
                  context:LBRecordsChanged];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == LBVehicleChosen) [self vehicleChosen];
    else if (context == LBRecordChosen) [self recordChosen];
    else if (context == LBRecordsChanged) [self recordsChanged];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (nullable Vehicle *)chosenVehicle {
    NSArray *chosen = _vehicles.selectedObjects;
    return chosen.count == 1 ? chosen[0] : nil;
}

- (NSArray<NSSortDescriptor *> *)byTitle {
    return @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbTitle)) ascending:YES
                                             selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

/* Its drivers to choose from (its records the XIB binds). */
/* The control of the identifier, in the view or under it. */
- (NSView *)controlOf:(NSString *)identifier in:(NSView *)view {
    if ([view.identifier isEqualToString:identifier]) return view;
    for (NSView *each in view.subviews) {
        NSView *found = [self controlOf:identifier in:each];
        if (found) return found;
    }
    return nil;
}

- (void)vehicleChosen {
    Vehicle *vehicle = [self chosenVehicle];
    NSMutableArray<User *> *drivers = [NSMutableArray array];
    if (vehicle.owner) [drivers addObject:vehicle.owner];
    for (VehicleDriver *shared in vehicle.vehicleDrivers) {
        if (shared.user && !shared.isDeleted && ![drivers containsObject:shared.user]) [drivers addObject:shared.user];
    }
    self.drivers = [drivers sortedArrayUsingDescriptors:[self byTitle]];
    [_reports vehicleChosen];
    [_remindersController refresh];
    [_calendarController refresh];
}

/* The chosen record's form shown, given the record. */
- (void)recordChosen {
    NSArray *chosen = _records.selectedObjects;
    Record *record = chosen.count == 1 ? chosen[0] : nil;
    NSString *kind = record.entity.name;
    self.chosenRecords = kind ? @{ kind: record } : @{};
    NSInteger form = [_recordForms indexOfTabViewItemWithIdentifier:kind ?: @"none"];
    [_recordForms selectTabViewItemAtIndex:form == NSNotFound ? 0 : form];
    [self answersChanged];
}

/* The chosen inspection's answers shown, as they are now. */
- (void)answersChanged {
    NSArray *chosen = _records.selectedObjects;
    Record *record = chosen.count == 1 ? chosen[0] : nil;
    [_answersController showInspection:[record isKindOfClass:[Inspection class]] ? (Inspection *)record : nil];
}

/* A pick list's objects, said anew when they or what it calls them (their
   titles, as typed since) changed. */
- (BOOL)list:(NSArray *)list differsFrom:(NSArray *)shown titled:(NSArray<NSString *> *)titles {
    return ![list isEqualToArray:shown] || ![[list valueForKey:NSStringFromSelector(@selector(lbTitle))] isEqualToArray:titles];
}

- (void)recordsChanged {
    NSMutableArray<TyreSet *> *tyreSets = [NSMutableArray array];
    for (Record *record in _records.arrangedObjects) {
        if ([record isKindOfClass:[TyreSet class]]) [tyreSets addObject:(TyreSet *)record];
    }
    [tyreSets sortUsingDescriptors:[self byTitle]];
    if ([self list:tyreSets differsFrom:_tyreSets titled:_tyreSetTitles]) {
        _tyreSetTitles = [tyreSets valueForKey:NSStringFromSelector(@selector(lbTitle))];
        self.tyreSets = tyreSets;
    }
    NSMutableArray<Trip *> *trips = [NSMutableArray array];
    for (Record *record in _records.arrangedObjects) {
        if ([record isKindOfClass:[Trip class]]) [trips addObject:(Trip *)record];
    }
    [trips sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(timestamp)) ascending:NO] ]];
    if ([self list:trips differsFrom:_trips titled:_tripTitles]) {
        _tripTitles = [trips valueForKey:NSStringFromSelector(@selector(lbTitle))];
        self.trips = trips;
    }
}

- (IBAction)addRecord:(id)sender {
    NSArray<NSString *> *kinds = [Record lbKinds];
    NSInteger kind = [sender respondsToSelector:@selector(tag)] ? [sender tag] : -1;
    Vehicle *vehicle = [self chosenVehicle];
    if (kind < 0 || kind >= (NSInteger)kinds.count || !vehicle || ![self commitEdits]) return;
    Record *record = [NSEntityDescription insertNewObjectForEntityForName:kinds[(NSUInteger)kind] inManagedObjectContext:self.context];
    record.enteredBy = _store.user;
    [self fillIn:record];
    /* Into the vehicle's records, which the controller's content is: its
       vehicle set with it, and it chosen. */
    [_records addObject:record];
}

- (IBAction)share:(id)sender {
    Vehicle *vehicle = [self chosenVehicle];
    if (![self commitEdits] || !vehicle) return;
    NSString *email = [[_shareEmail stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (![email containsString:@"@"]) {
        NSBeep();
        return;
    }
    User *user = [self userWithEmail:email];
    if (user == vehicle.owner) {
        NSBeep();
        return;
    }
    for (VehicleDriver *shared in vehicle.vehicleDrivers) {
        if (shared.user == user) return;
    }
    VehicleDriver *sharing = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([VehicleDriver class])
                                                           inManagedObjectContext:self.context];
    sharing.user = user;
    [_vehicleDrivers addObject:sharing];
    self.shareEmail = nil;
    [self vehicleChosen];
}

/* The logbook's user of an email, or one made of it. */
- (User *)userWithEmail:(NSString *)email {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([User class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(email)), email];
    User *user = [[self.context executeFetchRequest:fetch error:NULL] firstObject];
    if (user) return user;
    user = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([User class]) inManagedObjectContext:self.context];
    user.email = email;
    return user;
}

- (IBAction)unshare:(id)sender {
    if (![self commitEdits]) return;
    for (VehicleDriver *sharing in [_vehicleDrivers.selectedObjects copy]) [self.context deleteObject:sharing];
    [self vehicleChosen];
}

- (IBAction)openAttachment:(id)sender {
    Attachment *attachment = _attachments.selectedObjects.firstObject;
    if (!attachment) return;
    NSError *error = nil;
    NSURL *file = [self fileOfAttachment:attachment error:&error];
    if (!file) {
        [self reportError:error];
        return;
    }
    if (!_quiet && ![[NSWorkspace sharedWorkspace] openURL:file]) NSBeep();
}

- (IBAction)addAttachment:(id)sender {
    Record *record = _records.selectedObjects.count == 1 ? _records.selectedObjects.firstObject : nil;
    if (!record) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"Attach";
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *error = nil;
    if (![self attachFileAtURL:panel.URL toRecord:record error:&error]) [self reportError:error];
}

- (Attachment *)attachFileAtURL:(NSURL *)url toRecord:(Record *)record error:(NSError **)error {
    NSData *content = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!content) return nil;
    Attachment *attachment = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Attachment class])
                                                           inManagedObjectContext:self.context];
    attachment.fileName = url.lastPathComponent;
    attachment.content = content;
    attachment.record = record;
    [_attachments setSelectedObjects:@[ attachment ]];
    return attachment;
}

- (IBAction)removeAttachment:(id)sender {
    Attachment *attachment = _attachments.selectedObjects.firstObject;
    if (attachment) [self.context deleteObject:attachment];
}

- (NSURL *)fileOfAttachment:(Attachment *)attachment error:(NSError **)error {
    NSData *content = attachment.content;
    NSString *name = attachment.fileName.lastPathComponent;
    if (!content || !name.length || !attachment.id) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                            userInfo:@{ NSLocalizedDescriptionKey: @"The attachment has no file here." }];
        return nil;
    }
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                   [@"Logbook-" stringByAppendingString:attachment.id.UUIDString.lowercaseString]];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSURL *file = [NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];
    return [content writeToURL:file options:NSDataWritingAtomic error:error] ? file : nil;
}

/* The records chosen gone from the logbook, not only from the vehicle; an
   event that closed reminders discarded on the server, what it closed
   reopened. */
- (IBAction)removeRecord:(id)sender {
    if (![self commitEdits]) return;
    for (Record *record in [_records.selectedObjects copy]) {
        BOOL closed = [record isKindOfClass:[Event class]] && !record.objectID.isTemporaryID && ((Event *)record).reminders.count;
        if (closed) [self discard:record];
        else [self.context deleteObject:record];
    }
}

/* Discarded: when a next reminder it made has been changed since, the
   owner asked whether to delete it too (a reminder is done only by an
   event, so it cannot stay done once the record goes). */
- (void)discard:(Record *)record {
    NSError *error = nil;
    if ([self call:@"Discard" on:record parameters:@{} error:&error]) return;
    if ([error.userInfo[ODataErrorCodeKey] isEqual:@"NextReminderTouched"] && !_quiet) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"A reminder it made next has been changed since it was made";
        alert.informativeText = @"Discarding the record deletes that reminder too, and what you changed of it.";
        [alert addButtonWithTitle:@"Delete It Too"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        error = nil;
        if ([self call:@"Discard" on:record parameters:@{ @"KeepNextReminder": @NO } error:&error]) return;
    }
    [self reportError:error];
}

- (NSArray<NSError *> *)reminderWarnings {
    NSMutableArray *warnings = [NSMutableArray array];
    NSMutableSet *changed = [NSMutableSet setWithSet:self.context.insertedObjects];
    [changed unionSet:self.context.updatedObjects];
    for (NSManagedObject *object in changed) {
        if (![object isKindOfClass:[Event class]] || object.isDeleted) continue;
        Event *event = (Event *)object;
        if (event.mileageQuantity && event.mileageDistanceUnit) continue;
        for (Record *record in event.vehicle.records) {
            if (![record isKindOfClass:[Reminder class]]) continue;
            Reminder *reminder = (Reminder *)record;
            if (!reminder.schedule.intervalQuantity || !reminder.lb_isOpen || ![event lb_mayCloseReminder:reminder]) continue;
            NSString *said = [NSString stringWithFormat:@"This %@ closes the reminder for %@, which recurs every %@: without its odometer "
                                                        @"reading, no next reminder is made.",
                                                        event.lbKind.lowercaseString, reminder.lbWork,
                                                        LBDistanceText(reminder.schedule.intervalQuantity, reminder.schedule.intervalDistanceUnit)];
            [warnings addObject:[NSError errorWithDomain:LBProceduresErrorDomain code:LBProceduresErrorRefused
                                                userInfo:@{ NSLocalizedDescriptionKey: said }]];
        }
    }
    return warnings;
}

- (id)performAction:(NSString *)name on:(NSManagedObject *)object parameters:(NSDictionary *)parameters {
    NSError *error = nil;
    id result = [self call:name on:object parameters:parameters error:&error];
    if (!result) [self reportError:error];
    return result;
}

/* The action called, the changes saved before, what it changed read after. */
- (id)call:(NSString *)name on:(NSManagedObject *)object parameters:(NSDictionary *)parameters error:(NSError **)error {
    if (![self commitEdits]) return nil;
    if (self.context.hasChanges && ![self saveChanges]) {
        if (error) *error = _lastError;
        return nil;
    }
    ODataOperationCall *call = [ODataOperationCall callOfOperation:name onObject:object];
    call.parameters = parameters;
    id result = [call invoke:error];
    [self readAgain];
    if (result) _lastError = nil;
    return result;
}

- (void)readAgain {
    /* The records chosen stay chosen, wherever they now sort. */
    NSArray *chosen = _records.selectedObjects;
    NSManagedObjectContext *context = self.context;
    Vehicle *vehicle = [self chosenVehicle];
    if (vehicle) {
        /* The server's rows of the vehicle's records, and of their moves,
           for the objects to be read from. */
        NSFetchRequest *records = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Record class])];
        records.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(vehicle)), vehicle];
        NSError *error = nil;
        if (![context executeFetchRequest:records error:&error]) NSLog(@"Logbook: the records not read again: %@", error.localizedDescription);
        NSFetchRequest *moves = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Rescheduling class])];
        moves.predicate = [NSPredicate predicateWithFormat:@"%K.%K == %@", NSStringFromSelector(@selector(reminder)),
                                                           NSStringFromSelector(@selector(vehicle)), vehicle];
        if (![context executeFetchRequest:moves error:&error]) NSLog(@"Logbook: the moves not read again: %@", error.localizedDescription);
    }
    for (NSManagedObject *object in context.registeredObjects.allObjects) {
        if (!object.hasChanges) [context refreshObject:object mergeChanges:NO];
    }
    /* What shows the chosen vehicle's records asks for them again (the
       vehicle itself is not changed). */
    NSString *selection = NSStringFromSelector(@selector(selection));
    [_vehicles willChangeValueForKey:selection];
    [_vehicles didChangeValueForKey:selection];
    [_remindersController refresh];
    [_calendarController refresh];
    NSMutableArray *still = [NSMutableArray array];
    for (Record *record in chosen) {
        if (!record.isDeleted && record.managedObjectContext) [still addObject:record];
    }
    if (still.count) [_records setSelectedObjects:still];
    [self answersChanged];
}

- (BOOL)saveChanges {
    NSError *error = nil;
    /* A record's parts shipped as the server saves: the stock windows told. */
    BOOL stock = NO;
    for (NSManagedObject *object in [self.context.insertedObjects setByAddingObjectsFromSet:self.context.updatedObjects]) {
        stock = stock || [object isKindOfClass:[SaleOrder class]] || [object isKindOfClass:[SaleLine class]];
    }
    if ([_store save:&error]) {
        _lastError = nil;
        if (stock) [[NSNotificationCenter defaultCenter] postNotificationName:LBStockDidChangeNotification object:self];
        return YES;
    }
    [self reportError:[self willPresentError:error]];
    return NO;
}

- (void)reportError:(NSError *)error {
    _lastError = error;
    if (error && !_quiet) [self presentError:error];
}

/* What a new record most likely is: now, by whoever is signed in, in
   their units and currency. */
- (void)fillIn:(Record *)record {
    User *user = _store.user;
    NSString *currency = user.lbCurrency ?: @"EUR";
    if ([record isKindOfClass:[Event class]]) {
        Event *event = (Event *)record;
        event.timestamp = [NSDate date];
        /* Where it happens: its day is taken there. */
        event.timeZone = [NSTimeZone localTimeZone].name;
        event.driver = user;
    }
    /* A metered event's odometer, in their unit (any event may have one:
       an expense, an income). */
    for (Class metered in @[ [FillUp class], [Service class], [Trip class], [TyreChange class], [MeterReading class],
                             [Inspection class] ]) {
        if ([record isKindOfClass:metered]) ((Event *)record).mileageDistanceUnit = [self distanceUnit];
    }
    if ([record isKindOfClass:[FillUp class]]) {
        FillUp *fillUp = (FillUp *)record;
        fillUp.volumeVolumeUnit = [self volumeUnit];
        fillUp.filledTheTank = YES;
        fillUp.totalCurrency = currency;
    }
    if ([record isKindOfClass:[Expense class]]) record.totalCurrency = currency;
    if ([record isKindOfClass:[Service class]]) ((Service *)record).currency = currency;
    if ([record isKindOfClass:[Income class]]) ((Income *)record).earnedCurrency = currency;
    if ([record isKindOfClass:[Trip class]]) {
        Trip *trip = (Trip *)record;
        trip.moment = [NSDate date];
        trip.distanceDistanceUnit = [self distanceUnit];
    }
}

/* The user's unit, else the metric one. */
- (nullable DistanceUnit *)distanceUnit {
    return _store.user.distanceUnit ?: [self unitOf:[DistanceUnit class] coded:@"km"];
}

- (nullable VolumeUnit *)volumeUnit {
    return _store.user.volumeUnit ?: [self unitOf:[VolumeUnit class] coded:@"L"];
}

- (nullable id)unitOf:(Class)unitClass coded:(NSString *)code {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(unitClass)];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(code)), code];
    return [[self.context executeFetchRequest:fetch error:NULL] firstObject];
}

/* What is being typed, kept: the field editor ended, the controllers told. */
- (BOOL)commitEdits {
    if (![self.window makeFirstResponder:nil]) return NO;
    for (NSArrayController *controller in @[ _vehicles, _records ]) {
        if (![controller commitEditing]) return NO;
    }
    return YES;
}

/* An odometer reading typed where it may be left out (an expense's, an
   income's) with no unit chosen: in the user's. */
- (void)completeReadings {
    NSMutableSet *changed = [NSMutableSet setWithSet:self.context.insertedObjects];
    [changed unionSet:self.context.updatedObjects];
    for (NSManagedObject *object in changed) {
        if (![object isKindOfClass:[Event class]]) continue;
        Event *event = (Event *)object;
        if (event.mileageQuantity && !event.mileageDistanceUnit) event.mileageDistanceUnit = [self distanceUnit];
    }
}

- (IBAction)showParts:(id)sender {
    Event *event = _chosenRecords[NSStringFromClass([Service class])] ?: _chosenRecords[NSStringFromClass([TyreChange class])];
    if (!event.lb_usesParts) return;
    if (_partsPanel.event != event) {
        [_partsPanel close];
        _partsPanel = [[LBPartsPanelController alloc] initWithEvent:event];
        _partsPanel.quiet = _quiet;
    }
    [_partsPanel showWindow:sender];
}

- (IBAction)save:(id)sender {
    if (![self commitEdits]) return;
    [self completeReadings];
    NSArray<NSError *> *warnings = [[_store warnings] arrayByAddingObjectsFromArray:[self reminderWarnings]];
    if (warnings.count && !_quiet && ![self proceedDespite:warnings]) return;
    /* Saved, and what the server did as it saved read again: an event
       closes the reminders it does the work of. */
    if ([self saveChanges]) [self readAgain];
}

/* The deontic rules a change breaks: what ought not to be, but may. */
- (BOOL)proceedDespite:(NSArray<NSError *> *)warnings {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = warnings.count == 1 ? @"This ought not to be so" : @"These ought not to be so";
    alert.informativeText = [[warnings valueForKey:NSStringFromSelector(@selector(localizedDescription))] componentsJoinedByString:@"\n"];
    [alert addButtonWithTitle:@"Save Anyway"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

/* A save's refusal, each violation said: Core Data's message names none. */
- (NSError *)willPresentError:(NSError *)error {
    NSArray *each = error.userInfo[NSDetailedErrorsKey];
    if (!each.count) return error;
    NSString *said = [[each valueForKey:NSStringFromSelector(@selector(localizedDescription))] componentsJoinedByString:@"\n"];
    return [NSError errorWithDomain:error.domain code:error.code
                           userInfo:@{ NSLocalizedDescriptionKey: @"The changes break the logbook's rules",
                                       NSLocalizedRecoverySuggestionErrorKey: said }];
}

- (IBAction)revertChanges:(id)sender {
    [self.window makeFirstResponder:nil];
    [_store.context rollback];
    [self answersChanged];
}

- (BOOL)shouldClose {
    if (![self commitEdits]) return NO;
    if (!_store.context.hasChanges) return YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save the changes before closing?";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Don't Save"];
    NSModalResponse answer = [alert runModal];
    if (answer == NSAlertSecondButtonReturn) return NO;
    if (answer == NSAlertThirdButtonReturn) return YES;
    NSError *error = nil;
    if ([_store save:&error]) return YES;
    [self presentError:error];
    return NO;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    return [self shouldClose];
}

@end

@implementation LBServiceItemController

- (id)newObject {
    ServiceItem *item = [super newObject];
    Service *service = _windowController.chosenRecords[NSStringFromClass([Service class])];
    item.costCurrency = service.currency;
    return item;
}

@end

@implementation LBVehicleController

- (id)newObject {
    Vehicle *vehicle = [super newObject];
    vehicle.owner = _windowController.store.user;
    return vehicle;
}

@end
