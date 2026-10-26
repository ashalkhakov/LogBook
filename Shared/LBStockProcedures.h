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
//   a user's contact, its customer  "<catalog id> contact of <email>",
//                                   "<contact id> customer"
//   an event's sale of its parts    "parts of <event id>"
//   a return, its moves             "<order id> return <n>", "<return id>
//                                   for <line id>"
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
#import "Address+CoreDataClass.h"
#import "SaleOrder+CoreDataClass.h"
#import "SaleLine+CoreDataClass.h"
#import "Shipment+CoreDataClass.h"
#import "PurchaseOrder+CoreDataClass.h"
#import "PurchaseLine+CoreDataClass.h"
#import "Receipt+CoreDataClass.h"
#import "StockCount+CoreDataClass.h"
#import "ReorderRule+CoreDataClass.h"
#import "SupplierItem+CoreDataClass.h"
#import "ItemCode+CoreDataClass.h"
#import "CustomerReturn+CoreDataClass.h"
#import "SupplierReturn+CoreDataClass.h"
#import "Event+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "TyreChange+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "Vehicle+CoreDataClass.h"

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
// A new catalog, the user's, named so, priced in their currency, with one
// warehouse ("Main") and one location in it ("Default"): a person with one
// shelf need never see either.
+ (Catalog *)lb_newCatalogNamed:(NSString *)name owner:(User *)owner inContext:(NSManagedObjectContext *)context;
// A new sale order, a draft: to the customer, placed on the day, numbered
// the next in the catalog, shipped to and billed at the customer's
// contact's addresses as they are.
- (SaleOrder *)lb_newSaleOrderTo:(Customer *)customer on:(NSDate *)day;
// A new purchase order, a draft: from the supplier, placed on the day,
// numbered the next in the catalog.
- (PurchaseOrder *)lb_newPurchaseOrderFrom:(Supplier *)supplier on:(NSDate *)day;
// The next SKU given an item: the catalog's prefix (else "SKU"), a dash,
// and one more than the highest number so made (GAR-00042).
- (NSString *)lb_nextSKU;
// The next running number of the documents (orders of the catalog, a
// warehouse's counts, an order's shipments): one more than the highest.
- (int32_t)lb_nextNumberOf:(NSSet *)documents;
// A document's number as people read it: the app's prefix for its kind,
// the catalog's own where it has one, the running number (SO-GAR-0042).
- (NSString *)lb_numberOfKind:(NSString *)kind running:(int32_t)number;
@end

@interface Catalog (LBParts)
// The customer a logbook user is here: that of the contact that stands for
// them, made where there is none (named by the catalog and their email,
// called by their name), and made a customer.
- (Customer *)lb_customerFor:(User *)user;
@end

@interface NSManagedObjectContext (LBParts)
// Before a save: the parts of the events whose sale, or its lines, the
// context is about to save, shipped (-lb_shipParts:); refused as the first
// refuses. The server's and the phone's, as automatic completion is.
- (BOOL)lb_shipPartsOfChangedEvents:(NSError **)error;
@end

// A service's or a tyre change's parts: the lines of a sale of them to the
// vehicle's owner, shipped from a warehouse as the event is saved.
@interface Event (LBParts)
// Whether it may use parts: a service, a tyre change.
@property (nonatomic, readonly) BOOL lb_usesParts;
// The sale of its parts; nil, none yet.
@property (nonatomic, readonly, nullable) SaleOrder *lb_partsSale;
// A part used: a line of the sale of its parts, of the item, so many, at
// its unit cost (none: at its price; neither: refused). The sale made
// where there is none: of the item's catalog, to the vehicle owner's
// customer there, shipping from the location, placed on the event's day,
// a draft. Refused for an event that uses none, none of it, an item of
// another catalog than the sale's, or a location of another catalog.
- (nullable SaleLine *)lb_usePart:(StockItem *)item
                         quantity:(NSDecimalNumber *)quantity
                             from:(Location *)location
                            error:(NSError **)error;
// A part's use changed to so many. More: its line is for more, shipped as
// the event is saved. Fewer: what of its line is not shipped yet is taken
// off; of what was, as many come back (a customer return, Not used, to
// where they came from, now, by the user). None of a line nothing of which
// was shipped: the line deleted. Refused as a return is.
- (BOOL)lb_setUsed:(NSDecimalNumber *)used ofPart:(SaleLine *)part by:(User *)user at:(NSDate *)now error:(NSError **)error;
// Its parts shipped: what is left of each line, from where its sale ships
// from, on its day and at its moment, by whoever entered it; the sale
// confirmed first where a draft. Refused, nothing changed, where the
// location holds too few, or a line was changed to less than has been
// shipped (-lb_setUsed: says fewer). Nothing to do: YES.
- (BOOL)lb_shipParts:(NSError **)error;
@end

@interface Contact (LBStock)
// Whether it is a customer, a supplier, of its catalog: set, the part made
// (or removed, refused where an order is of it: it stays, and says so).
@property (nonatomic) BOOL lb_isCustomer;
@property (nonatomic) BOOL lb_isSupplier;
// Where it is shipped to, as lines of text: set, its shipping address
// made where it has none (its billing address too, where it has none).
@property (nonatomic, copy, nullable) NSString *lb_shippingLines;
@end

@interface SupplierItem (LBStock)
// Whether its item is preferably bought as it: set, it is (and no other);
// cleared, none is.
@property (nonatomic) BOOL lb_isPreferred;
@end

@interface Location (LBStock)
// How many of the item its moves leave here: those in less those out, the
// context's unsaved ones too (what the holding will say once saved).
- (NSDecimalNumber *)lb_heldOf:(StockItem *)item;
// The item's holding here; made, named by both, where it has none.
- (Holding *)lb_holdingOf:(StockItem *)item;
@end

@interface StockItem (LBStock)
// Whom it is preferably bought from: set, its supplier item from them made
// where it has none, and preferred.
@property (nonatomic, strong, nullable) Supplier *lb_preferredSupplier;
// What reordering buys: its preferred supplier item, else its only one;
// nil for none or several and none preferred.
@property (nonatomic, readonly, nullable) SupplierItem *lb_reorderedAs;
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
// How many of it were kept (of a part, used): its quantity, less those
// that came back, as its moves say (before the save that derives
// returnedQuantity).
@property (nonatomic, readonly) NSDecimalNumber *lb_kept;
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
// Come back: so many of each line (by its id) received at the location on
// the day, for the reason (one of the model's ReturnReasons): a customer
// return, numbered the next in the order, a move in for each. The lines
// stay as they are: what came back is not outstanding again. Refused for
// an order neither confirmed nor closed, no lines, a line not of it, a
// phantom kit's line (return its components'), none of one, or more of one
// than went out and has not come back.
- (nullable CustomerReturn *)lb_returnLines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities
                                         at:(Location *)location
                                         on:(NSDate *)day
                                     reason:(NSString *)reason
                                       note:(nullable NSString *)note
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
// Sent back: so many of each line (by its id) shipped from the location on
// the day, for the reason: a supplier return, numbered the next in the
// order, a move out for each. Refused for an order neither confirmed nor
// closed, no lines, a line not of it, none of one, more of one than came
// in and has not gone back, or more than is held at the location.
- (nullable SupplierReturn *)lb_returnLines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities
                                       from:(Location *)location
                                         on:(NSDate *)day
                                     reason:(NSString *)reason
                                       note:(nullable NSString *)note
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
// Draft purchase orders for its reorder rules due: one for each supplier
// of what each item is reordered as (-lb_reorderedAs), a line for each
// item, up to its level (its point, where it has none) from what is
// available and coming, at least the supplier's minimum, in whole packs;
// at the supplier's cost, else the item's unit cost. Items with no supplier
// item to buy, or no cost, are left, in skipped. The drafts made.
- (NSArray<PurchaseOrder *> *)lb_reorderOn:(NSDate *)day
                                   skipped:(NSArray<StockItem *> *_Nullable *_Nullable)skipped
                                     error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
