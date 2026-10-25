// Stock on the phone (docs/STOCK.md): what its tabs show of the catalog
// chosen, read from the device's store, and what they do to it. What
// stock is done to is the shared procedures' (Shared/LBStockProcedures.h),
// run here as the server runs them, saved here (LBLocalStore: derivations
// and rules, as the server's), and synced. The catalog's setup, recipes,
// supplier items and codes are the desktop's.

#pragma once
#import <Foundation/Foundation.h>
#import "LBLocalStore.h"
#import "LBStockProcedures.h"
#import "LBStockDisplay.h"

NS_ASSUME_NONNULL_BEGIN

// Defaults: the catalog chosen (its id).
FOUNDATION_EXPORT NSString * const LBCatalogDefaultsKey;     // @"LBCatalog"

@interface LBStockPhone : NSObject
- (instancetype)initWithStore:(LBLocalStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly) LBLocalStore *store;

// The catalogs the user sees, by name; the one chosen (kept across
// launches), the first when none is.
- (NSArray<Catalog *> *)catalogs;
@property (nonatomic, strong, nullable) Catalog *catalog;

// The chosen catalog's: items by name, those whose name, SKU or
// description has the text (all, for none); its locations, warehouses;
// its sales and purchases, the latest first.
- (NSArray<StockItem *> *)itemsMatching:(nullable NSString *)text;
- (NSArray<Location *> *)locations;
- (NSArray<Warehouse *> *)warehouses;
- (NSArray<SaleOrder *> *)saleOrders;
- (NSArray<PurchaseOrder *> *)purchaseOrders;
// What a count may be of.
- (NSArray<LBCountPlace *> *)countPlaces;
// An item's holdings (by location), its moves (newest first).
- (NSArray<Holding *> *)holdingsOf:(StockItem *)item;
- (NSArray<Move *> *)movesOf:(StockItem *)item;
// The overview: the figures, the rules due, the orders open.
- (LBStockFigures *)figures;
- (NSArray<ReorderRule *> *)rulesDue;
- (NSArray<NSManagedObject *> *)ordersOpen;

// A new item of the catalog: its SKU the next, named "New Item"; saved
// once its form is.
- (StockItem *)newItem;
// The changes saved (an amount typed with no currency given the
// catalog's). NO, and the rules' words: the changes kept to put right.
- (BOOL)saveProblems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
// Stock moved, by the user now, saved: adjusted at a location for the
// reason; moved from one location to another; an order's lines (by id,
// how many) shipped from, or received at, a location; a count of a place,
// of what was found. NO, and why: nothing changed.
- (BOOL)adjust:(StockItem *)item by:(NSDecimalNumber *)quantity at:(Location *)location reason:(NSString *)reason
      problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
- (BOOL)transfer:(StockItem *)item quantity:(NSDecimalNumber *)quantity from:(Location *)from to:(Location *)to
        problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
- (BOOL)ship:(SaleOrder *)order lines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)lines from:(Location *)location
    problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
- (BOOL)receive:(PurchaseOrder *)order lines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)lines at:(Location *)location
       problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
- (nullable StockCount *)count:(LBCountPlace *)place found:(NSArray<LBCounted *> *)found
                      problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
@end

NS_ASSUME_NONNULL_END
