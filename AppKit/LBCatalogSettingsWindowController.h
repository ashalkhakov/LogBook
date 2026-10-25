// A catalog's settings (CatalogSettings.xib; docs/STOCK.md, Setup): its
// name, currency, prefix and units; its warehouses and their locations;
// its categories; its contacts, which are its customers and suppliers. It
// reads the catalog and what is of it.

#import "LBStockEditor.h"

@class Warehouse, Location, Category, Contact, WeightUnit, SizeUnit;

NS_ASSUME_NONNULL_BEGIN

@interface LBCatalogSettingsWindowController : LBStockEditor

- (instancetype)initWithStore:(LBStore *)store catalog:(Catalog *)catalog;

// Its warehouses, the chosen one's locations, its categories, its
// contacts; each by title.
@property (nonatomic, readonly, copy) NSArray<Warehouse *> *warehouses;
@property (nonatomic, readonly, copy) NSArray<Location *> *warehouseLocations;
@property (nonatomic, readonly, copy) NSArray<Category *> *categories;
@property (nonatomic, readonly, copy) NSArray<Contact *> *contacts;
@property (nonatomic, strong) IBOutlet NSArrayController *warehouseList;
@property (nonatomic, strong) IBOutlet NSArrayController *locationList;
@property (nonatomic, strong) IBOutlet NSArrayController *categoryList;
@property (nonatomic, strong) IBOutlet NSArrayController *contactList;
@property (nonatomic, strong) IBOutlet NSTableView *warehousesTable;
@property (nonatomic, strong) IBOutlet NSTableView *locationsTable;
@property (nonatomic, strong) IBOutlet NSTableView *categoriesTable;
@property (nonatomic, strong) IBOutlet NSTableView *contactsTable;
// The units its weights and sizes are given in.
@property (nonatomic, readonly, copy) NSArray<WeightUnit *> *weightUnits;
@property (nonatomic, readonly, copy) NSArray<SizeUnit *> *sizeUnits;

// A new row of each, named to be typed over, chosen; the chosen ones
// removed (refused at save where something is of them; a contact no
// longer a customer or supplier first).
- (IBAction)addWarehouse:(nullable id)sender;
- (IBAction)removeWarehouse:(nullable id)sender;
- (IBAction)addLocation:(nullable id)sender;
- (IBAction)removeLocation:(nullable id)sender;
- (IBAction)addCategory:(nullable id)sender;
- (IBAction)removeCategory:(nullable id)sender;
- (IBAction)addContact:(nullable id)sender;
- (IBAction)removeContact:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
