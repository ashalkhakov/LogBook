// Who may see and change what (docs/CSDP.md, Permissions), at the server,
// once a sign-in is set. The signed-in user is the User whose email is the
// principal's email claim, else its subject; made the first time they
// write.
//
// - A user sees the vehicles they drive (own, or are entered as a driver
//   of: OwnerDrives) and what is of them: records, sharing, valuations,
//   and a record's items, attachments and answers. Themselves, and the
//   people they share a vehicle with. Their checklists, and those an
//   inspection of a vehicle of theirs went through. The reference data.
// - A vehicle is made by anyone signed in, its owner; only its owner
//   changes or removes it, who drives it (sharing) and its valuations.
// - A record is added by whoever drives its vehicle, entered by them
//   whatever the request says; only the owner changes or removes one. A
//   record's items, attachments and answers go with it: added with a new
//   record of one's own, else the owner's.
// - A user is named by their email, which whoever names them knows: a
//   write finds anyone by it, and anyone adds another by it alone (to
//   share a vehicle before they first sign in). What else is said of a
//   user is theirs to write. A checklist is its keeper's.
// - Units and kinds of cost are the app's: read only. An exchange rate is
//   added by anyone, changed by no one.
//
// - The procedures (LBActions.h): a reminder is closed and moved by
//   whoever drives its vehicle; a schedule started, a reminder cancelled
//   and a record discarded by the vehicle's owner alone.
//
// Stock (docs/STOCK.md, Who may): a catalog is its maker's, its owner's;
// it and all of it is seen by its owner and its warehouses' staff. Its
// owner alone writes its items, kits, categories, contacts, warehouses
// and staff; a manager (of any of its warehouses) its orders, (of a
// warehouse) that warehouse's locations and reorder rules; a keeper (of a
// warehouse, or its manager) the moves, holdings, receipts, shipments,
// assemblies and counts there, which only a manager there, or the owner,
// changes or removes. SKUs, order and count numbers left out are given,
// the next of their kind. The procedures (LBStockActions.h) the same.
//
// An anonymous request (AllowAnonymous) is let do anything, as before a
// sign-in is set.

#pragma once
#import <ODataSync/ODataSyncService.h>

NS_ASSUME_NONNULL_BEGIN

@class User, Vehicle, Catalog, Warehouse;

// The signed-in user's email: the principal's email claim, else its
// subject; nil for no one (an anonymous request).
FOUNDATION_EXPORT NSString *_Nullable LBEmailOf(ODataRequest *request);
// The user of the email, made when there is none and make says so.
FOUNDATION_EXPORT User *_Nullable LBUserNamed(NSManagedObjectContext *context, NSString *email, BOOL make);
// Whether the user of the email owns the vehicle; owns it or is entered as
// a driver of it.
FOUNDATION_EXPORT BOOL LBOwns(Vehicle *_Nullable vehicle, NSString *email);
FOUNDATION_EXPORT BOOL LBDrives(Vehicle *_Nullable vehicle, NSString *email);
// Of a catalog: whether the user of the email owns it; owns it or is of the
// staff of one of its warehouses (sees it); owns it or manages one of its
// warehouses. Of a warehouse: owns its catalog or manages it; owns its
// catalog or is of its staff.
FOUNDATION_EXPORT BOOL LBOwnsCatalog(Catalog *_Nullable catalog, NSString *email);
FOUNDATION_EXPORT BOOL LBSeesCatalog(Catalog *_Nullable catalog, NSString *email);
FOUNDATION_EXPORT BOOL LBManagesIn(Catalog *_Nullable catalog, NSString *email);
FOUNDATION_EXPORT BOOL LBManages(Warehouse *_Nullable warehouse, NSString *email);
FOUNDATION_EXPORT BOOL LBKeeps(Warehouse *_Nullable warehouse, NSString *email);

// Each entity set kept to the permissions; before ODataSyncService is made
// (it keeps a handler that is already an ODataSyncSetHandler).
FOUNDATION_EXPORT void LBServePermissions(ODataService *service);

NS_ASSUME_NONNULL_END
