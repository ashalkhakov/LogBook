// Logbook on iOS: the app's delegate (LBiOSApp.h).

#import "LBiOSApp.h"
#import "LBiOSSelfTest.h"
#import "LBSignIn.h"

@implementation LBiOSAppDelegate {
    NSURL *_directory;
    ODataSignIn *_signIn;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray *args = [NSProcessInfo processInfo].arguments;
    NSUInteger i = [args indexOfObject:@"--self-test"];
    if (i != NSNotFound && i + 1 < args.count) LBSelfTestRoot = [NSURL URLWithString:args[i + 1]];
    /* A self-test runs on a store of its own, and starts signed out. */
    if (LBSelfTestRoot) {
        _directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"lb-selftest-%@", [NSProcessInfo processInfo].globallyUniqueString]]
                                isDirectory:YES];
        for (NSString *key in @[ LBServerDefaultsKey, LBEmailDefaultsKey, LBVehicleDefaultsKey ])
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    } else {
        _directory = [LBLocalStore defaultDirectory];
    }
    _window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [self openStore];
    NSString *server = [[NSUserDefaults standardUserDefaults] stringForKey:LBServerDefaultsKey];
    if (server.length) {
        /* Signed in as last time: the tokens kept for it (the Keychain). */
        _signIn = LBSignInTo([NSURL URLWithString:server]);
        [self useSignIn:_signIn email:[[NSUserDefaults standardUserDefaults] stringForKey:LBEmailDefaultsKey]];
    } else {
        [self showSignIn];
    }
    [_window makeKeyAndVisible];
    if (LBSelfTestRoot) LBStartSelfTest(self);
    return YES;
}

- (void)openStore {
    NSError *error = nil;
    _store = [[LBLocalStore alloc] initWithDirectory:_directory modelURL:nil error:&error];
    if (!_store) NSLog(@"Logbook: the logbook does not open: %@", error);
    _phone = _store ? [[LBPhone alloc] initWithStore:_store] : nil;
}

- (void)showSignIn {
    _mainController = nil;
    _signInController = [[LBSignInViewController alloc] init];
    _signInController.delegate = self;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:_signInController];
    navigation.navigationBar.prefersLargeTitles = YES;
    _window.rootViewController = navigation;
}

- (void)useSignIn:(ODataSignIn *)signIn email:(NSString *)email {
    _store.signIn = signIn;
    _store.email = email;
    _store.serviceRoot = signIn.serviceRoot;
    _store.syncInterval = LBSelfTestRoot ? 0 : 60;
    _signInController = nil;
    _mainController = [[LBMainViewController alloc] initWithPhone:_phone];
    _mainController.signOutTarget = self;
    _mainController.signOutAction = @selector(signOut:);
    _window.rootViewController = _mainController;
    [_store sync];
}

- (void)signInViewController:(LBSignInViewController *)controller didConnect:(ODataSignIn *)signIn email:(NSString *)email {
    _signIn = signIn;
    [self useSignIn:signIn email:email];
}

- (IBAction)signOut:(id)sender {
    [_signIn signOut];
    _signIn = nil;
    for (NSString *key in @[ LBServerDefaultsKey, LBVehicleDefaultsKey ]) [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    _store.syncInterval = 0;
    _store.serviceRoot = nil;
    _store = nil;
    _phone = nil;
    [[NSFileManager defaultManager] removeItemAtURL:_directory error:NULL];
    [self openStore];
    [self showSignIn];
}

/* Opened, or back: the server's changes met, what waits sent. */
- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (_store.serviceRoot && !_store.syncing && !LBSelfTestRoot) [_store sync];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([LBiOSAppDelegate class]));
    }
}
