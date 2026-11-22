#import "LBStockCountWindowController.h"
#import "LBStore.h"
#import "LBStockDisplay.h"
#import "LBStockProcedures.h"
#import "LBTasks.h"
#import "LBFormValues.h"
#import <ORMRuntime/ORMFormSession.h>
#import <ORMRuntime/ORMFlowSession.h>

@interface LBStockCountWindowController ()
@property (nonatomic, readwrite, copy) NSArray<LBCountPlace *> *countPlaces;
@property (nonatomic, readwrite, strong) StockCount *stockCount;
@property (nonatomic, readwrite, strong) LBFormValues *countForm;
@property (nonatomic, readwrite, strong) LBFormValues *reviewForm;
@end

@implementation LBStockCountWindowController {
    ORMFlowSession *_flow;
    NSError *_flowError;
}

- (instancetype)initWithStore:(LBStore *)store catalog:(Catalog *)catalog {
    if ((self = [super initWithStore:store windowNibName:@"StockCount"])) {
        self.catalog = [self own:catalog];
        _countPlaces = @[];
        NSError *error = nil;
        _flow = [ORMFlowSession flowNamed:@"Counting" error:&error];
        if (!_flow) _flowError = error;
    }
    return self;
}

- (instancetype)initWithStore:(LBStore *)store count:(StockCount *)count {
    if ((self = [self initWithStore:store catalog:count.warehouse.catalog])) {
        _stockCount = [self own:count];
    }
    return self;
}

- (ORMFlowSession *)flow {
    return _flow;
}

- (NSString *)businessKey {
    return _stockCount.id.UUIDString;
}

- (NSArray<NSArrayController *> *)editedControllers {
    return @[ _countRows ];
}

- (void)readAgain {
    NSArray *warehouses = [self fetch:[Warehouse class] where:[NSPredicate predicateWithFormat:@"catalog == %@", self.catalog]
                             sortedBy:self.byTitle];
    NSArray *locations = [self fetch:[Location class] where:[NSPredicate predicateWithFormat:@"warehouse.catalog == %@", self.catalog]
                            sortedBy:self.byTitle];
    NSArray *places = [LBCountPlace placesOf:warehouses locations:locations];
    self.countPlaces = places;
    NSUInteger kept = _countPlace ? [places indexOfObject:_countPlace] : NSNotFound;
    self.countPlace = kept != NSNotFound ? places[kept] : places.firstObject;
    /* A count taken, shown as its form has it. */
    if (_stockCount && !_stockCount.inserted && !self.window.attachedSheet) [self openCountForm];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    _countRows.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"stockItem.itemName" ascending:YES],
                                    [NSSortDescriptor sortDescriptorWithKey:@"location.lbTitle" ascending:YES] ];
    [self setShowsExpected:_showsExpected];
}

/* Opened for its review's task: its sheet over the count at once. */
- (void)showWindow:(id)sender {
    [super showWindow:sender];
    if (!_stockCount || !self.task.entryName || ![self.task.flowName isEqualToString:@"Counting"] || self.window.attachedSheet) return;
    NSError *error = nil;
    ORMFlowStep *step = [_flow beginAt:self.task.entryName key:_stockCount.id.UUIDString error:&error];
    if (!step) return [self reportError:error ?: _flowError];
    if (![step.formName isEqualToString:@"ReviewStockCount"]) {
        return [self refuse:[NSString stringWithFormat:@"%@ has no view in the count's window.", step.formName]];
    }
    self.reviewForm = [self valuesOfForm:step.formName given:step.given object:_stockCount];
    if (_reviewForm) [self.window beginSheet:_reviewPanel completionHandler:nil];
}

/* What is held, shown or not: the column of what each line's place holds
   (its form's held). */
- (void)setShowsExpected:(BOOL)shows {
    _showsExpected = shows;
    [_countRowsTable tableColumnWithIdentifier:@"expected"].hidden = !shows;
}

- (void)openCountForm {
    NSMutableDictionary *given = [@{ @"warehouse" : _stockCount.warehouse.id.UUIDString ?: @"",
                                     @"runningNumber" : [NSString stringWithFormat:@"%d", _stockCount.runningNumber],
                                     @"counter" : _stockCount.counter.email ?: @"",
                                     @"countState" : _stockCount.countState ?: @"" } mutableCopy];
    if (_stockCount.countedLocation) given[@"countedLocation"] = _stockCount.countedLocation.id.UUIDString;
    self.countForm = [self valuesOfForm:@"CountStock" given:given object:_stockCount];
}

- (CountLine *)lineOf:(StockItem *)item at:(Location *)place {
    CountLine *line = [NSEntityDescription insertNewObjectForEntityForName:@"CountLine" inManagedObjectContext:self.context];
    line.id = [NSUUID UUID];
    line.stockCount = _stockCount;
    line.stockItem = item;
    line.location = place;
    /* What the place holds of it, as the model works it out when it saves
       (CountLineHeld): shown while the count is taken. */
    for (Holding *holding in place.holdings) {
        if (holding.stockItem == item) line.held = holding.quantity;
    }
    return line;
}

- (IBAction)startCount:(id)sender {
    if (!_countPlace || ![self commitEdits]) return;
    if (_stockCount.inserted) [self.context rollback];
    Warehouse *warehouse = _countPlace.warehouse;
    int32_t number = 0;
    for (StockCount *each in warehouse.stockCounts) number = MAX(number, each.runningNumber);
    StockCount *count = [NSEntityDescription insertNewObjectForEntityForName:@"StockCount" inManagedObjectContext:self.context];
    count.id = [NSUUID UUID];
    count.warehouse = warehouse;
    count.countedLocation = _countPlace.location;
    count.countedOn = [NSDate date];
    count.counter = self.user;
    count.runningNumber = number + 1;
    count.countState = @"Counted";
    self.stockCount = count;
    NSMutableArray *at = [NSMutableArray array];
    for (Location *place in _countPlace.locations) [at addObject:[NSPredicate predicateWithFormat:@"location == %@", place]];
    NSArray *holdings = [self fetch:[Holding class] where:[NSCompoundPredicate orPredicateWithSubpredicates:at] sortedBy:nil];
    for (Holding *holding in holdings) {
        if (holding.stockItem && holding.location) [self lineOf:holding.stockItem at:holding.location];
    }
    [self openCountForm];
}

- (IBAction)addCountRow:(id)sender {
    if (!_stockCount.inserted) return [self refuse:@"Start a count first."];
    if (![self commitEdits]) return;
    NSArray *items = [_countForm valueForKeyPath:@"choices.countLines.stockItem"];
    NSArray *places = [_countForm valueForKeyPath:@"choices.countLines.location"];
    /* Where it counts: its location, else the warehouse's first. */
    Location *place = _stockCount.countedLocation ?: [places firstObject];
    CountLine *line = [self lineOf:[items firstObject] at:place];
    [_countRows rearrangeObjects];
    [_countRows setSelectedObjects:@[ line ]];
}

- (IBAction)removeCountRow:(id)sender {
    for (CountLine *line in _countRows.selectedObjects) [self.context deleteObject:line];
}

- (IBAction)submitCount:(id)sender {
    if (!_stockCount.inserted || ![self commitEdits]) return;
    for (CountLine *line in _stockCount.countLines) {
        if (!line.isDeleted && !line.found) return [self refuse:@"Type what was found of each (0 for none)."];
    }
    /* Saved by its form, opened again on it as it is now. */
    LBFormValues *now = [self valuesOfForm:@"CountStock" given:_countForm.session.given object:_stockCount];
    NSError *error = nil;
    if (!now || ![now.session save:&error]) {
        if (now) [self refuseForm:now error:error under:self.window.contentView];
        return;
    }
    _submitted = _stockCount;
    self.countForm = nil;
    self.stockCount = nil;
    [self readAgain];
}

- (IBAction)submitReview:(id)sender {
    if (![self submitForm:_reviewForm sheet:_reviewPanel]) return;
    [self endReview];
}

- (void)endReview {
    NSWindow *sheet = self.window.attachedSheet;
    if (sheet) [self.window endSheet:sheet];
    [sheet orderOut:nil];
    self.reviewForm = nil;
    [self readAgain];
}

- (IBAction)dismissForm:(id)sender {
    [self.context rollback];
    [self endReview];
}

- (void)cancelOperation:(id)sender {
    if (self.window.attachedSheet) [self dismissForm:sender];
}

@end
