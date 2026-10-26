// Who may see and change what (docs/CSDP.md, Permissions; docs/STOCK.md,
// Who may), at the server, once a sign-in is set. The signed-in user is
// the User whose email is the principal's email claim, else its subject;
// made the first time they write.
//
// Who may is the permissions file's (Logbook.permissions.plist, beside
// the server; ODataKit's docs/permissions.md), as relations the service
// checks on every read, write and action. What the handlers here keep is
// what no relation says:
//
// - Who made a row, whatever the request says: a vehicle's owner, a
//   record's enteredBy, a rescheduling's madeBy, a checklist's keeper, a
//   catalog's owner. Who entered a record, or made a rescheduling, is said
//   once: a change to it is left out.
// - Users: named by their email, which whoever names them knows. A write
//   finds anyone by it, and anyone adds another by it alone (to share a
//   vehicle before they first sign in); a read sees themselves and the
//   people they share a vehicle with.
// - An item with no SKU, an order or count with no number, is given the
//   next of its kind.
// - A set the permissions file does not name is read only.
//
// An anonymous request (AllowAnonymous) holds no relation: once a
// sign-in is set, it sees and writes nothing the file limits. With no
// sign-in, nothing is checked, and an action acts as the vehicle's or
// catalog's owner.

#pragma once
#import <ODataSync/ODataSyncService.h>

NS_ASSUME_NONNULL_BEGIN

@class User;

// The signed-in user's email: the principal's email claim, else its
// subject; nil for no one (an anonymous request).
FOUNDATION_EXPORT NSString *_Nullable LBEmailOf(ODataRequest *request);
// The user of the email, made when there is none and make says so.
FOUNDATION_EXPORT User *_Nullable LBUserNamed(NSManagedObjectContext *context, NSString *email, BOOL make);
// Whether the request's caller holds the relation on the object, as the
// permissions say (ODataService -request:holds:onObject:); YES with no
// permissions (no sign-in). An action asks it of what a parameter names.
FOUNDATION_EXPORT BOOL LBHolds(ODataRequest *request, NSString *relation, NSManagedObject *_Nullable object);

// Each entity set's handler; before ODataSyncService is made (it keeps a
// handler that is already an ODataSyncSetHandler), after the service is
// given its permissions.
FOUNDATION_EXPORT void LBServePermissions(ODataService *service);

NS_ASSUME_NONNULL_END
