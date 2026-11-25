// Stock on the phone (docs/STOCK.md), KiWi's tabs, which the app shows in
// place of the logbook's (the Vehicle tab's Stock row; Settings' Logbook
// row back): what is done in a stockroom with a phone in hand. UIKit,
// programmatic controllers over LBStockPhone, as the logbook's are over
// LBPhone:
//
//   LBStockTabBarController     Items, Orders, Overview, Settings
//   LBStockItemsViewController  the catalog's items, searched; + a new one
//   LBStockItemViewController   an item: its details (edited), quantities,
//                               holdings and moves; adjusted, transferred;
//                               a holding opens its moves, a move its
//                               order (a receipt's, a shipment's) or itself
//   LBStockHoldingViewController  an item's holding: the moves there
//   LBStockMoveDetailViewController  a move: what, when, how many, from,
//                               to, whose, the unit, its note; its order
//   LBStockMoveViewController   how many, where (and where to), why
//   LBStockOrdersViewController sales or purchases
//   LBStockOrderViewController  an order: its lines shipped (received),
//                               one or all, from (at) a location
//   LBStockOverviewViewController  the figures, the rules due, the orders
//                               open; a count begun
//   LBStockCountViewController  a count: of a place, what was found, posted
//   LBStockSettingsViewController  the catalog chosen, sync, the logbook

#pragma once
#import <UIKit/UIKit.h>
#import "LBStockPhone.h"

NS_ASSUME_NONNULL_BEGIN

@class LBStockItemViewController, LBStockOrderViewController, LBStockCountViewController, Move, Holding;

// What a move opens: its order (a receipt's purchase, a shipment's sale),
// else the move itself.
UIViewController *LBStockScreenOfMove(Move *move, LBStockPhone *phone);

@interface LBStockTabBarController : UITabBarController
- (instancetype)initWithStockPhone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@property (nonatomic, readonly) LBStockPhone *phone;
// Its tabs' controllers (the navigation controllers' first).
- (__kindof UIViewController *)tabNamed:(NSString *)title;
@end

@interface LBStockItemsViewController : UITableViewController <UISearchBarDelegate>
- (instancetype)initWithStockPhone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
// What the search says; the items shown: "PH-00001 Bolt: 20".
@property (nonatomic, copy) NSString *searchText;
- (NSArray<StockItem *> *)shownItems;
- (NSArray<NSString *> *)shownRows;
// A new item's screen, shown; an item's.
- (LBStockItemViewController *)addItem;
- (LBStockItemViewController *)openItem:(StockItem *)item;
@end

@interface LBStockItemViewController : UITableViewController <UITextFieldDelegate>
- (instancetype)initWithItem:(StockItem *)item phone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
// A row of Held at, or of Moves, tapped: what it opens, pushed.
- (UIViewController *)openHoldingAt:(NSUInteger)row;
- (UIViewController *)openMoveAt:(NSUInteger)row;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
@property (nonatomic, readonly) StockItem *item;
// Its details' fields, by their titles ("Name", "SKU", "Price"...); what
// a user types into one, into the item as typed.
- (NSArray<NSString *> *)fieldTitles;
- (BOOL)enter:(nullable NSString *)text intoField:(NSString *)title;
// Saved; NO and the rules' words.
- (BOOL)saveProblems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
// What it shows: "On hand: 20"; "Main / Default: 15"; "Transfer: 5".
- (NSArray<NSString *> *)quantityRows;
- (NSArray<NSString *> *)holdingRows;
- (NSArray<NSString *> *)moveRows;
// Its stock moved, the quantity as typed: adjusted at a location, for the
// reason; transferred.
- (BOOL)adjust:(NSString *)quantity at:(Location *)location reason:(NSString *)reason problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
- (BOOL)transfer:(NSString *)quantity from:(Location *)from to:(Location *)to problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
- (IBAction)save:(nullable id)sender;
@end

// What moving an item's stock is about to do: how many, where (from),
// where to (a transfer), why (an adjustment). Done moves it.
// An item's holding: where, how many, and the moves in and out of there,
// each opening its order or itself.
@interface LBStockHoldingViewController : UITableViewController
- (instancetype)initWithHolding:(Holding *)holding phone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
@property (nonatomic, readonly) Holding *holding;
// Into or out of its place, the latest first.
@property (nonatomic, readonly, copy) NSArray<Move *> *moves;
@end

// A move, as it was made: none of it is changed here (a move is made by
// what makes it: an adjustment, a transfer, an order's line, a count).
@interface LBStockMoveDetailViewController : UITableViewController
- (instancetype)initWithMove:(Move *)move phone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
@property (nonatomic, readonly) Move *move;
// "What: Transfer", "When: …", "Moved: 1", "From: …", "To: …", …
- (NSArray<NSString *> *)detailRows;
// Its order, where it has one (a line's, a receipt's, a shipment's).
@property (nonatomic, readonly, nullable) NSManagedObject *order;
@end

@interface LBStockMoveViewController : UITableViewController <UITextFieldDelegate>
- (instancetype)initWithItemController:(LBStockItemViewController *)item transfer:(BOOL)transfer NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
@end

@interface LBStockOrdersViewController : UITableViewController
- (instancetype)initWithStockPhone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
// Sales shown (else purchases), as the segments say.
@property (nonatomic) BOOL showsSales;
// "SO-PH-0001 Bob's Garage: Confirmed, Partly"
- (NSArray<NSString *> *)shownRows;
- (LBStockOrderViewController *)openOrder:(NSManagedObject *)order;
@end

@interface LBStockOrderViewController : UITableViewController
- (instancetype)initWithOrder:(NSManagedObject *)order phone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
@property (nonatomic, readonly) NSManagedObject *order;
// Where its lines are shipped from (received at): the first location,
// until chosen.
@property (nonatomic, strong, nullable) Location *moveAt;
// "Bolt: 3, shipped 2"
- (NSArray<NSString *> *)lineRows;
- (NSArray *)lines;
// A line's so many (as typed), every line's outstanding (shipping: as
// much as moveAt holds of each), shipped or received.
- (BOOL)moveLine:(NSManagedObject *)line quantity:(NSString *)quantity problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
- (BOOL)moveAllProblems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
@end

@interface LBStockOverviewViewController : UITableViewController
- (instancetype)initWithStockPhone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
// "Items: 1", "On hand: 16"...; "Bolt at Garage"; "SO-PH-0001".
- (NSArray<NSString *> *)figureRows;
- (NSArray<NSString *> *)dueRows;
- (NSArray<NSString *> *)openRows;
// A count's screen, shown.
- (LBStockCountViewController *)beginCount;
@end

// A row of a count being taken: an item at a location, what is held there,
// what was found (typed; nil, nothing yet).
@interface LBPhoneCountRow : NSObject
@property (nonatomic, strong) StockItem *item;
@property (nonatomic, strong) Location *location;
@property (nonatomic, strong) NSDecimalNumber *expected;
@property (nonatomic, copy, nullable) NSString *found;
@end

@interface LBStockCountViewController : UITableViewController <UITextFieldDelegate>
- (instancetype)initWithStockPhone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
// What it counts: chosen, a row for each holding there, nothing found yet.
@property (nonatomic, strong, nullable) LBCountPlace *countPlace;
// Whether what is held is shown (off: counted blind).
@property (nonatomic) BOOL showsExpected;
@property (nonatomic, readonly, copy) NSArray<LBPhoneCountRow *> *rows;
// An item found that was not expected, at one of its locations.
- (LBPhoneCountRow *)addRowOf:(StockItem *)item at:(Location *)location;
// Posted: the count made, saved; nil and why (a row with nothing typed).
- (nullable StockCount *)postProblems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
@end

@interface LBStockSettingsViewController : UITableViewController
- (instancetype)initWithStockPhone:(LBStockPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (NSArray<NSString *> *)shownSections;
@end

NS_ASSUME_NONNULL_END
