#import "LBMainWindowController.h"
#import "LBStore.h"
#import "LBLocalStore.h"
#import "LBDisplay.h"
#import "LBReportsController.h"
#import "LBRemindersController.h"
#import "LBAnswersController.h"
#import "LBCalendarController.h"
#import <ODataKit/ODataError.h>
#import "Schedule+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"
#import "Rescheduling+CoreDataClass.h"
#import "LBProcedures.h"
#import "LBImport.h"
#import "LBFieldIssues.h"
#import <ODataSync/ODataSignIn.h>
#import "ComponentChange+CoreDataClass.h"
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
#import "LBFormValues.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>

/* Something being typed in the window, or in its sheet: a field's editor
   open. Read again then, its row or field would be taken from under it. */
static BOOL LBTyping(NSWindow *window) {
    for (NSWindow *each in @[ window ?: [NSNull null], window.attachedSheet ?: [NSNull null] ]) {
        if (![each isKindOfClass:[NSWindow class]]) continue;
        id responder = each.firstResponder;
        if ([responder isKindOfClass:[NSText class]] && [(NSText *)responder isFieldEditor]) return YES;
    }
    return NO;
}

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
    /* The window's title while InvenTree is read. */
    NSString *_inventreeTitle;
    NSArray<NSString *> *_tripTitles;
    /* The chosen record as its model's form has it (Record<Kind>). */
    LBFormValues *_recordForm;
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (!self.isWindowLoaded) return;
    NSString *selection = NSStringFromSelector(@selector(selectionIndexes));
    [_vehicles removeObserver:self forKeyPath:selection context:LBVehicleChosen];
    [_records removeObserver:self forKeyPath:selection context:LBRecordChosen];
    [_records removeObserver:self forKeyPath:NSStringFromSelector(@selector(arrangedObjects)) context:LBRecordsChanged];
}

- (NSManagedObjectContext *)context {
    return _store.context;
}

/* Offline first: what a sync brought down (another device's), shown. */
- (void)storeDidSync:(NSNotification *)note {
    /* Not while the user types: once they are done. */
    if (self.isWindowLoaded && LBTyping(self.window)) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(storeDidSync:) object:nil];
        return [self performSelector:@selector(storeDidSync:) withObject:nil afterDelay:1];
    }
    [self readAgain];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    if (_store.local) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeDidSync:)
                                                                   name:LBLocalStoreDidSyncNotification object:_store.local];
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
    /* The rules a record or a vehicle breaks, at its fields. */
    _fieldIssues = [[LBFieldIssues alloc] initWithView:self.window.contentView];
    [_fieldIssues setNeedsRefresh];
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

/* A record as the model's form of its kind, Record<Kind> (ORMKit's
   docs/FORMS.md): its inputs the vehicle and who entered it, read from the
   store's context as it is now, what is typed written through to the
   record (the list shows it as it is typed), its choices the form's, and
   saved by the form (-saveChanges). What a save refused of a field is said
   under it, and gone once the field changes. nil, and why, where the app
   has no such form or it cannot read the record: its tab then shows none
   of it, never the record bound past its form. */
- (LBFormValues *)formOfRecord:(Record *)record error:(NSError **)error {
    /* One no longer in the store (deleted, or read again without it). */
    if (!record.managedObjectContext || !record.entity.name) return nil;
    ORMForm *form = [ORMForm formNamed:[@"Record" stringByAppendingString:record.entity.name] error:error];
    if (!form) return nil;
    /* A new one is given its key now, and so is what is new of it (an
       inspection's answers), as saving would: the form edits them by
       their keys. */
    [_store identifyInserted];
    ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form
                                                             given:@{ @"vehicle" : (record.vehicle ?: [self chosenVehicle]).id.UUIDString ?: @"",
                                                                      @"enteredBy" : record.enteredBy.email ?: _store.user.email ?: @"" }];
    LBStore *store = _store;
    [session useContext:self.context saving:^BOOL(NSManagedObjectContext *context, NSError **failure) {
        return [store save:failure];
    }];
    session.key = record.id.UUIDString;
    if (![session open:error]) return nil;
    LBFormValues *values = [[LBFormValues alloc] initWithSession:session object:record];
    __weak NSTabView *forms = _recordForms;
    values.changedHandler = ^(NSString *element) {
        [LBFormValues clearProblemAt:element under:forms];
    };
    return values;
}

/* The chosen record's form shown, given the record. */
- (void)recordChosen {
    NSArray *chosen = _records.selectedObjects;
    Record *record = chosen.count == 1 ? chosen[0] : nil;
    NSString *kind = record.entity.name;
    NSError *error = nil;
    _recordForm = record ? [self formOfRecord:record error:&error] : nil;
    if (record.managedObjectContext && !_recordForm) {
        NSLog(@"Logbook: %@ not opened in its form: %@", kind, error.localizedDescription);
        if (!_quiet) [self reportError:error ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError
                                                                userInfo:@{ NSLocalizedDescriptionKey : @"The record's form does not open." }]];
    }
    self.chosenRecords = kind && _recordForm ? @{ kind: _recordForm } : @{};
    [_recordForm showErrors:@{} under:_recordForms];
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
    /* Offline first, done here and saved here (then synced); online, the
       server's. */
    id result = [_store performAction:name on:object parameters:parameters error:error];
    if (result && _store.local && ![_store save:error]) {
        [self.context rollback];
        result = nil;
    }
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
    /* The server's objects read again; offline first, the context's are
       the store's, and a sync has refreshed what it brought. */
    if (!_store.local) {
        for (NSManagedObject *object in context.registeredObjects.allObjects) {
            if (!object.hasChanges) [context refreshObject:object mergeChanges:NO];
        }
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
    /* Each record changed of a kind the window shows (Record's lbKinds:
       a schedule or a reminder is the reminders' screen's) is saved by its
       form, all in one save, the rest with them: a refusal of the chosen one's fields said under them,
       the rest as any save's. Each is opened as it is now: Save may have
       completed it since it was chosen (its readings), or added it to its
       vehicle. */
    Record *chosen = (Record *)_recordForm.object;
    NSMutableArray<Record *> *changed = [NSMutableArray array];
    for (NSManagedObject *object in [self.context.insertedObjects setByAddingObjectsFromSet:self.context.updatedObjects]) {
        if ([object isKindOfClass:[Record class]] && !object.isDeleted && [[Record lbKinds] containsObject:object.entity.name]) {
            [changed addObject:(Record *)object];
        }
    }
    if ([changed containsObject:chosen]) {
        [changed removeObject:chosen];
        [changed insertObject:chosen atIndex:0];
    }
    NSMutableArray<ORMForm *> *forms = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *instances = [NSMutableArray array];
    for (Record *record in changed) {
        LBFormValues *form = [self formOfRecord:record error:&error];
        if (!form) {
            [self reportError:[self willPresentError:error]];
            return NO;
        }
        [forms addObject:form.session.form];
        [instances addObject:form.session.values];
    }
    if (forms.count) {
        NSDictionary<NSString *, NSString *> *errors = nil;
        LBStore *store = _store;
        NSArray *saved = [ORMForm saveForms:forms instances:instances inContext:self.context
                                     saving:^BOOL(NSManagedObjectContext *context, NSError **failure) { return [store save:failure]; }
                                     errors:&errors error:&error];
        if (!saved) {
            BOOL theirs = changed.firstObject == chosen && _recordForm;
            NSArray<NSString *> *rest = errors.count ? (theirs ? [_recordForm showErrors:errors under:_recordForms] : errors.allValues) : @[];
            if (!error && rest.count) {
                error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationMultipleErrorsError
                                        userInfo:@{ NSLocalizedDescriptionKey : @"The records were not saved.",
                                                    NSLocalizedRecoverySuggestionErrorKey : [rest componentsJoinedByString:@"\n"] }];
            }
            if (error) [self reportError:[self willPresentError:error]];
            else _lastError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationMultipleErrorsError
                                              userInfo:@{ NSLocalizedDescriptionKey : @"The record was not saved: see under its fields." }];
            return NO;
        }
        [_recordForm showErrors:@{} under:_recordForms];
    }
    if ([_store save:&error]) {
        _lastError = nil;
        if (stock) [[NSNotificationCenter defaultCenter] postNotificationName:LBStockDidChangeNotification object:self];
        return YES;
    }
    [self reportError:[self willPresentError:error]];
    return NO;
}

- (NSArray<NSString *> *)vehicleKinds {
    return @[ @"Car", @"Motorcycle", @"Bicycle" ];
}

- (NSString *)componentWear {
    id chosen = [_recordForm object];
    StockUnit *component = [chosen isKindOfClass:[ComponentChange class]] ? ((ComponentChange *)chosen).stockUnit : nil;
    if (!component) return @"";
    DistanceUnit *unit = [self distanceUnit];
    NSDecimalNumber *worn = unit ? [component lb_wornIn:unit] : nil;
    if (!worn) return @"At no reading yet.";
    NSString *distance = [NSString stringWithFormat:@"%@ %@", [NSNumberFormatter localizedStringFromNumber:worn
                                                                                                numberStyle:NSNumberFormatterDecimalStyle],
                                                     unit.code];
    /* Every time it was fitted, so far: it may have been on another before. */
    return [component lb_fittedTo] ? [NSString stringWithFormat:@"%@ so far, fitted", distance]
                                   : [NSString stringWithFormat:@"%@ in all, not fitted now", distance];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingComponentWear {
    return [NSSet setWithObject:@"chosenRecords"];
}

#pragma mark Import

- (IBAction)importRecords:(id)sender {
    Vehicle *vehicle = [self chosenVehicle];
    if (![self commitEdits]) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.message = vehicle ? [NSString stringWithFormat:@"Choose an export: Drivvo's CSV (into %@), or MainTrack's store (Maintrack.sqlite).",
                                                         vehicle.vehicleName]
                            : @"Choose an export: MainTrack's store (Maintrack.sqlite), or Drivvo's CSV with a vehicle chosen first.";
    /* MainTrack's store, where it is on this Mac: its folder is hidden. */
    NSString *mainTrack = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Group Containers/group.kiwiswift.mainTrack"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[mainTrack stringByAppendingPathComponent:@"Maintrack.sqlite"]])
        panel.directoryURL = [NSURL fileURLWithPath:mainTrack isDirectory:YES];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        /* After the panel has gone: the summary is a sheet of its own. */
        dispatch_async(dispatch_get_main_queue(), ^{
            [self askToImport:panel.URL intoVehicle:vehicle];
        });
    }];
}

/* What the export would make, and what it leaves out, said; imported once
   the user says Import. */
- (void)askToImport:(NSURL *)file intoVehicle:(Vehicle *)vehicle {
    NSError *error = nil;
    LBImport *import = [LBImport importOfFile:file error:&error];
    if (!import) return [self reportError:error];
    [self askToImportRecordsOf:import intoVehicle:vehicle];
}

- (void)askToImportRecordsOf:(LBImport *)import intoVehicle:(Vehicle *)vehicle {
    NSError *error = nil;
    if (!import.makesVehicles && !import.makesStock && !vehicle) {
        return [self reportError:[NSError errorWithDomain:LBImportErrorDomain code:1
                                                 userInfo:@{ NSLocalizedDescriptionKey : @"Choose the vehicle to import into first.",
                                                             NSLocalizedRecoverySuggestionErrorKey :
                                                                 @"Drivvo's export goes into a vehicle already set up: it says no make or year." }]];
    }
    /* Stock goes into a catalog: the one it went into before, else one
       named for where it comes from (the user may name another below). */
    BOOL inventree = [import.source isEqualToString:@"InvenTree"];
    NSString *catalogDefault = inventree ? ([[NSUserDefaults standardUserDefaults] stringForKey:@"LBInvenTreeCatalog"] ?: @"InvenTree") : @"Bike parts";
    if (import.makesStock) import.catalogName = catalogDefault;
    if (![import planForVehicle:vehicle by:_store.user error:&error]) return [self reportError:error];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = inventree              ? [NSString stringWithFormat:@"Import InvenTree's %@?", import.summary]
                        : import.makesVehicles ? [NSString stringWithFormat:@"Import %@'s %@?", import.source,
                                                                            [import.vehicleNames componentsJoinedByString:@", "]]
                                               : [NSString stringWithFormat:@"Import %@'s export into %@?", import.source, vehicle.vehicleName];
    alert.informativeText = [NSString stringWithFormat:@"%@.%@", inventree ? @"Its stock goes into the catalog named below" : import.summary,
                                                       import.leftOut.count ? @" Logbook has no place for these, or takes them so:" : @""];
    [alert addButtonWithTitle:@"Import"];
    [alert addButtonWithTitle:@"Cancel"];
    if (import.leftOut.count || import.makesStock) {
        NSArray *objects = nil;
        NSNib *nib = [[NSNib alloc] initWithNibNamed:@"ImportSummary" bundle:nil];
        if ([nib instantiateWithOwner:self topLevelObjects:&objects] && _importSummaryView) {
            [_importSummaryText setString:import.leftOut.count ? [@"• " stringByAppendingString:[import.leftOut componentsJoinedByString:@"\n• "]] : @""];
            alert.accessoryView = _importSummaryView;
        }
    }
    /* Its stock: into a catalog of the user's, or a new one. */
    if (_importCatalogField) {
        NSArray *names = [[_store.user.ownedCatalogs valueForKey:NSStringFromSelector(@selector(catalogName))] allObjects];
        [_importCatalogField addItemsWithObjectValues:[names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
        _importCatalogField.stringValue = catalogDefault;
        for (NSView *view in _importCatalogField.superview.subviews) {
            if (view == _importCatalogField || [view.identifier isEqualToString:@"importCatalogLabel"]) view.hidden = !import.makesStock;
        }
    }
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        NSString *catalog = [self.importCatalogField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.importSummaryView = nil;
        self.importSummaryText = nil;
        self.importCatalogField = nil;
        if (response != NSAlertFirstButtonReturn) return;
        if (inventree && catalog.length) [[NSUserDefaults standardUserDefaults] setObject:catalog forKey:@"LBInvenTreeCatalog"];
        NSUInteger made = 0, skipped = 0;
        NSError *failure = nil;
        BOOL done = [self importRecordsOf:import intoVehicle:vehicle catalogNamed:catalog made:&made skipped:&skipped error:&failure];
        if (!done) return [self reportError:failure];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *said = [[NSAlert alloc] init];
            said.messageText = [NSString stringWithFormat:@"%lu made, %lu there already.", (unsigned long)made, (unsigned long)skipped];
            said.informativeText = @"They are synced with the rest of your logbook.";
            [said beginSheetModalForWindow:self.window completionHandler:nil];
        });
    }];
}

- (BOOL)importFile:(NSURL *)file intoVehicle:(Vehicle *)vehicle made:(NSUInteger *)made skipped:(NSUInteger *)skipped error:(NSError **)error {
    return [self importFile:file intoVehicle:vehicle catalogNamed:nil made:made skipped:skipped error:error];
}

- (BOOL)importFile:(NSURL *)file intoVehicle:(Vehicle *)vehicle catalogNamed:(NSString *)catalog
              made:(NSUInteger *)made skipped:(NSUInteger *)skipped error:(NSError **)error {
    if (![self commitEdits]) return NO;
    LBImport *import = [LBImport importOfFile:file error:error];
    if (!import) return NO;
    return [self importRecordsOf:import intoVehicle:vehicle catalogNamed:catalog made:made skipped:skipped error:error];
}

- (BOOL)importRecordsOf:(LBImport *)import intoVehicle:(Vehicle *)vehicle catalogNamed:(NSString *)catalog
                   made:(NSUInteger *)made skipped:(NSUInteger *)skipped error:(NSError **)error {
    if (![self commitEdits]) return NO;
    import.catalogName = catalog.length ? catalog : nil;
    LBStore *store = _store;
    BOOL done = [import importIntoVehicle:vehicle by:store.user context:self.context
                                  saving:^BOOL(NSManagedObjectContext *context, NSError **failure) { return [store save:failure]; }
                                    made:made skipped:skipped error:error];
    [self readAgain];
    return done;
}

/* InvenTree's address and token asked, then its stock read (away from the
   window: it may take a while), then asked to import as an export is. */
- (IBAction)importFromInvenTree:(id)sender {
    if (![self commitEdits]) return;
    NSArray *objects = nil;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"InvenTreeConnect" bundle:nil];
    if (![nib instantiateWithOwner:self topLevelObjects:&objects] || !_inventreeConnectView) return;
    ODataSecretStore *secrets = [[ODataSecretStore alloc] initWithServiceName:@"Logbook InvenTree"];
    NSString *address = [[NSUserDefaults standardUserDefaults] stringForKey:@"LBInvenTreeAddress"];
    if (address.length) {
        _inventreeAddressField.stringValue = address;
        _inventreeTokenField.stringValue = [secrets secretsForAccount:address][@"token"] ?: @"";
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Import from InvenTree";
    alert.informativeText = @"Its address, and an API token that may read its parts, stock and purchase orders (in InvenTree: your user's settings, API Tokens).";
    alert.accessoryView = _inventreeConnectView;
    [alert addButtonWithTitle:@"Connect"];
    [alert addButtonWithTitle:@"Cancel"];
    [(NSWindow *)alert.window setInitialFirstResponder:address.length ? _inventreeTokenField : _inventreeAddressField];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        NSString *typed = [self.inventreeAddressField.stringValue stringByTrimmingCharactersInSet:space];
        NSString *token = [self.inventreeTokenField.stringValue stringByTrimmingCharactersInSet:space];
        self.inventreeConnectView = nil;
        self.inventreeAddressField = nil;
        self.inventreeTokenField = nil;
        if (response != NSAlertFirstButtonReturn) return;
        if (typed.length && ![typed containsString:@"://"]) typed = [@"https://" stringByAppendingString:typed];
        NSURL *root = typed.length ? [NSURL URLWithString:[typed hasSuffix:@"/"] ? typed : [typed stringByAppendingString:@"/"]] : nil;
        if (!root.host.length || !token.length) {
            return [self reportError:[NSError errorWithDomain:LBImportErrorDomain code:1
                                                     userInfo:@{ NSLocalizedDescriptionKey : @"Say InvenTree's address and an API token." }]];
        }
        [[NSUserDefaults standardUserDefaults] setObject:typed forKey:@"LBInvenTreeAddress"];
        [secrets setSecrets:@{ @"token" : token } forAccount:typed];
        [self readInvenTree:root token:token];
    }];
}

- (void)readInvenTree:(NSURL *)root token:(NSString *)token {
    _inventreeTitle = self.window.title;
    self.window.title = [NSString stringWithFormat:@"%@ — reading InvenTree…", _inventreeTitle];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        LBImport *read = [LBImport importOfInvenTree:root token:token fetch:nil error:&error];
        [self performSelectorOnMainThread:@selector(readInvenTreeGave:) withObject:read ?: (id)error ?: [NSNull null] waitUntilDone:NO];
    });
}

/* What reading InvenTree gave: its import, else why not. */
- (void)readInvenTreeGave:(id)gave {
    if (_inventreeTitle) self.window.title = _inventreeTitle;
    _inventreeTitle = nil;
    if ([gave isKindOfClass:[LBImport class]]) return [self askToImportRecordsOf:gave intoVehicle:nil];
    [self reportError:[gave isKindOfClass:[NSError class]] ? gave
                                                           : [NSError errorWithDomain:LBImportErrorDomain code:1
                                                                             userInfo:@{ NSLocalizedDescriptionKey : @"InvenTree was not read." }]];
}

- (void)reportError:(NSError *)error {
    error = [self willPresentError:error];
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
        /* A trip's length typed with no unit: its readings', else the user's. */
        if ([event isKindOfClass:[Trip class]]) {
            Trip *trip = (Trip *)event;
            if (trip.lengthQuantity && !trip.lengthDistanceUnit) trip.lengthDistanceUnit = trip.distanceDistanceUnit ?: [self distanceUnit];
        }
    }
}

- (IBAction)showParts:(id)sender {
    LBFormValues *form = _chosenRecords[NSStringFromClass([Service class])] ?: _chosenRecords[NSStringFromClass([TyreChange class])];
    Event *event = (Event *)form.object;
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
    if (!error.userInfo[NSDetailedErrorsKey] && !error.userInfo[NSValidationKeyErrorKey]) return error;
    NSString *said = [[LBLocalStore sentencesOfError:error] componentsJoinedByString:@"\n"];
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
    [self presentError:[self willPresentError:error]];
    return NO;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    return [self shouldClose];
}

@end

@implementation LBServiceItemController

- (id)newObject {
    ServiceItem *item = [super newObject];
    LBFormValues *service = _windowController.chosenRecords[NSStringFromClass([Service class])];
    item.costCurrency = [service valueForKey:@"currency"];
    return item;
}

@end

@implementation LBVehicleController

- (id)newObject {
    Vehicle *vehicle = [super newObject];
    vehicle.owner = _windowController.store.user;
    /* A car, most likely: the user says otherwise. */
    vehicle.vehicleKind = @"Car";
    return vehicle;
}

@end
