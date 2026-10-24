// The stock procedures (Shared/LBStockProcedures.h) as the server's OData
// actions, bound to what they act on, as LBActions.h binds the reminders'.
// Each is carried out and saved whole, the model's rules checked as for any
// write, or refused (400, the procedure's message) and nothing of it saved.
//
//   POST SaleOrders(<id>)/Default.Confirm      the order (its kits expanded)
//   POST SaleOrders(<id>)/Default.Close, .Cancel, .Reopen
//   POST SaleOrders(<id>)/Default.ExpandKits   the order
//   POST SaleOrders(<id>)/Default.Ship
//        {Lines: {"<line id>": quantity, ...}, From, Day}  the shipment
//   POST PurchaseOrders(<id>)/Default.Confirm, .Close, .Cancel, .Reopen
//   POST PurchaseOrders(<id>)/Default.Receive
//        {Lines: {"<line id>": quantity, ...}, At, Day}    the receipt
//   POST StockItems(<id>)/Default.Transfer {Quantity, From, To}  the move
//   POST StockItems(<id>)/Default.Adjust
//        {Quantity, At, Reason, Note?}                     the move
//   POST StockItems(<id>)/Default.Assemble
//        {Batches, At, Day, Disassemble?}                  the assembly
//   POST Warehouses(<id>)/Default.Count
//        {Location?, Found: [{Item, Location, Quantity}], Day}  the count
//   POST Warehouses(<id>)/Default.Reorder {Day}            the drafts made
//
// A location is a reference ({"@odata.id": "Locations(<id>)"}); in Lines
// and Found, ids are as the entity's key, quantities numbers (or decimal
// strings); a day a moment whose UTC day is meant. Who may (LBPermissions.h):
// an order's actions its catalog's owner or managers; Ship, Receive,
// Transfer, Adjust, Assemble and Count the staff of the warehouses they are
// at (keepers or managers) or the owner; Reorder a manager of the warehouse
// or the owner (403 for anyone else). An anonymous request acts as the
// catalog's owner.

#pragma once
#import <ODataService/ODataService.h>
#import "LBStockProcedures.h"

NS_ASSUME_NONNULL_BEGIN

@protocol LBSaleOrderActions <ODataActions>
- (nullable SaleOrder *)confirm:(ODataReply *)reply;
- (nullable SaleOrder *)close:(ODataReply *)reply;
- (nullable SaleOrder *)cancel:(ODataReply *)reply;
- (nullable SaleOrder *)reopen:(ODataReply *)reply;
- (nullable SaleOrder *)expandKits:(ODataReply *)reply;
- (nullable Shipment *)shipWithLines:(NSDictionary *)lines from:(Location *)from day:(nullable NSDate *)day reply:(ODataReply *)reply;
@end

@protocol LBPurchaseOrderActions <ODataActions>
- (nullable PurchaseOrder *)confirm:(ODataReply *)reply;
- (nullable PurchaseOrder *)close:(ODataReply *)reply;
- (nullable PurchaseOrder *)cancel:(ODataReply *)reply;
- (nullable PurchaseOrder *)reopen:(ODataReply *)reply;
- (nullable Receipt *)receiveWithLines:(NSDictionary *)lines at:(Location *)at day:(nullable NSDate *)day reply:(ODataReply *)reply;
@end

@protocol LBStockItemActions <ODataActions>
- (nullable Move *)transferWithQuantity:(NSDecimalNumber *)quantity from:(Location *)from to:(Location *)to reply:(ODataReply *)reply;
- (nullable Move *)adjustWithQuantity:(NSDecimalNumber *)quantity
                                   at:(Location *)at
                               reason:(NSString *)reason
                                 note:(nullable NSString *)note
                                reply:(ODataReply *)reply;
- (nullable Assembly *)assembleWithBatches:(NSDecimalNumber *)batches
                                        at:(Location *)at
                                       day:(nullable NSDate *)day
                               disassemble:(nullable NSNumber *)disassemble
                                     reply:(ODataReply *)reply;
@end

@protocol LBWarehouseActions <ODataActions>
- (nullable StockCount *)countWithLocation:(nullable Location *)location
                                     found:(NSArray *)found
                                       day:(nullable NSDate *)day
                                     reply:(ODataReply *)reply;
- (nullable NSArray<PurchaseOrder *> *)reorderWithDay:(nullable NSDate *)day reply:(ODataReply *)reply;
@end

@interface SaleOrder (LBStockActions) <LBSaleOrderActions>
@end

@interface PurchaseOrder (LBStockActions) <LBPurchaseOrderActions>
@end

@interface StockItem (LBStockActions) <LBStockItemActions>
@end

@interface Warehouse (LBStockActions) <LBWarehouseActions>
@end

NS_ASSUME_NONNULL_END
