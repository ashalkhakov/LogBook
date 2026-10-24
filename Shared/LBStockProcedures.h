// What the app does with stock (docs/STOCK.md): the procedures, not
// derivations. Each changes objects of the model in their context, and
// nothing else: no save, no request. The model's rules, checked at save by
// the generated code, say whether what a procedure leaves may be kept;
// where one would plainly be broken (more out than is held, an order not
// confirmed), the procedure refuses first, saying why in the user's terms,
// and changes nothing. Foundation and Core Data only: the server runs them
// as its actions, the iOS app in its own store.
//
// Deterministic, as LBProcedures.h is: what a procedure makes of what is
// there is named by it (a name-based UUID, LBNamedUUID):
//
//   a holding                       "<item id> at <location id>"
//   a phantom kit line's component  "<kit line id> component <item id>"
//   a receipt, a shipment           "<order id> receipt <n>", "... shipment <n>"
//   their moves                     "<receipt or shipment id> for <line id>"
//   an assembly's moves             "<assembly id> uses <item id>", "... makes"
//   a count's adjustments           "<count id> for <item id> at <location id>"
//   a reorder's draft, its lines    "reorder at <warehouse id> on <day> from
//                                   <supplier id>", "<order id> for <item id>"
//
// What a person starts (an order, a transfer, an adjustment, a count, an
// assembly) is new, with an id of its own. Numbers: an order's running
// number is the next in its catalog, a receipt's and a shipment's the next
// in its order, a count's the next in its warehouse.

#pragma once
#import <CoreData/CoreData.h>
#import "LBProcedures.h"
#import "Catalog+CoreDataClass.h"
#import "StockItem+CoreDataClass.h"
#import "Warehouse+CoreDataClass.h"
#import "Location+CoreDataClass.h"
#import "Holding+CoreDataClass.h"
#import "Move+CoreDataClass.h"
#import "KitLine+CoreDataClass.h"
#import "Assembly+CoreDataClass.h"
#import "Customer+CoreDataClass.h"
#import "Supplier+CoreDataClass.h"
#import "Contact+CoreDataClass.h"
#import "SaleOrder+CoreDataClass.h"
#import "SaleLine+CoreDataClass.h"
#import "Shipment+CoreDataClass.h"
#import "PurchaseOrder+CoreDataClass.h"
#import "PurchaseLine+CoreDataClass.h"
#import "Receipt+CoreDataClass.h"
#import "StockCount+CoreDataClass.h"
#import "ReorderRule+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

// An order's state, as the model has them.
FOUNDATION_EXPORT NSString * const LBOrderDraft;
FOUNDATION_EXPORT NSString * const LBOrderConfirmed;
FOUNDATION_EXPORT NSString * const LBOrderClosed;
FOUNDATION_EXPORT NSString * const LBOrderCancelled;

// What was found of an item at a location, in a count.
@interface LBCounted : NSObject
+ (instancetype)countedItem:(StockItem *)item at:(Location *)location quantity:(NSDecimalNumber *)quantity;
@property (nonatomic, readonly) StockItem *item;
@property (nonatomic, readonly) Location *location;
@property (nonatomic, readonly) NSDecimalNumber *quantity;
@end

@interface Catalog (LBStock)
// A new sale order, a draft: to the customer, placed on the day, numbered
// the next in the catalog, shipped to and billed at the customer's
// contact's addresses as they are.
- (SaleOrder *)lb_newSaleOrderTo:(Customer *)customer on:(NSDate *)day;
// A new purchase order, a draft: from the supplier, placed on the day,
// numbered the next in the catalog.
- (PurchaseOrder *)lb_newPurchaseOrderFrom:(Supplier *)supplier on:(NSDate *)day;
// The next running number of the documents (orders of the catalog, a
// warehouse's counts, an order's shipments): one more than the highest.
- (int32_t)lb_nextNumberOf:(NSSet *)documents;
// A document's number as people read it: the app's prefix for its kind,
// the catalog's own where it has one, the running number (SO-GAR-0042).
- (NSString *)lb_numberOfKind:(NSString *)kind running:(int32_t)number;
@end

@interface Location (LBStock)
// How many of the item its moves leave here: those in less those out, the
// context's unsaved ones too (what the holding will say once saved).
- (NSDecimalNumber *)lb_heldOf:(StockItem *)item;
// The item's holding here; made, named by both, where it has none.
- (Holding *)lb_holdingOf:(StockItem *)item;
@end

@interface StockItem (LBStock)
// Moved, so many, from one location to another (a transfer), by the user at
// now. Refused for none, the same location, a phantom kit, or more than is
// held there.
- (nullable Move *)lb_transfer:(NSDecimalNumber *)quantity
                          from:(Location *)from
                            to:(Location *)to
                            by:(User *)user
                            at:(NSDate *)now
                         error:(NSError **)error;
// Adjusted at the location: so many in (more than none) or out (less), for
// the reason (not Count: a count adjusts, -lb_count...), with the note.
// Refused for none, a phantom kit, or more out than is held.
- (nullable Move *)lb_adjust:(NSDecimalNumber *)quantity
                          at:(Location *)location
                      reason:(NSString *)reason
                        note:(nullable NSString *)note
                          by:(User *)user
                          at:(NSDate *)now
                       error:(NSError **)error;
// So many batches of the kit assembled at the location on the day (or
// taken apart): each component out, so many per batch, the kit in, its
// yield a batch; the other way round taken apart. Refused for an item
// that is no kit, a phantom, no batches, or a component (the kit, taken
// apart) short at the location.
- (nullable Assembly *)lb_assemble:(NSDecimalNumber *)batches
                                at:(Location *)location
                                on:(NSDate *)day
                       disassemble:(BOOL)disassemble
                                by:(User *)user
                                at:(NSDate *)now
                             error:(NSError **)error;
@end

@interface SaleLine (LBStock)
// Deleted, with its component lines (a phantom kit's). Refused where
// something of it, or of them, has been shipped.
- (BOOL)lb_delete:(NSError **)error;
@end

@interface SaleOrder (LBStock)
// Confirmed (a draft): its phantom kits' lines expanded. Refused for one
// that is not a draft, or has no lines.
- (BOOL)lb_confirm:(NSError **)error;
// Closed (confirmed): done with, whatever is outstanding.
- (BOOL)lb_close:(NSError **)error;
// Cancelled (a draft, or confirmed): never to be filled. Refused once
// something of it is shipped.
- (BOOL)lb_cancel:(NSError **)error;
// Confirmed again (closed).
- (BOOL)lb_reopen:(NSError **)error;
// Its phantom kits' lines given a line of each component, for as many as
// their kits take in whole batches (ceil(kits / yield) * so many a batch),
// unpriced; one of a component no longer in the recipe deleted, one of
// another quantity changed. Refused where a component's line has shipped
// more than it would then be for.
- (BOOL)lb_expandKits:(NSError **)error;
// Shipped, so many of each line (by its id) from the location on the day,
// to the order's ship-to: a shipment, numbered the next in the order, a
// move out for each. Refused for an order not confirmed, no lines, a line
// not of it, a phantom kit's line (ship its components'), none of one, or
// more than is held at the location.
- (nullable Shipment *)lb_shipLines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities
                               from:(Location *)location
                                 on:(NSDate *)day
                                 by:(User *)user
                                 at:(NSDate *)now
                              error:(NSError **)error;
// Its number, as people read it.
@property (nonatomic, readonly) NSString *lb_number;
@end

@interface PurchaseOrder (LBStock)
- (BOOL)lb_confirm:(NSError **)error;
- (BOOL)lb_close:(NSError **)error;
// Refused once something of it is received.
- (BOOL)lb_cancel:(NSError **)error;
- (BOOL)lb_reopen:(NSError **)error;
// Received, so many of each line (by its id) at the location on the day:
// a receipt, numbered the next in the order, a move in for each. Refused
// for an order not confirmed, no lines, a line not of it, or none of one.
- (nullable Receipt *)lb_receiveLines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities
                                   at:(Location *)location
                                   on:(NSDate *)day
                                   by:(User *)user
                                   at:(NSDate *)now
                                error:(NSError **)error;
@property (nonatomic, readonly) NSString *lb_number;
@end

@interface Warehouse (LBStock)
// A count of the warehouse (location nil) or one of its locations, on the
// day, by the user: what was found of each item where. What is held in
// what it counts and not found is counted none. Each difference an
// adjustment of reason Count, part of the count; the warehouse's last
// counted day set, where all of it was. Refused for a location of another
// warehouse, or what was found somewhere the count does not cover.
- (nullable StockCount *)lb_countLocation:(nullable Location *)location
                                    found:(NSArray<LBCounted *> *)found
                                       on:(NSDate *)day
                                       by:(User *)user
                                       at:(NSDate *)now
                                    error:(NSError **)error;
// Draft purchase orders for its reorder rules due: one for each supplier,
// a line for each item, up to its level (its point, where it has none)
// from what is available and coming; at the item's unit cost. Items with
// no supplier or no unit cost are left, in skipped. The drafts made.
- (NSArray<PurchaseOrder *> *)lb_reorderOn:(NSDate *)day
                                   skipped:(NSArray<StockItem *> *_Nullable *_Nullable)skipped
                                     error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
