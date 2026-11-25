#import "LBSignIn.h"

NSString * const LBSignInClientID = @"logbook";

/* Tokens handed in, for a check run against an identity provider (the
   self-test signed in through Keycloak, Tests/signed-in-check.sh):
   LB_SIGN_IN_TOKENS, the provider's token answer as JSON, kept in memory
   as the device flow keeps them, never in the system's store. */
@interface LBHandedTokens : NSObject <ODataSecretStoring>
@end

@implementation LBHandedTokens {
    NSMutableDictionary *_byAccount;
    NSDictionary *_answer;
}

- (instancetype)initWithAnswer:(NSDictionary *)answer {
    if ((self = [super init])) {
        _byAccount = [NSMutableDictionary dictionary];
        _answer = answer;
    }
    return self;
}

- (NSDictionary *)secretsForAccount:(NSString *)account {
    NSMutableDictionary *kept = [_byAccount[account] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (!kept[@"access"] && _answer[@"access_token"]) {
        kept[@"kind"] = kept[@"kind"] ?: @(ODataSignInOpenID);
        kept[@"access"] = _answer[@"access_token"];
        if (_answer[@"refresh_token"]) kept[@"refresh"] = _answer[@"refresh_token"];
        kept[@"expires"] = @([NSDate date].timeIntervalSince1970 + ([_answer[@"expires_in"] doubleValue] ?: 300));
        /* Who, as the device flow names them: the access token's claims. */
        NSArray *parts = [_answer[@"access_token"] componentsSeparatedByString:@"."];
        NSString *payload = parts.count == 3 ? [[parts[1] stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                                                  stringByReplacingOccurrencesOfString:@"_" withString:@"/"] : nil;
        while (payload.length % 4) payload = [payload stringByAppendingString:@"="];
        NSData *data = payload ? [[NSData alloc] initWithBase64EncodedString:payload options:0] : nil;
        NSDictionary *claims = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        id name = claims[@"preferred_username"] ?: claims[@"email"] ?: claims[@"sub"];
        if ([name isKindOfClass:[NSString class]]) kept[@"name"] = name;
        if ([claims[@"email"] isKindOfClass:[NSString class]]) kept[@"email"] = claims[@"email"];
        _byAccount[account] = kept;
    }
    return kept;
}

- (BOOL)setSecrets:(NSDictionary *)secrets forAccount:(NSString *)account {
    _byAccount[account] = [secrets mutableCopy];
    return YES;
}
@end

ODataSignIn *LBSignInTo(NSURL *serviceRoot) {
    NSString *handed = [NSProcessInfo processInfo].environment[@"LB_SIGN_IN_TOKENS"];
    NSDictionary *answer = handed.length ? [NSJSONSerialization JSONObjectWithData:[handed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
    static LBHandedTokens *tokens;
    if ([answer isKindOfClass:[NSDictionary class]] && !tokens) tokens = [[LBHandedTokens alloc] initWithAnswer:answer];
    id<ODataSecretStoring> secrets = tokens ?: (id<ODataSecretStoring>)[[ODataSecretStore alloc] initWithServiceName:@"Logbook sign-in"];
    ODataSignIn *signIn = [[ODataSignIn alloc] initWithServiceRoot:serviceRoot secrets:secrets];
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
