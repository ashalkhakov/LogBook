#import "LBMainWindowController.h"
#import "LBStore.h"
#import "LBDisplay.h"
#import "VehicleDriver+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "Expense+CoreDataClass.h"
#import "Income+CoreDataClass.h"
#import "Trip+CoreDataClass.h"

static void *LBVehicleChosen = &LBVehicleChosen;
static void *LBRecordChosen = &LBRecordChosen;
static void *LBRecordsChanged = &LBRecordsChanged;

@interface LBMainWindowController ()
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, id> *chosenRecords;
@property (nonatomic, readwrite, copy) NSArray<User *> *drivers;
@property (nonatomic, readwrite, copy) NSArray<TyreSet *> *tyreSets;
@end

#ifdef GNUSTEP
/* gnustep-base parses no decimal number (its generatesDecimalNumbers
   fails every string): a number parsed, then the string read as one. */
@interface LBDecimalFormatter : NSNumberFormatter
@end

@implementation LBDecimalFormatter
- (BOOL)getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString **)error {
    id number = nil;
    if (![super getObjectValue:&number forString:string errorDescription:error]) return NO;
    NSString *plain = [[string stringByReplacingOccurrencesOfString:self.groupingSeparator withString:@""]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSDecimalNumber *decimal = [NSDecimalNumber decimalNumberWithString:plain locale:@{ NSLocaleDecimalSeparator: self.decimalSeparator }];
    if (object) *object = number && ![decimal isEqual:[NSDecimalNumber notANumber]] ? decimal : number;
    return YES;
}
@end

/* gnustep-gui reads a XIB's formatters without their settings (a decimal
   number style, decimals generated, a date's style): set from the
   attribute the field shows, until the stack reads them. */
static void LBSetUpFormatter(NSTextField *field, NSManagedObjectModel *model) {
    NSDictionary *info = [field infoForBinding:NSValueBinding];
    NSObjectController *controller = info[NSObservedObjectKey];
    NSString *key = [[info[NSObservedKeyPathKey] componentsSeparatedByString:@"."] lastObject];
    if (![controller isKindOfClass:[NSObjectController class]] || !key) return;
    NSEntityDescription *entity = [model.entitiesByName objectForKey:NSStringFromClass(controller.objectClass)];
    NSAttributeDescription *attribute = [entity.attributesByName objectForKey:key];
    if ([field.formatter isKindOfClass:[NSNumberFormatter class]]) {
        BOOL decimal = attribute.attributeType == NSDecimalAttributeType;
        NSNumberFormatter *number = decimal ? [[LBDecimalFormatter alloc] init] : field.formatter;
        number.numberStyle = decimal ? NSNumberFormatterDecimalStyle : NSNumberFormatterNoStyle;
        number.usesGroupingSeparator = NO;
        number.maximumFractionDigits = decimal ? 3 : 0;
        field.formatter = number;
    }
    if ([field.formatter isKindOfClass:[NSDateFormatter class]]) {
        NSDateFormatter *date = field.formatter;
        date.dateStyle = NSDateFormatterShortStyle;
        date.timeStyle = [key.lowercaseString hasSuffix:@"date"] ? NSDateFormatterNoStyle : NSDateFormatterShortStyle;
    }
}

/* Every field's, those of tabs not shown too. */
static void LBSetUpFormatters(NSView *view, NSManagedObjectModel *model) {
    if ([view isKindOfClass:[NSTextField class]]) LBSetUpFormatter((NSTextField *)view, model);
    if ([view isKindOfClass:[NSTabView class]]) {
        for (NSTabViewItem *item in ((NSTabView *)view).tabViewItems) LBSetUpFormatters(item.view, model);
        return;
    }
    for (NSView *each in view.subviews) LBSetUpFormatters(each, model);
}
#endif

@implementation LBMainWindowController

- (instancetype)initWithStore:(LBStore *)store {
    if ((self = [super initWithWindowNibName:@"MainWindow"])) {
        _store = store;
        _chosenRecords = @{};
        _drivers = @[];
        _tyreSets = @[];
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
#ifdef GNUSTEP
    LBSetUpFormatters(self.window.contentView, self.context.persistentStoreCoordinator.managedObjectModel);
#endif
    _records.parentKey = NSStringFromSelector(@selector(records));
    _records.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbDate)) ascending:NO] ];
    NSArray<NSString *> *kinds = [Record lbKinds];
    for (NSUInteger i = 0; i < kinds.count; i++) {
        NSMenuItem *item = [_addRecordButton.menu addItemWithTitle:[Record lbKindOfEntityNamed:kinds[i]] action:@selector(addRecord:)
                                                     keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)i;
    }
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

/* Its records listed, its drivers to choose from. */
- (void)vehicleChosen {
    Vehicle *vehicle = [self chosenVehicle];
    _records.parentObject = vehicle;
    NSMutableArray<User *> *drivers = [NSMutableArray array];
    if (vehicle.owner) [drivers addObject:vehicle.owner];
    for (VehicleDriver *shared in vehicle.vehicleDrivers) {
        if (shared.user && ![drivers containsObject:shared.user]) [drivers addObject:shared.user];
    }
    self.drivers = drivers;
}

/* The chosen record's form shown, given the record. */
- (void)recordChosen {
    NSArray *chosen = _records.selectedObjects;
    Record *record = chosen.count == 1 ? chosen[0] : nil;
    NSString *kind = record.entity.name;
    self.chosenRecords = kind ? @{ kind: record } : @{};
    NSInteger form = [_recordForms indexOfTabViewItemWithIdentifier:kind ?: @"none"];
    [_recordForms selectTabViewItemAtIndex:form == NSNotFound ? 0 : form];
}

- (void)recordsChanged {
    NSMutableArray<TyreSet *> *tyreSets = [NSMutableArray array];
    for (Record *record in _records.arrangedObjects) {
        if ([record isKindOfClass:[TyreSet class]]) [tyreSets addObject:(TyreSet *)record];
    }
    if (![tyreSets isEqualToArray:_tyreSets]) self.tyreSets = tyreSets;
}

- (IBAction)addRecord:(id)sender {
    NSArray<NSString *> *kinds = [Record lbKinds];
    NSInteger kind = [sender respondsToSelector:@selector(tag)] ? [sender tag] : -1;
    Vehicle *vehicle = [self chosenVehicle];
    if (kind < 0 || kind >= (NSInteger)kinds.count || !vehicle || ![self commitEdits]) return;
    Record *record = [NSEntityDescription insertNewObjectForEntityForName:kinds[(NSUInteger)kind] inManagedObjectContext:self.context];
    record.vehicle = vehicle;
    record.enteredBy = _store.user;
    [self fillIn:record];
    [_records addObject:record];
}

/* What a new record most likely is: now, by whoever is signed in, in
   their units and currency. */
- (void)fillIn:(Record *)record {
    User *user = _store.user;
    NSString *currency = user.currency ?: [[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode] ?: @"EUR";
    if ([record isKindOfClass:[Event class]]) {
        Event *event = (Event *)record;
        event.timestamp = [NSDate date];
        event.driver = user;
    }
    if ([record isKindOfClass:[MeteredEvent class]]) ((MeteredEvent *)record).mileageDistanceUnit = [self distanceUnit];
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

- (IBAction)save:(id)sender {
    if (![self commitEdits]) return;
    NSArray<NSError *> *warnings = [_store warnings];
    if (warnings.count && !_quiet && ![self proceedDespite:warnings]) return;
    NSError *error = nil;
    _lastError = [_store save:&error] ? nil : [self willPresentError:error];
    if (_lastError && !_quiet) [self presentError:error];
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
    NSArray *each = error.userInfo[NSDetailedErrorsKey] ?: error.userInfo[@"NSDetailedErrors"] ?: error.userInfo[@"NSDetailedErrorsKey"];
    if (!each.count) return error;
    NSString *said = [[each valueForKey:NSStringFromSelector(@selector(localizedDescription))] componentsJoinedByString:@"\n"];
    return [NSError errorWithDomain:error.domain code:error.code
                           userInfo:@{ NSLocalizedDescriptionKey: @"The changes break the logbook's rules",
                                       NSLocalizedRecoverySuggestionErrorKey: said }];
}

- (IBAction)revertChanges:(id)sender {
    [self.window makeFirstResponder:nil];
    [_store.context rollback];
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

@implementation LBVehicleController

- (id)newObject {
    Vehicle *vehicle = [super newObject];
    vehicle.owner = _windowController.store.user;
    return vehicle;
}

@end
