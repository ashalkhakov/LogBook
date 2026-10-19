// Signing in to a Logbook server: ODataSync's ODataSignIn, as the server's
// $metadata says (nothing, or OpenID Connect by the device flow), as
// Logbook's client at the identity provider ("logbook": a public client
// with the device flow on), its tokens in the system's secret store (the
// Keychain; on GNUstep a file only the user can read).

#pragma once
#import <Foundation/Foundation.h>
#import <ODataSync/ODataSignIn.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const LBSignInClientID;   // @"logbook"

// A sign-in to the server at serviceRoot, as Logbook's client.
FOUNDATION_EXPORT ODataSignIn *LBSignInTo(NSURL *serviceRoot);

// The address typed, made a service root (http(s), /odata/ and a trailing
// slash added when missing); nil: no address.
FOUNDATION_EXPORT NSURL *_Nullable LBServiceRootOf(NSString *typed);

NS_ASSUME_NONNULL_END
