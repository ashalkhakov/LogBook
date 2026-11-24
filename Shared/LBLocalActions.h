// The server's actions (Server/LBActions.h, Server/LBStockActions.h) done
// on the device, offline first: the same shared procedures
// (LBProcedures.h, LBStockProcedures.h) on the device's store, by the user
// signed in, their parameters as an app gives them (objects, a unit by its
// code, lines by their ids). What it makes is saved as any change is, and
// synced: the server checks who may as it takes the change.
//
//   Start, Continue (a schedule); Complete, Reschedule, Cancel (a
//   reminder); Discard (a record); Confirm, Close, Cancel, Reopen,
//   ExpandKits, Ship, Return (a sale); Confirm, Close, Cancel, Reopen,
//   Receive, Return (a purchase); Transfer, Adjust, Assemble (an item);
//   Count, Reorder (a warehouse).

#pragma once
#import <CoreData/CoreData.h>

@class User;

NS_ASSUME_NONNULL_BEGIN

@interface LBLocalActions : NSObject
// What the action made or changed (NSNull where it answers nothing); nil,
// and why, where the procedure refuses or the action is none of these.
+ (nullable id)performAction:(NSString *)name
                          on:(NSManagedObject *)object
                  parameters:(nullable NSDictionary<NSString *, id> *)parameters
                          by:(User *)user
                       error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
