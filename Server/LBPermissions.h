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
// An anonymous request (AllowAnonymous) is let do anything, as before a
// sign-in is set.

#pragma once
#import <ODataSync/ODataSyncService.h>

NS_ASSUME_NONNULL_BEGIN

// Each entity set kept to the permissions; before ODataSyncService is made
// (it keeps a handler that is already an ODataSyncSetHandler).
FOUNDATION_EXPORT void LBServePermissions(ODataService *service);

NS_ASSUME_NONNULL_END
