#import "LBStockControllers.h"
#import "LBDisplay.h"

static void LBStockTell(UIViewController *controller, NSString *title, NSArray<NSString *> *lines) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:[lines componentsJoinedByString:@"\n\n"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

/* A cell of a title and, at its right, a detail. */
static UITableViewCell *LBValueCell(NSString *title, NSString *detail) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = detail;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

/* A row that does something when tapped, in the tint. */
static UITableViewCell *LBActionCell(UIViewController *controller, NSString *title) {
    UITableViewCell *cell = LBValueCell(title, @"");
    cell.textLabel.textColor = controller.view.tintColor;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

/* A quantity as typed: a decimal number; nil for anything else. */
static NSDecimalNumber *LBTyped(NSString *text) {
    NSDecimalNumber *number = text.length ? [NSDecimalNumber decimalNumberWithString:text locale:[NSLocale currentLocale]] : nil;
    return number == [NSDecimalNumber notANumber] ? nil : number;
}

static NSString *LBNumber(NSDecimalNumber *number) {
    return number ? number.stringValue : @"0";
}

/* Each object's title offered in a sheet over the cell; the one chosen
   given to the target's action (with the object). */
static void LBOffer(UIViewController *over, UITableViewCell *cell, NSString *title, NSArray *objects, id target, SEL action) {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (id object in objects) {
        NSString *name = [object respondsToSelector:@selector(lbTitle)] ? [object lbTitle] : [object description];
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *chosen) {
            ((void (*)(id, SEL, id))[target methodForSelector:action])(target, action, object);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell ?: over.view;
    sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : over.view.bounds;
    [over presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - The tabs

@implementation LBStockTabBarController

- (instancetype)initWithStockPhone:(LBStockPhone *)phone {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _phone = phone;
        NSArray *tabs = @[ @[ [[LBStockItemsViewController alloc] initWithStockPhone:phone], @"Items", @"shippingbox" ],
                           @[ [[LBStockOrdersViewController alloc] initWithStockPhone:phone], @"Orders", @"doc.text" ],
                           @[ [[LBStockOverviewViewController alloc] initWithStockPhone:phone], @"Overview", @"chart.bar" ],
                           @[ [[LBStockSettingsViewController alloc] initWithStockPhone:phone], @"Settings", @"gearshape" ] ];
        NSMutableArray *controllers = [NSMutableArray array];
        for (NSUInteger i = 0; i < tabs.count; i++) {
            UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:tabs[i][0]];
            navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:tabs[i][1] image:[UIImage systemImageNamed:tabs[i][2]] tag:(NSInteger)i];
            [controllers addObject:navigation];
        }
        self.viewControllers = controllers;
    }
    return self;
}

- (UIViewController *)tabNamed:(NSString *)title {
    for (UINavigationController *navigation in self.viewControllers) {
        if ([navigation.tabBarItem.title isEqualToString:title]) return navigation.viewControllers.firstObject;
    }
    return nil;
}

@end

#pragma mark - Items

@interface LBStockItemsViewController ()
@property (nonatomic, readonly) LBStockPhone *phone;
@end

@implementation LBStockItemsViewController {
    NSArray<StockItem *> *_items;
}

- (instancetype)initWithStockPhone:(LBStockPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _phone = phone;
        _searchText = @"";
        self.title = @"Items";
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self
                                                                                               action:@selector(add:)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:LBLocalStoreDidChangeNotification
                                                   object:phone.store];
        [self reload];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 56)];
    search.placeholder = @"Name, SKU or description";
    search.delegate = self;
    self.tableView.tableHeaderView = search;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    _items = [_phone itemsMatching:_searchText];
    self.navigationItem.title = _phone.catalog.lbTitle ?: @"Items";
    self.navigationItem.prompt = _phone.store.status;
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (void)setSearchText:(NSString *)text {
    _searchText = [text copy] ?: @"";
    [self reload];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    self.searchText = text;
}

- (NSArray<StockItem *> *)shownItems {
    return _items;
}

- (NSArray<NSString *> *)shownRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (StockItem *item in _items) [rows addObject:[NSString stringWithFormat:@"%@ %@: %@", item.sku ?: @"", item.lbTitle, LBNumber(item.totalQuantity)]];
    return rows;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    StockItem *item = _items[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = item.lbTitle;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ on hand", item.sku ?: @"", LBNumber(item.totalQuantity)];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openItem:_items[(NSUInteger)indexPath.row]];
}

- (void)add:(id)sender {
    [self addItem];
}

- (LBStockItemViewController *)addItem {
    if (!_phone.catalog) {
        LBStockTell(self, @"No Catalog", @[ @"A catalog is set up on the desktop: it comes here as the phone syncs." ]);
        return nil;
    }
    return [self openItem:[_phone newItem]];
}

- (LBStockItemViewController *)openItem:(StockItem *)item {
    LBStockItemViewController *screen = [[LBStockItemViewController alloc] initWithItem:item phone:_phone];
    [self.navigationController pushViewController:screen animated:NO];
    return screen;
}

@end

#pragma mark - An item

typedef NS_ENUM(NSInteger, LBItemSection) {
    LBItemSectionDetails,
    LBItemSectionQuantities,
    LBItemSectionStock,
    LBItemSectionHoldings,
    LBItemSectionMoves,
};

@implementation LBStockItemViewController {
    LBStockPhone *_phone;
    NSArray<Holding *> *_holdings;
    NSArray<Move *> *_moves;
}

/* Its fields: title, key, whether a number. */
static NSArray<NSArray *> *LBItemFields(void) {
    return @[ @[ @"Name", @"itemName", @NO ], @[ @"SKU", @"sku", @NO ], @[ @"Description", @"descriptionValue", @NO ],
              @[ @"Price", @"priceAmount", @YES ], @[ @"Unit cost", @"unitCostAmount", @YES ], @[ @"Note", @"note", @NO ] ];
}

- (instancetype)initWithItem:(StockItem *)item phone:(LBStockPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _item = item;
        _phone = phone;
        self.title = item.lbTitle;
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self
                                                                                               action:@selector(save:)];
        if (item.isInserted) {
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self
                                                                                                  action:@selector(cancel:)];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:LBLocalStoreDidChangeNotification
                                                   object:phone.store];
        [self reload];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reload {
    if (_item.isDeleted || !_item.managedObjectContext) return;
    _holdings = _item.isInserted ? @[] : [_phone holdingsOf:_item];
    _moves = _item.isInserted ? @[] : [_phone movesOf:_item];
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (NSArray<NSString *> *)fieldTitles {
    return [LBItemFields() valueForKey:@"firstObject"];
}

- (BOOL)enter:(NSString *)text intoField:(NSString *)title {
    for (NSArray *field in LBItemFields()) {
        if (![field[0] isEqualToString:title]) continue;
        if ([field[2] boolValue]) {
            NSDecimalNumber *number = LBTyped(text);
            if (text.length && !number) return NO;
            [_item setValue:number forKey:field[1]];
        } else {
            [_item setValue:text.length ? text : nil forKey:field[1]];
        }
        return YES;
    }
    return NO;
}

- (BOOL)saveProblems:(NSArray<NSString *> **)problems {
    [self.view endEditing:YES];
    if (![_phone saveProblems:problems]) return NO;
    self.title = _item.lbTitle;
    self.navigationItem.leftBarButtonItem = nil;
    [self reload];
    return YES;
}

- (IBAction)save:(id)sender {
    NSArray *problems = nil;
    if (![self saveProblems:&problems]) LBStockTell(self, @"Not Saved", problems ?: @[]);
}

- (void)cancel:(id)sender {
    [_phone.store.context rollback];
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSArray<NSString *> *)quantityRows {
    return @[ [NSString stringWithFormat:@"On hand: %@", LBNumber(_item.totalQuantity)],
              [NSString stringWithFormat:@"Available: %@", LBNumber(_item.available)],
              [NSString stringWithFormat:@"Committed: %@", LBNumber(_item.committed)],
              [NSString stringWithFormat:@"Incoming: %@", LBNumber(_item.incoming)] ];
}

- (NSArray<NSString *> *)holdingRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (Holding *holding in _holdings) [rows addObject:[NSString stringWithFormat:@"%@: %@", holding.lbLocationTitle, LBNumber(holding.quantity)]];
    return rows;
}

- (NSArray<NSString *> *)moveRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (Move *move in _moves) [rows addObject:[NSString stringWithFormat:@"%@: %@", move.lbWhat, LBNumber(move.moved)]];
    return rows;
}

- (BOOL)adjust:(NSString *)quantity at:(Location *)location reason:(NSString *)reason problems:(NSArray<NSString *> **)problems {
    NSDecimalNumber *number = LBTyped(quantity);
    if (!number || !location) {
        if (problems) *problems = @[ number ? @"Choose where." : @"Say how many: a number." ];
        return NO;
    }
    if (![_phone adjust:_item by:number at:location reason:reason problems:problems]) return NO;
    [self reload];
    return YES;
}

- (BOOL)transfer:(NSString *)quantity from:(Location *)from to:(Location *)to problems:(NSArray<NSString *> **)problems {
    NSDecimalNumber *number = LBTyped(quantity);
    if (!number || !from || !to) {
        if (problems) *problems = @[ number ? @"Choose where from, and where to." : @"Say how many: a number." ];
        return NO;
    }
    if (![_phone transfer:_item quantity:number from:from to:to problems:problems]) return NO;
    [self reload];
    return YES;
}

#pragma mark Its table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _item.isInserted ? 1 : 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[ @"Item", @"Quantities", @"Stock", @"Held at", @"Moves" ][(NSUInteger)section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((LBItemSection)section) {
        case LBItemSectionDetails: return (NSInteger)LBItemFields().count;
        case LBItemSectionQuantities: return 4;
        case LBItemSectionStock: return 2;
        case LBItemSectionHoldings: return (NSInteger)_holdings.count;
        case LBItemSectionMoves: return (NSInteger)MIN(_moves.count, 20u);
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger row = (NSUInteger)indexPath.row;
    switch ((LBItemSection)indexPath.section) {
        case LBItemSectionDetails: {
            NSArray *field = LBItemFields()[row];
            UITableViewCell *cell = LBValueCell(field[0], @"");
            UITextField *text = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 30)];
            text.textAlignment = NSTextAlignmentRight;
            id value = [_item valueForKey:field[1]];
            text.text = [value isKindOfClass:[NSDecimalNumber class]] ? [value stringValue] : value;
            text.keyboardType = [field[2] boolValue] ? UIKeyboardTypeDecimalPad : UIKeyboardTypeDefault;
            text.tag = (NSInteger)row;
            text.delegate = self;
            [text addTarget:self action:@selector(typed:) forControlEvents:UIControlEventEditingChanged];
            cell.accessoryView = text;
            return cell;
        }
        case LBItemSectionQuantities: {
            NSArray *parts = [[self quantityRows][row] componentsSeparatedByString:@": "];
            return LBValueCell(parts[0], parts[1]);
        }
        case LBItemSectionStock:
            return LBActionCell(self, row == 0 ? @"Adjust…" : @"Transfer…");
        case LBItemSectionHoldings: {
            Holding *holding = _holdings[row];
            return LBValueCell(holding.lbLocationTitle, LBNumber(holding.quantity));
        }
        case LBItemSectionMoves: {
            Move *move = _moves[row];
            UITableViewCell *cell = LBValueCell(move.lbWhat, LBNumber(move.moved));
            cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
            return cell;
        }
    }
    return LBValueCell(@"", @"");
}

- (void)typed:(UITextField *)field {
    [self enter:field.text intoField:LBItemFields()[(NSUInteger)field.tag][0]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != LBItemSectionStock) return;
    LBStockMoveViewController *move = [[LBStockMoveViewController alloc] initWithItemController:self transfer:indexPath.row == 1];
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:move] animated:YES completion:nil];
}

- (LBStockPhone *)phone {
    return _phone;
}

@end

#pragma mark - Moving an item's stock

@implementation LBStockMoveViewController {
    __weak LBStockItemViewController *_item;
    BOOL _transfer;
    NSString *_quantity;
    Location *_at, *_to;
    NSString *_reason;
    NSArray<Location *> *_locations;
}

- (instancetype)initWithItemController:(LBStockItemViewController *)item transfer:(BOOL)transfer {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _item = item;
        _transfer = transfer;
        _reason = @"Found";
        _locations = [(LBStockPhone *)[item valueForKey:@"phone"] locations];
        _at = _locations.firstObject;
        _to = _locations.count > 1 ? _locations[1] : nil;
        self.title = transfer ? @"Transfer" : @"Adjust";
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self
                                                                                              action:@selector(cancel:)];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self
                                                                                               action:@selector(done:)];
    }
    return self;
}

- (NSArray<NSString *> *)rowTitles {
    return _transfer ? @[ @"Quantity", @"From", @"To" ] : @[ @"Quantity (less than none: out)", @"At", @"Reason" ];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *title = [self rowTitles][(NSUInteger)indexPath.row];
    if (indexPath.row == 0) {
        UITableViewCell *cell = LBValueCell(title, @"");
        UITextField *text = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 120, 30)];
        text.textAlignment = NSTextAlignmentRight;
        text.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        text.text = _quantity;
        text.delegate = self;
        [text addTarget:self action:@selector(typed:) forControlEvents:UIControlEventEditingChanged];
        cell.accessoryView = text;
        return cell;
    }
    NSString *detail = indexPath.row == 1 ? _at.lbTitle : _transfer ? _to.lbTitle : _reason;
    UITableViewCell *cell = LBValueCell(title, detail ?: @"Choose");
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)typed:(UITextField *)field {
    _quantity = field.text;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (indexPath.row == 1) LBOffer(self, cell, _transfer ? @"From" : @"At", _locations, self, @selector(chooseAt:));
    else if (indexPath.row == 2 && _transfer) LBOffer(self, cell, @"To", _locations, self, @selector(chooseTo:));
    else if (indexPath.row == 2) LBOffer(self, cell, @"Why", @[ @"Opening", @"Found", @"Damaged", @"Lost", @"Expired", @"Other" ], self,
                                         @selector(chooseReason:));
}

- (void)chooseAt:(Location *)location {
    _at = location;
    [self.tableView reloadData];
}

- (void)chooseTo:(Location *)location {
    _to = location;
    [self.tableView reloadData];
}

- (void)chooseReason:(NSString *)reason {
    _reason = reason;
    [self.tableView reloadData];
}

- (void)cancel:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)done:(id)sender {
    [self.view endEditing:YES];
    NSArray *problems = nil;
    BOOL moved = _transfer ? [_item transfer:_quantity from:_at to:_to problems:&problems]
                           : [_item adjust:_quantity at:_at reason:_reason problems:&problems];
    if (moved) [self dismissViewControllerAnimated:YES completion:nil];
    else LBStockTell(self, @"Not Moved", problems ?: @[]);
}

@end

#pragma mark - Orders

@implementation LBStockOrdersViewController {
    LBStockPhone *_phone;
    NSArray *_orders;
}

- (instancetype)initWithStockPhone:(LBStockPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _phone = phone;
        _showsSales = YES;
        self.title = @"Orders";
        UISegmentedControl *kinds = [[UISegmentedControl alloc] initWithItems:@[ @"Sales", @"Purchases" ]];
        kinds.selectedSegmentIndex = 0;
        [kinds addTarget:self action:@selector(kindChosen:) forControlEvents:UIControlEventValueChanged];
        self.navigationItem.titleView = kinds;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:LBLocalStoreDidChangeNotification
                                                   object:phone.store];
        [self reload];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)kindChosen:(UISegmentedControl *)kinds {
    self.showsSales = kinds.selectedSegmentIndex == 0;
}

- (void)setShowsSales:(BOOL)sales {
    _showsSales = sales;
    ((UISegmentedControl *)self.navigationItem.titleView).selectedSegmentIndex = sales ? 0 : 1;
    [self reload];
}

- (void)reload {
    _orders = _showsSales ? (NSArray *)[_phone saleOrders] : (NSArray *)[_phone purchaseOrders];
    self.navigationItem.prompt = _phone.store.status;
    if (self.isViewLoaded) [self.tableView reloadData];
}

static NSString *LBPartyOf(NSManagedObject *order) {
    return [order respondsToSelector:@selector(lbParty)] ? [(id)order lbParty] : @"";
}

- (NSArray<NSString *> *)shownRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (id order in _orders) {
        NSString *filled = [order lbFilled];
        [rows addObject:[NSString stringWithFormat:@"%@ %@: %@%@", [order lb_number], LBPartyOf(order), [order orderState] ?: @"",
                                                   filled.length ? [@", " stringByAppendingString:filled] : @""]];
    }
    return rows;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_orders.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id order = _orders[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@", [order lb_number], LBPartyOf(order)];
    NSString *filled = [order lbFilled];
    cell.detailTextLabel.text = filled.length ? [NSString stringWithFormat:@"%@, %@", [order orderState], filled] : [order orderState];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openOrder:_orders[(NSUInteger)indexPath.row]];
}

- (LBStockOrderViewController *)openOrder:(NSManagedObject *)order {
    LBStockOrderViewController *screen = [[LBStockOrderViewController alloc] initWithOrder:order phone:_phone];
    [self.navigationController pushViewController:screen animated:NO];
    return screen;
}

@end

#pragma mark - An order

@implementation LBStockOrderViewController {
    LBStockPhone *_phone;
    BOOL _sale;
    NSArray *_lines;
    NSArray *_documents;
}

- (instancetype)initWithOrder:(NSManagedObject *)order phone:(LBStockPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _order = order;
        _phone = phone;
        _sale = [order isKindOfClass:[SaleOrder class]];
        _moveAt = [phone locations].firstObject;
        self.title = [(id)order lb_number];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:LBLocalStoreDidChangeNotification
                                                   object:phone.store];
        [self reload];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reload {
    NSSortDescriptor *inOrder = [NSSortDescriptor sortDescriptorWithKey:@"lbLineOrder" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    NSSet *lines = [_order valueForKey:_sale ? @"saleLines" : @"purchaseLines"];
    _lines = [[lines.allObjects filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDeleted == NO"]] sortedArrayUsingDescriptors:@[ inOrder ]];
    NSSet *documents = [_order valueForKey:_sale ? @"shipments" : @"receipts"];
    _documents = [documents.allObjects sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"runningNumber" ascending:NO] ]];
    self.navigationItem.prompt = _phone.store.status;
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (NSArray *)lines {
    return _lines;
}

- (NSString *)rowOf:(id)line {
    NSDecimalNumber *done = [line valueForKey:_sale ? @"shippedQuantity" : @"receivedQuantity"];
    return [NSString stringWithFormat:@"%@: %@, %@ %@", [line stockItem].lbTitle, LBNumber([line quantity]), _sale ? @"shipped" : @"received",
                                      LBNumber(done)];
}

- (NSArray<NSString *> *)lineRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (id line in _lines) [rows addObject:[self rowOf:line]];
    return rows;
}

- (BOOL)move:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities problems:(NSArray<NSString *> **)problems {
    if (!_moveAt) {
        if (problems) *problems = @[ @"Choose where." ];
        return NO;
    }
    BOOL moved = _sale ? [_phone ship:(SaleOrder *)_order lines:quantities from:_moveAt problems:problems]
                       : [_phone receive:(PurchaseOrder *)_order lines:quantities at:_moveAt problems:problems];
    [self reload];
    return moved;
}

- (BOOL)moveLine:(NSManagedObject *)line quantity:(NSString *)quantity problems:(NSArray<NSString *> **)problems {
    NSDecimalNumber *number = LBTyped(quantity);
    if (!number) {
        if (problems) *problems = @[ @"Say how many: a number." ];
        return NO;
    }
    return [self move:@{ [line valueForKey:@"id"]: number } problems:problems];
}

- (BOOL)moveAllProblems:(NSArray<NSString *> **)problems {
    NSMutableDictionary *quantities = [NSMutableDictionary dictionary];
    for (id line in _lines) {
        NSDecimalNumber *left = [line valueForKey:_sale ? @"backorderedQuantity" : @"outstandingQuantity"];
        if (!left || [left compare:[NSDecimalNumber zero]] != NSOrderedDescending) continue;
        if (_sale) {
            if ([line stockItem].isAPhantomKit) continue;
            NSDecimalNumber *held = [_moveAt lb_heldOf:[line stockItem]];
            if ([held compare:left] == NSOrderedAscending) left = held;
            if ([left compare:[NSDecimalNumber zero]] != NSOrderedDescending) continue;
        }
        quantities[[line valueForKey:@"id"]] = left;
    }
    if (!quantities.count) {
        if (problems) *problems = @[ _sale ? @"Nothing outstanding is held there." : @"Nothing is outstanding." ];
        return NO;
    }
    return [self move:quantities problems:problems];
}

#pragma mark Its table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[ @"Order", @"Lines", _sale ? @"Ship" : @"Receive", _sale ? @"Shipments" : @"Receipts" ][(NSUInteger)section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 1 ? (_sale ? @"Tap a line to ship some of it." : @"Tap a line to receive some of it.") : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [@[ @4, @(_lines.count), @2, @(_documents.count) ][(NSUInteger)section] integerValue];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger row = (NSUInteger)indexPath.row;
    id order = _order;
    switch (indexPath.section) {
        case 0: {
            NSArray *rows = @[ @[ @"Number", [order lb_number] ], @[ _sale ? @"Customer" : @"Supplier", LBPartyOf(order) ],
                               @[ @"State", [order orderState] ?: @"" ], @[ @"Filled", [order lbFilled] ?: @"" ] ];
            return LBValueCell(rows[row][0], rows[row][1]);
        }
        case 1: {
            id line = _lines[row];
            NSDecimalNumber *done = [line valueForKey:_sale ? @"shippedQuantity" : @"receivedQuantity"];
            UITableViewCell *cell = LBValueCell([line stockItem].lbTitle,
                                                [NSString stringWithFormat:@"%@ of %@", LBNumber(done), LBNumber([line quantity])]);
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }
        case 2: {
            if (row == 0) {
                UITableViewCell *cell = LBValueCell(_sale ? @"From" : @"At", _moveAt.lbTitle ?: @"Choose");
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
            return LBActionCell(self, _sale ? @"Ship All Outstanding" : @"Receive All Outstanding");
        }
        default: {
            id document = _documents[row];
            NSDate *day = [document valueForKey:_sale ? @"shipped" : @"received"];
            return LBValueCell([NSString stringWithFormat:@"%d", [[document valueForKey:@"runningNumber"] intValue]],
                               [NSDateFormatter localizedStringFromDate:day dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterNoStyle]);
        }
    }
}

- (void)chooseAt:(Location *)location {
    _moveAt = location;
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSArray *problems = nil;
    if (indexPath.section == 2 && indexPath.row == 0) {
        LBOffer(self, cell, _sale ? @"Ship from" : @"Receive at", [_phone locations], self, @selector(chooseAt:));
    } else if (indexPath.section == 2) {
        if (![self moveAllProblems:&problems]) LBStockTell(self, _sale ? @"Not Shipped" : @"Not Received", problems ?: @[]);
    } else if (indexPath.section == 1) {
        id line = _lines[(NSUInteger)indexPath.row];
        UIAlertController *ask = [UIAlertController alertControllerWithTitle:[line stockItem].lbTitle message:@"How many?"
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [ask addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.keyboardType = UIKeyboardTypeDecimalPad;
        }];
        __weak LBStockOrderViewController *weakSelf = self;
        __weak UIAlertController *weakAsk = ask;
        [ask addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [ask addAction:[UIAlertAction actionWithTitle:_sale ? @"Ship" : @"Receive" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSArray *refused = nil;
            if (![weakSelf moveLine:line quantity:weakAsk.textFields.firstObject.text problems:&refused]) {
                LBStockTell(weakSelf, @"Not Done", refused ?: @[]);
            }
        }]];
        [self presentViewController:ask animated:YES completion:nil];
    }
}

@end

#pragma mark - The overview

@implementation LBStockOverviewViewController {
    LBStockPhone *_phone;
    NSArray<NSArray<NSString *> *> *_figures;
    NSArray<ReorderRule *> *_due;
    NSArray<NSManagedObject *> *_open;
}

- (instancetype)initWithStockPhone:(LBStockPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _phone = phone;
        self.title = @"Overview";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:LBLocalStoreDidChangeNotification
                                                   object:phone.store];
        [self reload];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    LBStockFigures *figures = [_phone figures];
    _figures = @[ @[ @"Items", [NSString stringWithFormat:@"%lu", (unsigned long)[_phone itemsMatching:nil].count] ],
                  @[ @"On hand", LBNumber(figures.quantity) ], @[ @"Value at price", figures.valueAtPrice ],
                  @[ @"Value at cost", figures.valueAtCost ], @[ @"Weight", figures.totals.weightText ],
                  @[ @"Volume", figures.totals.volumeText ] ];
    _due = [_phone rulesDue];
    _open = [_phone ordersOpen];
    self.navigationItem.prompt = _phone.store.status;
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (NSArray<NSString *> *)figureRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSArray *figure in _figures) [rows addObject:[NSString stringWithFormat:@"%@: %@", figure[0], figure[1]]];
    return rows;
}

- (NSArray<NSString *> *)dueRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (ReorderRule *rule in _due) [rows addObject:[NSString stringWithFormat:@"%@ at %@", rule.stockItem.lbTitle, rule.warehouse.lbTitle]];
    return rows;
}

- (NSArray<NSString *> *)openRows {
    return [_open valueForKey:@"lb_number"];
}

- (LBStockCountViewController *)beginCount {
    LBStockCountViewController *count = [[LBStockCountViewController alloc] initWithStockPhone:_phone];
    [self.navigationController pushViewController:count animated:NO];
    return count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[ @"At a Glance", @"Due for Reorder", @"Open Orders", @"Count" ][(NSUInteger)section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [@[ @(_figures.count), @(_due.count), @(_open.count), @1 ][(NSUInteger)section] integerValue];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger row = (NSUInteger)indexPath.row;
    switch (indexPath.section) {
        case 0: return LBValueCell(_figures[row][0], _figures[row][1]);
        case 1: {
            ReorderRule *rule = _due[row];
            return LBValueCell(rule.stockItem.lbTitle, [NSString stringWithFormat:@"%@ available at %@", LBNumber(rule.stockItem.available),
                                                                                   rule.warehouse.lbTitle]);
        }
        case 2: {
            id order = _open[row];
            UITableViewCell *cell = LBValueCell([order lb_number], LBPartyOf(order));
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        default: return LBActionCell(self, @"Count Stock…");
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) {
        LBStockOrderViewController *order = [[LBStockOrderViewController alloc] initWithOrder:_open[(NSUInteger)indexPath.row] phone:_phone];
        [self.navigationController pushViewController:order animated:YES];
    } else if (indexPath.section == 3) {
        [self beginCount];
    }
}

@end

#pragma mark - A count

@implementation LBPhoneCountRow
@end

@implementation LBStockCountViewController {
    LBStockPhone *_phone;
    /* An item found, chosen, its location to be. */
    StockItem *_pendingItem;
}

- (instancetype)initWithStockPhone:(LBStockPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _phone = phone;
        _rows = @[];
        self.title = @"Count";
        self.countPlace = [phone countPlaces].firstObject;
    }
    return self;
}

- (void)setCountPlace:(LBCountPlace *)place {
    _countPlace = place;
    NSMutableArray *rows = [NSMutableArray array];
    for (Location *location in place.locations) {
        for (Holding *holding in location.holdings) {
            if (holding.isDeleted || !holding.stockItem) continue;
            LBPhoneCountRow *row = [[LBPhoneCountRow alloc] init];
            row.item = holding.stockItem;
            row.location = location;
            row.expected = holding.quantity ?: [NSDecimalNumber zero];
            [rows addObject:row];
        }
    }
    [rows sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"item.itemName" ascending:YES],
                                  [NSSortDescriptor sortDescriptorWithKey:@"location.lbTitle" ascending:YES] ]];
    _rows = rows;
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (void)setShowsExpected:(BOOL)shows {
    _showsExpected = shows;
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (LBPhoneCountRow *)addRowOf:(StockItem *)item at:(Location *)location {
    LBPhoneCountRow *row = [[LBPhoneCountRow alloc] init];
    row.item = item;
    row.location = location;
    row.expected = [location lb_heldOf:item];
    _rows = [_rows arrayByAddingObject:row];
    if (self.isViewLoaded) [self.tableView reloadData];
    return row;
}

- (StockCount *)postProblems:(NSArray<NSString *> **)problems {
    [self.view endEditing:YES];
    NSMutableArray *found = [NSMutableArray array];
    for (LBPhoneCountRow *row in _rows) {
        NSDecimalNumber *number = LBTyped(row.found);
        if (!number) {
            if (problems) *problems = @[ @"Type what was found of each (0 for none)." ];
            return nil;
        }
        [found addObject:[LBCounted countedItem:row.item at:row.location quantity:number]];
    }
    if (!_countPlace) {
        if (problems) *problems = @[ @"Choose what to count." ];
        return nil;
    }
    StockCount *count = [_phone count:_countPlace found:found problems:problems];
    if (count) self.countPlace = _countPlace;
    return count;
}

#pragma mark Its table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[ @"Of", @"Found", @"" ][(NSUInteger)section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [@[ @2, @(_rows.count + 1), @1 ][(NSUInteger)section] integerValue];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger row = (NSUInteger)indexPath.row;
    if (indexPath.section == 0 && row == 0) {
        UITableViewCell *cell = LBValueCell(@"Place", _countPlace.lbTitle ?: @"Choose");
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (indexPath.section == 0) {
        UITableViewCell *cell = LBValueCell(@"Show what is held", @"");
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = _showsExpected;
        [toggle addTarget:self action:@selector(expectedSwitched:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }
    if (indexPath.section == 2) return LBActionCell(self, @"Post Count");
    if (row == _rows.count) return LBActionCell(self, @"Add an Item Found…");
    LBPhoneCountRow *counted = _rows[row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = counted.item.lbTitle;
    cell.detailTextLabel.text = _showsExpected ? [NSString stringWithFormat:@"%@ · %@ held", counted.location.lbTitle, LBNumber(counted.expected)]
                                               : counted.location.lbTitle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UITextField *text = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 80, 30)];
    text.textAlignment = NSTextAlignmentRight;
    text.keyboardType = UIKeyboardTypeDecimalPad;
    text.placeholder = @"found";
    text.text = counted.found;
    text.tag = (NSInteger)row;
    text.delegate = self;
    [text addTarget:self action:@selector(typed:) forControlEvents:UIControlEventEditingChanged];
    cell.accessoryView = text;
    return cell;
}

- (void)typed:(UITextField *)field {
    if ((NSUInteger)field.tag < _rows.count) _rows[(NSUInteger)field.tag].found = field.text;
}

- (void)expectedSwitched:(UISwitch *)toggle {
    self.showsExpected = toggle.isOn;
}

- (void)choosePlace:(LBCountPlace *)place {
    self.countPlace = place;
}

/* An item found, then where. */
- (void)chooseFoundItem:(StockItem *)item {
    _pendingItem = item;
    LBOffer(self, nil, @"Where", _countPlace.locations, self, @selector(chooseFoundAt:));
}

- (void)chooseFoundAt:(Location *)location {
    if (_pendingItem) [self addRowOf:_pendingItem at:location];
    _pendingItem = nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (indexPath.section == 0 && indexPath.row == 0) {
        LBOffer(self, cell, @"Count", [_phone countPlaces], self, @selector(choosePlace:));
    } else if (indexPath.section == 1 && (NSUInteger)indexPath.row == _rows.count) {
        LBOffer(self, cell, @"Found", [_phone itemsMatching:nil], self, @selector(chooseFoundItem:));
    } else if (indexPath.section == 2) {
        NSArray *problems = nil;
        StockCount *count = [self postProblems:&problems];
        if (count) LBStockTell(self, @"Counted", @[ [NSString stringWithFormat:@"%@: %lu adjusted.", count.lbNumber, (unsigned long)count.moves.count] ]);
        else LBStockTell(self, @"Not Counted", problems ?: @[]);
    }
}

@end

#pragma mark - Settings

typedef NS_ENUM(NSInteger, LBStockSettingsSection) {
    LBStockSettingsCatalog,
    LBStockSettingsSync,
    LBStockSettingsLogbook,
};

@implementation LBStockSettingsViewController {
    LBStockPhone *_phone;
    NSArray<Catalog *> *_catalogs;
}

- (instancetype)initWithStockPhone:(LBStockPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _phone = phone;
        self.title = @"Settings";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:LBLocalStoreDidChangeNotification
                                                   object:phone.store];
        [self reload];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    _catalogs = [_phone catalogs];
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (NSArray<NSString *> *)shownSections {
    return @[ @"Catalog", @"Sync", @"Logbook" ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self shownSections][(NSUInteger)section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == LBStockSettingsCatalog ? @"Catalogs are set up on the desktop: their warehouses, contacts, recipes and suppliers." : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((LBStockSettingsSection)section) {
        case LBStockSettingsCatalog: return (NSInteger)MAX(_catalogs.count, 1u);
        case LBStockSettingsSync: return 2;
        case LBStockSettingsLogbook: return 1;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ((LBStockSettingsSection)indexPath.section) {
        case LBStockSettingsCatalog: {
            if (!_catalogs.count) return LBValueCell(@"No catalog yet", @"");
            Catalog *catalog = _catalogs[(NSUInteger)indexPath.row];
            UITableViewCell *cell = LBValueCell(catalog.lbTitle, @"");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = catalog == _phone.catalog ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            return cell;
        }
        case LBStockSettingsSync:
            if (indexPath.row == 0) {
                UITableViewCell *cell = LBValueCell(_phone.store.status, @"");
                cell.textLabel.textColor = [UIColor secondaryLabelColor];
                return cell;
            }
            return LBActionCell(self, @"Sync Now");
        case LBStockSettingsLogbook:
            return LBActionCell(self, @"Back to the Logbook");
    }
    return LBValueCell(@"", @"");
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch ((LBStockSettingsSection)indexPath.section) {
        case LBStockSettingsCatalog:
            if (_catalogs.count) _phone.catalog = _catalogs[(NSUInteger)indexPath.row];
            [[NSNotificationCenter defaultCenter] postNotificationName:LBLocalStoreDidChangeNotification object:_phone.store];
            break;
        case LBStockSettingsSync:
            if (indexPath.row == 1) [_phone.store syncNow];
            break;
        case LBStockSettingsLogbook:
            [[UIApplication sharedApplication] sendAction:@selector(showLogbook:) to:nil from:self forEvent:nil];
            break;
    }
}

@end
