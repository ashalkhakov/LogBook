#import "LBCatalogSettingsWindowController.h"
#import "LBStore.h"
#import "LBStockDisplay.h"

static void *LBWarehouseChosen = &LBWarehouseChosen;

@interface LBCatalogSettingsWindowController ()
@property (nonatomic, readwrite, copy) NSArray<Warehouse *> *warehouses;
@property (nonatomic, readwrite, copy) NSArray<Location *> *warehouseLocations;
@property (nonatomic, readwrite, copy) NSArray<Category *> *categories;
@property (nonatomic, readwrite, copy) NSArray<Contact *> *contacts;
@property (nonatomic, readwrite, copy) NSArray<WeightUnit *> *weightUnits;
@property (nonatomic, readwrite, copy) NSArray<SizeUnit *> *sizeUnits;
@end

@implementation LBCatalogSettingsWindowController {
    /* Every location of the catalog's: the chosen warehouse's are listed. */
    NSArray<Location *> *_locations;
}

- (instancetype)initWithStore:(LBStore *)store catalog:(Catalog *)catalog {
    if ((self = [super initWithStore:store windowNibName:@"CatalogSettings"])) {
        self.catalog = [self own:catalog];
        _warehouses = @[];
        _warehouseLocations = @[];
        _categories = @[];
        _contacts = @[];
        _weightUnits = @[];
        _sizeUnits = @[];
        _locations = @[];
    }
    return self;
}

- (void)dealloc {
    if (self.isWindowLoaded) [_warehouseList removeObserver:self forKeyPath:@"selectionIndexes" context:LBWarehouseChosen];
}

- (void)windowDidLoad {
    [_warehouseList addObserver:self forKeyPath:@"selectionIndexes" options:0 context:LBWarehouseChosen];
    [super windowDidLoad];
    [self.window bind:NSTitleBinding toObject:self withKeyPath:@"catalog.catalogName" options:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == LBWarehouseChosen) [self listLocations];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (NSArray<NSArrayController *> *)editedControllers {
    return @[ _warehouseList, _locationList, _categoryList, _contactList ];
}

#pragma mark Reading

- (void)readAgain {
    Catalog *catalog = self.catalog;
    NSPredicate *ofCatalog = [NSPredicate predicateWithFormat:@"catalog == %@", catalog];
    [self fetch:[Catalog class] where:[NSPredicate predicateWithFormat:@"id == %@", catalog.id] sortedBy:nil];
    self.warehouses = [self fetch:[Warehouse class] where:ofCatalog sortedBy:self.byTitle];
    _locations = [self fetch:[Location class] where:[NSPredicate predicateWithFormat:@"warehouse.catalog == %@", catalog] sortedBy:self.byTitle];
    [self listLocations];
    self.categories = [self fetch:[Category class] where:ofCatalog sortedBy:self.byTitle];
    self.contacts = [self fetch:[Contact class] where:ofCatalog sortedBy:self.byTitle];
    NSArray *largest = @[ [NSSortDescriptor sortDescriptorWithKey:@"factor" ascending:NO] ];
    if (!_weightUnits.count) self.weightUnits = [self fetch:[WeightUnit class] where:nil sortedBy:largest];
    if (!_sizeUnits.count) self.sizeUnits = [self fetch:[SizeUnit class] where:nil sortedBy:largest];
    /* Its fields, bound through the catalog, read it again. */
    [self willChangeValueForKey:@"catalog"];
    [self didChangeValueForKey:@"catalog"];
}

/* The chosen warehouse's locations, those added here too. */
- (void)listLocations {
    Warehouse *chosen = _warehouseList.selectedObjects.count == 1 ? _warehouseList.selectedObjects[0] : nil;
    NSArray *its = [_locations filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"warehouse == %@ AND isDeleted == NO", chosen]];
    self.warehouseLocations = chosen ? its : @[];
}

#pragma mark Rows

/* A new object of the class, named so under the key, listed under the
   list's key, chosen, its name ready to be typed over in the table. */
- (id)add:(Class)cls named:(NSString *)name key:(NSString *)key list:(NSString *)list
       to:(NSArrayController *)controller table:(NSTableView *)table {
    if (![self commitEdits]) return nil;
    NSManagedObject *row = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass(cls) inManagedObjectContext:self.context];
    [row setValue:[NSUUID UUID] forKey:@"id"];
    [row setValue:name forKey:key];
    [self setValue:[[self valueForKey:list] arrayByAddingObject:row] forKey:list];
    [controller setSelectedObjects:@[ row ]];
    NSUInteger index = [controller.arrangedObjects indexOfObjectIdenticalTo:row];
    if (index != NSNotFound) [table editColumn:0 row:(NSInteger)index withEvent:nil select:YES];
    return row;
}

/* The chosen ones of the controller deleted, and no longer listed. */
- (void)remove:(NSArrayController *)controller list:(NSString *)list {
    NSArray *chosen = controller.selectedObjects;
    for (NSManagedObject *row in chosen) [self.context deleteObject:row];
    NSMutableArray *left = [[self valueForKey:list] mutableCopy];
    [left removeObjectsInArray:chosen];
    [self setValue:left forKey:list];
}

- (IBAction)addWarehouse:(id)sender {
    Warehouse *warehouse = [self add:[Warehouse class] named:@"New Warehouse" key:@"warehouseName" list:@"warehouses" to:_warehouseList
                               table:_warehousesTable];
    warehouse.catalog = self.catalog;
}

- (IBAction)removeWarehouse:(id)sender {
    [self remove:_warehouseList list:@"warehouses"];
}

- (IBAction)addLocation:(id)sender {
    Warehouse *chosen = _warehouseList.selectedObjects.count == 1 ? _warehouseList.selectedObjects[0] : nil;
    if (!chosen) return;
    Location *place = [self add:[Location class] named:@"New Location" key:@"locationName" list:@"warehouseLocations" to:_locationList
                          table:_locationsTable];
    place.warehouse = chosen;
    _locations = [_locations arrayByAddingObject:place];
}

- (IBAction)removeLocation:(id)sender {
    [self remove:_locationList list:@"warehouseLocations"];
}

- (IBAction)addCategory:(id)sender {
    Category *category = [self add:[Category class] named:@"New Category" key:@"categoryName" list:@"categories" to:_categoryList
                             table:_categoriesTable];
    category.catalog = self.catalog;
}

- (IBAction)removeCategory:(id)sender {
    [self remove:_categoryList list:@"categories"];
}

- (IBAction)addContact:(id)sender {
    Contact *contact = [self add:[Contact class] named:@"New Contact" key:@"contactName" list:@"contacts" to:_contactList
                           table:_contactsTable];
    contact.catalog = self.catalog;
}

- (IBAction)removeContact:(id)sender {
    for (Contact *contact in _contactList.selectedObjects) {
        contact.lb_isCustomer = NO;
        contact.lb_isSupplier = NO;
    }
    [self remove:_contactList list:@"contacts"];
}

@end
