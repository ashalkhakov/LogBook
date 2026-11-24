// The logbook as an app sees it: Logbook's model over a server's OData
// service, signed in as the server asks (LBSignIn.h). Offline first, the
// desktop app's (-initOfflineFirstWithServiceRoot:signIn:directory:): kept
// on the Mac (LBLocalStore.h, the iOS app's), every change saved there and
// synced with the server when it answers, its actions done there
// (LBLocalActions.h). Online (-initWithServiceRoot:signIn:): the server's
// own, as it has it (ODataIncrementalStore), what a check reads it by.
//
// Saving does what the server does before it saves (the generated
// orm_prepareForSave:): what is derived worked out, every rule checked for
// what the change reaches. A change that breaks one is not sent; one the
// server refuses all the same (another device's change) comes back as its
// error. New objects are given their keys here: a change set holds them.

#pragma once
#import <CoreData/CoreData.h>
#import <ODataSync/ODataSignIn.h>

@class User, LBLocalStore;

NS_ASSUME_NONNULL_BEGIN

@interface LBStore : NSObject

// The compiled model in the app's bundle (Logbook.momd).
+ (nullable NSManagedObjectModel *)model;

- (instancetype)initWithServiceRoot:(NSURL *)serviceRoot signIn:(nullable ODataSignIn *)signIn NS_DESIGNATED_INITIALIZER;
// Offline first: kept in the directory (one of its own for each server).
- (instancetype)initOfflineFirstWithServiceRoot:(NSURL *)serviceRoot signIn:(nullable ODataSignIn *)signIn directory:(NSURL *)directory;
// The directory a server's logbook is kept in on this Mac, under
// Application Support/Logbook.
+ (NSURL *)directoryForServiceRoot:(NSURL *)serviceRoot;
// Offline first: the device's store (nil online).
@property (nonatomic, readonly, strong, nullable) LBLocalStore *local;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly, copy) NSURL *serviceRoot;
@property (nonatomic, readonly, strong, nullable) ODataSignIn *signIn;

// The store opened: NO, and why, when the server cannot be reached as one
// (online), or the Mac's store cannot be opened (offline first: synced once
// where the server answers, else what it kept is shown).
- (BOOL)open:(NSError **)error;
// The main queue's: what the windows bind to.
@property (nonatomic, readonly, strong, nullable) NSManagedObjectContext *context;
// Another main-queue context over the same store, as the main one is (its
// undo, its merge policy): a window's that edits apart from the others
// (the stock windows), saved by -saveContext:error:.
- (NSManagedObjectContext *)newContext;

// Who is signed in, as a User of the logbook (made when there is none
// yet): whom a new vehicle belongs to. With no sign-in, the user named by
// the LBUser default.
@property (nonatomic, readonly, strong, nullable) User *user;

// The context's changes: keys given, derivations and rules, then sent.
// NO, and why (each violation in its NSDetailedErrorsKey), when a rule is
// broken or the server refuses; the changes are kept to put right.
- (BOOL)save:(NSError **)error;
// Each object made and not yet saved given its key (an answer made as its
// question is answered), as saving would: what a form edits it by.
- (void)identifyInserted;
// The same of a context -newContext made.
- (BOOL)saveContext:(NSManagedObjectContext *)context error:(NSError **)error;

// Offline first: synced now, waited for; NO, and why, where the server
// does not answer (online: YES, there is nothing to sync).
- (BOOL)syncAndWait:(NSError **)error;
// The server's actions on the object (LBLocalActions.h): offline first,
// done here, by the user; online, called at the server. Not saved here.
- (nullable id)performAction:(NSString *)name
                          on:(NSManagedObject *)object
                  parameters:(nullable NSDictionary<NSString *, id> *)parameters
                       error:(NSError **)error;

// What ought not to be, but may (deontic rules: the meter goes down, an
// event after the car was sold): the objects changed asked, each warning
// said.
- (NSArray<NSError *> *)warnings;

@end

// An object of the model with a key of its own (a vehicle, a record, a
// user's checklist): what the generated classes declare.
@protocol LBIdentified <NSObject>
@property (nullable, nonatomic, copy) NSUUID *id;
@end

NS_ASSUME_NONNULL_END
