// What this device keeps of its own, beside the logbook: its app state, in a
// small Core Data model of its own (built here, in code), in a store of its
// own beside the logbook's, never synced, and no part of the model
// (Model/Logbook.orm):
//
// - pending conflicts: what this device changed of an object that the
//   server changed too, since they last agreed. The sync never waits on
//   one: the server's version is taken (LBConflictResolver, ODataSync's
//   resolver), and this device's side kept here, for the user to settle
//   (LBLocalStore.h): keep theirs, keep mine (written back, a new change),
//   or edit by hand.
//
// Foundation and Core Data only: the iOS app's, and checked on macOS and
// GNUstep with the rest of Shared/.

#pragma once
#import <CoreData/CoreData.h>
#import <ODataSync/ODataSyncEngine.h>

NS_ASSUME_NONNULL_BEGIN

// One conflict, as kept. Values by the model's property names: an
// attribute's value, a to-one's related object's key (a dictionary of its
// key attributes), NSNull for none.
@interface LBPendingConflict : NSManagedObject
// The entity of the object, and its key (by attribute name).
@property (nonatomic, copy, nullable) NSString *objectEntityName;
@property (nonatomic, readonly) NSDictionary<NSString *, id> *key;
// The properties both sides changed, differently, in the model's order.
@property (nonatomic, readonly) NSArray<NSString *> *properties;
// This device's values, and the server's (which the object has now).
@property (nonatomic, readonly) NSDictionary<NSString *, id> *mine;
@property (nonatomic, readonly) NSDictionary<NSString *, id> *theirs;
// Deleted at the server, changed here: the deletion stands (mine: every
// value this device had). Deleted here, changed there: the server's
// version came back.
@property (nonatomic) BOOL deletedThere;
@property (nonatomic) BOOL deletedHere;
// When the sync met it.
@property (nonatomic, copy, nullable) NSDate *when;
@end

@interface LBAppState : NSObject
// The store at url, made the first time.
- (nullable instancetype)initWithStoreURL:(NSURL *)url error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
// The main queue's.
@property (nonatomic, readonly) NSManagedObjectContext *context;

// The conflicts not settled yet, the latest first.
- (NSArray<LBPendingConflict *> *)pendingConflicts;
// Kept (on any thread: the resolver's is the sync's).
- (void)recordConflictOfEntity:(NSString *)entityName key:(NSDictionary<NSString *, id> *)key
                    properties:(NSArray<NSString *> *)properties mine:(NSDictionary<NSString *, id> *)mine
                        theirs:(NSDictionary<NSString *, id> *)theirs deletedThere:(BOOL)deletedThere
                   deletedHere:(BOOL)deletedHere;
// Settled: forgotten.
- (void)removeConflict:(LBPendingConflict *)conflict;
@end

// ODataSync's resolver for a both entity: the server's version stands
// (take remote: the sync never waits), and what this side changed
// otherwise than the server did is kept as a pending conflict. Bookkeeping
// (versions, stamps) is no conflict, nor a value one side left unsaid, nor
// the same value on both sides (the same procedure carried out on both:
// the same objects, by their names).
@interface LBConflictResolver : NSObject <ODataSyncResolving>
- (instancetype)initWithAppState:(LBAppState *)state NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
// Whether two of a conflict's values are the same: dates to the
// millisecond (the service's JSON), numbers by value, keys by their parts.
+ (BOOL)value:(nullable id)one isSameAs:(nullable id)other;
@end

// A value as a property list (a conflict's, kept), and back.
FOUNDATION_EXPORT id LBPropertyListOfValue(id _Nullable value);
FOUNDATION_EXPORT id _Nullable LBValueOfPropertyList(id _Nullable plist);

NS_ASSUME_NONNULL_END
