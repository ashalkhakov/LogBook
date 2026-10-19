// An array controller of a Core Data entity's objects, the same on macOS
// and GNUstep (whose controllers have no entity mode): the app ships it.
//
// In a XIB: an array controller of this class, its object class the
// entity's (the model's generated class: Vehicle), its context bound
// (context). Neither is AppKit's entity mode (entityName,
// managedObjectContext), which GNUstep has not and which would take an
// Apple controller over. Then
// either its content is the entity's objects, fetched once the context
// comes and kept as the context changes (what is inserted added, what is
// deleted dropped, what is changed asked the predicate again), or its
// content is bound (contentSet to a vehicle's records) and the binding
// keeps it. Either way add: makes a new object of the entity in the
// context, and remove: deletes what it removes.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface LBEntityController : NSArrayController
// The entity whose objects it controls, and makes: by default its object
// class's name (the generated class is named as its entity).
@property (nonatomic, copy, nullable) NSString *modelEntityName;
// Where they are: bound in the XIB.
@property (nonatomic, strong, nullable) NSManagedObjectContext *context;
// Of the entity's objects, those it controls (nil: all); content fetched
// only.
@property (nonatomic, copy, nullable) NSPredicate *contentPredicate;
// The entity's objects fetched again (content fetched only).
- (void)refetch;
@end

NS_ASSUME_NONNULL_END
