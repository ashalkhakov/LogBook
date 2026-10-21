// The logbook kept on the device, offline first: Logbook's model in a store
// of the device's own (SQLite, kept across launches), kept in sync with a
// Logbook server by ODataSync (the iOS app's; LBStore.h is the desktop's,
// online). Foundation and Core Data only.
//
// Every change is saved here first and waits in the outbox; a sync brings
// down what changed at the server (what this user may see of it) and sends
// up what waits. Which way each entity goes, and the bookkeeping that tells
// one version from another, are the model's (Model/Logbook.orm's mapping,
// docs/PROCESSES.md, Offline): the reference data down, the logbook both
// ways.
//
// Saving does what the server does before it saves: the reminders the
// changed events do the work of closed (automatic completion,
// LBProcedures.h), then the generated orm_prepareForSave: (what is derived
// worked out, every rule checked). The same code as the server's, and what
// it makes named by what it is made of: the phone and the server make the
// same objects, which the sync meets as one.
//
// A change made here and at the server since they last agreed is a
// conflict: the server's version stands (the sync never waits), and this
// side's is kept as a pending conflict (LBConflicts.h) for the user to
// settle here.

#pragma once
#import <CoreData/CoreData.h>
#import <ODataSync/ODataSync.h>
#import "LBConflicts.h"

@class User, Attachment, Record;

NS_ASSUME_NONNULL_BEGIN

// On the main thread: something changed (a save, a sync, a conflict
// settled), the views read again. userInfo: "status" (text).
FOUNDATION_EXPORT NSNotificationName const LBLocalStoreDidChangeNotification;

@interface LBLocalStore : NSObject <ODataSyncDelegate>

// Application Support/Logbook, made the first time.
+ (NSURL *)defaultDirectory;

// The store in directory (Logbook.sqlite, and AppState.sqlite beside it),
// made the first time, of the compiled model at modelURL (nil: the main
// bundle's Logbook.momd), with ODataSync's bookkeeping.
- (nullable instancetype)initWithDirectory:(NSURL *)directory modelURL:(nullable NSURL *)modelURL
                                     error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The main queue's: what the views show and change.
@property (nonatomic, readonly) NSManagedObjectContext *context;
@property (nonatomic, readonly) ODataSyncEngine *engine;
@property (nonatomic, readonly) LBAppState *appState;

// The server (its service root); nil: none, the logbook stays here.
@property (nonatomic, copy, nullable) NSURL *serviceRoot;
// Signed in as the server asks (LBSignIn.h): its credentials go with every
// request. nil: a server that asks for no one.
@property (nonatomic, strong, nullable) ODataSignIn *signIn;
// Who the user is with no sign-in (a server for trying it out): their
// email. Signed in, the sign-in's.
@property (nonatomic, copy, nullable) NSString *email;

// Off: nothing goes or comes (the user's switch); what is saved waits.
// On by default.
@property (nonatomic) BOOL syncEnabled;
// A sync now and then (seconds; 0: never, the default), and a little after
// each save.
@property (nonatomic) NSTimeInterval syncInterval;
@property (nonatomic, readonly, getter=isSyncing) BOOL syncing;
// "Synced 10:42. 2 changes waiting.", "Sync is off.", "Not synced: ..."
@property (nonatomic, readonly, copy) NSString *status;
@property (nonatomic, readonly, nullable) NSDate *lastSync;
// Changes not sent yet; those the server refused (with its words).
- (NSUInteger)pendingCount;
- (NSArray<ODataSyncIssue *> *)issues;
// On a thread of its own; LBLocalStoreDidChangeNotification when done.
// Asked while one runs: once more after it.
- (void)sync;
// The same, waited for, on the main thread (the self-test).
- (BOOL)syncAndWait:(NSError **)error;

// Who is signed in, as a User of the logbook (made when there is none
// yet: the first sync brings them when the server has them).
@property (nonatomic, readonly, nullable) User *user;
// The context's changes: keys given, automatic completion, derivations and
// rules, then saved here, and a sync asked for. NO, and why (each rule
// broken in NSDetailedErrorsKey, as the model says it): nothing saved, the
// changes kept to put right.
- (BOOL)save:(NSError **)error;
// What ought not to be, but may (deontic rules): the changed objects asked,
// and the other records of their vehicles (the meter goes up is said of
// the earlier reading); those the user went ahead with not said again.
- (NSArray<NSError *> *)warnings;
// Saved anyway: these not said again, while the app runs.
- (void)acceptWarnings:(NSArray<NSError *> *)warnings;
// Every rule an error says is broken, each said: the model's sentences.
+ (NSArray<NSString *> *)sentencesOfError:(NSError *)error;

// Pending conflicts (LBConflicts.h), the latest first.
- (NSArray<LBPendingConflict *> *)pendingConflicts;
// The object a conflict is of, as it is now (the server's version); nil:
// deleted.
- (nullable NSManagedObject *)objectOfConflict:(LBPendingConflict *)conflict;
// Keep theirs: what this device had given up, the conflict forgotten.
- (void)keepTheirs:(LBPendingConflict *)conflict;
// Keep mine: this device's values written back over the server's, as a
// new change (saved, so the rules are checked, and synced); an object the
// server deleted made again. NO, and why, when they cannot be saved.
- (BOOL)keepMine:(LBPendingConflict *)conflict error:(NSError **)error;
// Settled by hand: the object edited and saved, the conflict forgotten.
- (void)settleConflict:(LBPendingConflict *)conflict;
// A value of a conflict as a person reads it: a date, an amount, the
// related object's title.
- (NSString *)textOfValue:(nullable id)value property:(NSString *)name ofConflict:(LBPendingConflict *)conflict;

// A receipt's photo, as an Attachment of the record: named by its id
// (.jpg), the image its content, which syncs with it.
- (Attachment *)attachImage:(NSData *)jpeg toRecord:(Record *)record;

@end

// Now, to the second: what a record made now is at. A moment the server
// sends back as JSON keeps milliseconds; one of whole seconds compares the
// same on both sides.
FOUNDATION_EXPORT NSDate *LBNow(void);

NS_ASSUME_NONNULL_END
