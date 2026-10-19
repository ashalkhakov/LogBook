#import "LBSignIn.h"

NSString * const LBSignInClientID = @"logbook";

ODataSignIn *LBSignInTo(NSURL *serviceRoot) {
    ODataSignIn *signIn = [[ODataSignIn alloc] initWithServiceRoot:serviceRoot
                                                           secrets:[[ODataSecretStore alloc] initWithServiceName:@"Logbook sign-in"]];
    signIn.clientID = LBSignInClientID;
    return signIn;
}

NSURL *LBServiceRootOf(NSString *typed) {
    NSString *text = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return nil;
    if (![text containsString:@"://"]) text = [@"https://" stringByAppendingString:text];
    NSURL *url = [NSURL URLWithString:text];
    if (!url.host.length || !([url.scheme isEqual:@"http"] || [url.scheme isEqual:@"https"])) return nil;
    NSString *path = url.path.length ? url.path : @"/";
    if ([path isEqualToString:@"/"]) path = @"/odata/";
    if (![path hasSuffix:@"/"]) path = [path stringByAppendingString:@"/"];
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    parts.path = path;
    return parts.URL;
}
