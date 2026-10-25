#import "LBStockCountWindowController.h"
#import "LBStore.h"
#import "LBStockDisplay.h"

@implementation LBCountPlace

- (instancetype)initWithWarehouse:(Warehouse *)warehouse location:(Location *)location locations:(NSArray<Location *> *)locations {
    if ((self = [super init])) {
        _warehouse = warehouse;
        _location = location;
        _locations = location ? @[ location ] : [locations copy];
    }
    return self;
}

- (NSString *)lbTitle {
    return _location ? _location.lbTitle : [NSString stringWithFormat:@"%@ (all of it)", _warehouse.lbTitle];
}

/* The same place however often the list is made: a pop-up keeps it. */
- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:[LBCountPlace class]] && ((LBCountPlace *)other).warehouse == _warehouse
           && ((LBCountPlace *)other).location == _location;
}

- (NSUInteger)hash {
    return _warehouse.hash ^ _location.hash;
}

@end

@interface LBCountRow ()
- (instancetype)initWithHeld:(NSDictionary *)held shows:(BOOL)shows;
- (void)setShows:(BOOL)shows;
@end

@implementation LBCountRow {
    /* What the count's places hold: by item and location. */
    NSDictionary *_held;
    BOOL _shows;
}

- (instancetype)initWithHeld:(NSDictionary *)held shows:(BOOL)shows {
    if ((self = [super init])) {
        _held = held;
        _shows = shows;
    }
    return self;
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingExpectedShown {
    return [NSSet setWithObjects:@"item", @"location", nil];
}

- (void)setShows:(BOOL)shows {
    [self willChangeValueForKey:@"expectedShown"];
    _shows = shows;
    [self didChangeValueForKey:@"expectedShown"];
}

- (NSDecimalNumber *)expectedShown {
    if (!_shows || !_item || !_location) return nil;
    return _held[@[ _item.objectID, _location.objectID ]] ?: [NSDecimalNumber zero];
}

@end

@interface LBStockCountWindowController ()
@property (nonatomic, readwrite, copy) NSArray<LBCountPlace *> *countPlaces;
@property (nonatomic, readwrite, copy) NSArray<LBCountRow *> *rowsCounted;
@property (nonatomic, readwrite, copy) NSArray<Location *> *countLocations;
@property (nonatomic, readwrite, copy) NSArray<StockItem *> *catalogItems;
@end

@implementation LBStockCountWindowController {
    /* What the count being taken is of; none, none is. */
    LBCountPlace *_counting;
    /* What its places hold, as the count started. */
    NSDictionary *_held;
}

- (instancetype)initWithStore:(LBStore *)store catalog:(Catalog *)catalog {
    if ((self = [super initWithStore:store windowNibName:@"StockCount"])) {
        self.catalog = [self own:catalog];
        _countPlaces = @[];
        _rowsCounted = @[];
        _countLocations = @[];
        _catalogItems = @[];
        _held = @{};
    }
    return self;
}

- (NSArray<NSArrayController *> *)editedControllers {
    return @[ _countRows ];
}

- (void)readAgain {
    NSArray *warehouses = [self fetch:[Warehouse class] where:[NSPredicate predicateWithFormat:@"catalog == %@", self.catalog]
                             sortedBy:self.byTitle];
    NSArray *locations = [self fetch:[Location class] where:[NSPredicate predicateWithFormat:@"warehouse.catalog == %@", self.catalog]
                            sortedBy:self.byTitle];
    NSMutableArray *places = [NSMutableArray array];
    for (Warehouse *warehouse in warehouses) {
        NSArray *its = [locations filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"warehouse == %@", warehouse]];
        [places addObject:[[LBCountPlace alloc] initWithWarehouse:warehouse location:nil locations:its]];
        for (Location *place in its) [places addObject:[[LBCountPlace alloc] initWithWarehouse:warehouse location:place locations:its]];
    }
    self.countPlaces = places;
    NSUInteger kept = _countPlace ? [places indexOfObject:_countPlace] : NSNotFound;
    self.countPlace = kept != NSNotFound ? places[kept] : places.firstObject;
    self.catalogItems = [self fetch:[StockItem class] where:[NSPredicate predicateWithFormat:@"catalog == %@", self.catalog]
                           sortedBy:self.byTitle];
}

- (void)setShowsExpected:(BOOL)shows {
    _showsExpected = shows;
    for (LBCountRow *row in _rowsCounted) [row setShows:shows];
}

- (LBCountRow *)rowOf:(StockItem *)item at:(Location *)place {
    LBCountRow *row = [[LBCountRow alloc] initWithHeld:_held shows:_showsExpected];
    row.item = item;
    row.location = place;
    return row;
}

- (IBAction)startCount:(id)sender {
    if (!_countPlace || ![self commitEdits]) return;
    _counting = _countPlace;
    NSMutableArray *at = [NSMutableArray array];
    for (Location *place in _counting.locations) [at addObject:[NSPredicate predicateWithFormat:@"location == %@", place]];
    NSArray *holdings = [self fetch:[Holding class] where:[NSCompoundPredicate orPredicateWithSubpredicates:at]
                           sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"stockItem.itemName" ascending:YES],
                                       [NSSortDescriptor sortDescriptorWithKey:@"location.lbTitle" ascending:YES] ]];
    NSMutableDictionary *held = [NSMutableDictionary dictionary];
    for (Holding *holding in holdings) {
        if (holding.stockItem && holding.location) held[@[ holding.stockItem.objectID, holding.location.objectID ]] = holding.quantity ?: [NSDecimalNumber zero];
    }
    _held = held;
    NSMutableArray *rows = [NSMutableArray array];
    for (Holding *holding in holdings) {
        if (holding.stockItem && holding.location) [rows addObject:[self rowOf:holding.stockItem at:holding.location]];
    }
    self.countLocations = _counting.locations;
    self.rowsCounted = rows;
}

- (IBAction)addCountRow:(id)sender {
    if (!_counting) return [self refuse:@"Start a count first."];
    if (![self commitEdits]) return;
    LBCountRow *row = [self rowOf:_catalogItems.firstObject at:_countLocations.firstObject];
    self.rowsCounted = [_rowsCounted arrayByAddingObject:row];
    [_countRows setSelectedObjects:@[ row ]];
}

- (IBAction)removeCountRow:(id)sender {
    NSMutableArray *rows = [_rowsCounted mutableCopy];
    [rows removeObjectsInArray:_countRows.selectedObjects];
    self.rowsCounted = rows;
}

- (IBAction)postCount:(id)sender {
    if (!_counting || ![self commitEdits]) return;
    NSMutableArray *found = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (LBCountRow *row in _rowsCounted) {
        if (!row.item || !row.location || !row.found) return [self refuse:@"Type what was found of each (0 for none)."];
        NSArray *key = @[ row.item.objectID, row.location.objectID ];
        if ([seen containsObject:key]) {
            return [self refuse:[NSString stringWithFormat:@"%@ at %@ is counted twice.", row.item.lbTitle, row.location.lbTitle]];
        }
        [seen addObject:key];
        [found addObject:@{ @"Item": row.item.id.UUIDString, @"Location": row.location.id.UUIDString, @"Quantity": row.found }];
    }
    NSMutableDictionary *parameters = [@{ @"Found": found } mutableCopy];
    if (_counting.location) parameters[@"Location"] = _counting.location;
    id count = [self performAction:@"Count" on:_counting.warehouse parameters:parameters];
    if (!count) return;
    _posted = [count isKindOfClass:[StockCount class]] ? [self own:count] : nil;
    _counting = nil;
    self.rowsCounted = @[];
}

@end
