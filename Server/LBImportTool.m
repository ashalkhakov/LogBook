// logbook-import: another app's export (Shared/LBImport.h: Drivvo's CSV)
// imported into a vehicle of a Logbook server's, as the desktop app's
// File > Import… does it: the user's logbook synced down into a store of
// its own (a temporary one), each record entered through the model's form,
// then synced up. The server keeps its rules and its permissions as for
// any device's changes.
//
//   logbook-import -Server https://logbook.example.org/ -Vehicle Golf Drivvo.csv
//   logbook-import -Server http://127.0.0.1:8080/ -Email anna@example.org -Vehicle Golf Drivvo.csv
//
// Settings:
//
//   Server    the server (its address; /odata/ added when missing)
//   Email     who imports, where the server asks for no sign-in; where it
//             asks for one, it is signed in to by its device flow (a code
//             to type at a page), the tokens kept as the desktop's are
//   Vehicle   the vehicle (its name) the records go into: one the user
//             owns, set up already (Drivvo's export has no make or year)
//   LeaveOut  YES: import even though the export says things Logbook has
//             no place for (each is said first; NO, the default, stops)
//   Model, Plans, Forms   the compiled model, its tables, the forms'
//             contracts (default: Logbook.momd, Logbook.ormplans and
//             Forms beside the tool)
//
// Exits 0 when every record is made or was there already and the server
// took them; 1 otherwise, saying why.
#import <Foundation/Foundation.h>
#ifdef _WIN32
#include <conio.h>
#else
#include <unistd.h>
#endif
#import <CoreData/CoreData.h>
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMTables.h>
#import <ODataSync/ODataSignIn.h>
#import <ODataSync/ODataSyncEngine.h>
#import "LBImport.h"
#import "LBLocalStore.h"
#import "LBSignIn.h"
#import "Vehicle+CoreDataClass.h"
#import "User+CoreDataClass.h"

static int LBFail(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static int LBFail(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *said = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    fprintf(stderr, "logbook-import: %s\n", said.UTF8String);
    return 1;
}

/* A file beside the tool, or where the setting says. */
static NSURL *LBBeside(NSString *setting, NSString *name) {
    NSString *given = [[NSUserDefaults standardUserDefaults] stringForKey:setting];
    if (given.length) return [NSURL fileURLWithPath:given];
    NSString *tool = [[NSProcessInfo processInfo].arguments.firstObject stringByResolvingSymlinksInPath];
    return [NSURL fileURLWithPath:[[tool stringByDeletingLastPathComponent] stringByAppendingPathComponent:name]];
}

/* The device flow's code said, and its end waited for. */
@interface LBSigningIn : NSObject <ODataSignInDelegate>
@property (nonatomic) BOOL learnt, done;
@property (nonatomic, strong) NSError *failure;
@end

@implementation LBSigningIn
- (void)signInDidLearn:(ODataSignIn *)signIn {
    _learnt = YES;
}

- (void)signIn:(ODataSignIn *)signIn showCode:(NSString *)code page:(NSURL *)page completePage:(NSURL *)completePage {
    printf("To sign in, open %s and type %s\n", (completePage ?: page).absoluteString.UTF8String, code.UTF8String);
    fflush(stdout);
}

- (void)signInDidFinish:(ODataSignIn *)signIn {
    _done = YES;
}

- (void)signIn:(ODataSignIn *)signIn didFail:(NSError *)error {
    _failure = error;
    _done = YES;
    _learnt = YES;
}
@end

/* A password typed, not shown: getpass where there is one; on Windows,
   key by key from the console (Return ends it, Backspace takes one back). */
static NSString *LBTypedPassword(void) {
#ifdef _WIN32
    fputs("Password: ", stderr);
    fflush(stderr);
    NSMutableString *typed = [NSMutableString string];
    for (;;) {
        int c = _getwch();
        if (c == '\r' || c == '\n' || c == WEOF) break;
        if (c == 3) return nil;
        if (c == '\b') {
            if (typed.length) [typed deleteCharactersInRange:NSMakeRange(typed.length - 1, 1)];
            continue;
        }
        unichar u = (unichar)c;
        [typed appendString:[NSString stringWithCharacters:&u length:1]];
    }
    fputs("\n", stderr);
    return typed;
#else
    char *typed = getpass("Password: ");
    return typed ? @(typed) : nil;
#endif
}

static void LBWaitFor(BOOL (^done)(void)) {
    while (!done()) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

int main(int argc, const char *argv[]) {
    /* A line at a time, piped too: what it says in the order it happens,
       beside what the libraries log. */
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        NSUserDefaults *settings = [NSUserDefaults standardUserDefaults];
        NSArray<NSString *> *arguments = [NSProcessInfo processInfo].arguments;
        /* The file: the last argument that is no setting or a setting's value. */
        NSString *file = nil;
        for (NSUInteger i = 1; i < arguments.count; i++) {
            if ([arguments[i] hasPrefix:@"-"]) {
                i++;
                continue;
            }
            file = arguments[i];
        }
        NSURL *root = LBServiceRootOf([settings stringForKey:@"Server"] ?: @"");
        NSString *named = [settings stringForKey:@"Vehicle"];
        if (!file || !root || !named.length) {
            fprintf(stderr, "usage: logbook-import -Server address [-Email you@example.org] -Vehicle name [-LeaveOut YES] export.csv\n");
            return 2;
        }
        NSError *error = nil;
        LBImport *import = [LBImport importOfFile:[NSURL fileURLWithPath:file] error:&error];
        if (!import) return LBFail(@"%@", error.localizedDescription);
        NSURL *forms = LBBeside(@"Forms", @"Forms");
        import.formNamed = ^ORMForm *(NSString *name, NSError **failure) {
            NSData *data = [NSData dataWithContentsOfURL:[forms URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"ormform"]]
                                                 options:0 error:failure];
            id list = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:failure] : nil;
            return list ? [ORMForm formWithPropertyList:list error:failure] : nil;
        };
        NSData *plans = [NSData dataWithContentsOfURL:LBBeside(@"Plans", @"Logbook.ormplans") options:0 error:&error];
        id list = plans ? [NSPropertyListSerialization propertyListWithData:plans options:0 format:NULL error:&error] : nil;
        ORMTables *tables = list ? [ORMTables tablesWithPropertyList:list error:&error] : nil;
        if (!tables) return LBFail(@"no tables of the model (-Plans): %@", error.localizedDescription);
        [ORMTables registerTables:tables named:@"Logbook"];

        /* Signed in as the server asks. */
        ODataSignIn *signIn = LBSignInTo(root);
        LBSigningIn *signing = [[LBSigningIn alloc] init];
        signIn.delegate = signing;
        [signIn learn];
        LBWaitFor(^BOOL { return signing.learnt; });
        if (signing.failure) return LBFail(@"%@ did not say how to sign in: %@", root, signing.failure.localizedDescription);
        NSString *email = [settings stringForKey:@"Email"];
        if (signIn.kind == ODataSignInPassword && !signIn.isSignedIn) {
            if (!email.length) return LBFail(@"%@ asks for a user and password: say who you are (-Email).", root);
            NSString *typed = LBTypedPassword();
            if (!typed) return LBFail(@"no password typed.");
            [signIn signInWithUser:email password:typed];
            LBWaitFor(^BOOL { return signing.done; });
            if (signing.failure || !signIn.isSignedIn) return LBFail(@"not signed in: %@", signing.failure.localizedDescription ?: @"");
        } else if (signIn.kind != ODataSignInNone && !signIn.isSignedIn) {
            [signIn begin];
            LBWaitFor(^BOOL { return signing.done; });
            if (signing.failure || !signIn.isSignedIn) return LBFail(@"not signed in: %@", signing.failure.localizedDescription ?: @"");
        }
        if (signIn.kind == ODataSignInNone && !email.length) return LBFail(@"%@ asks for no sign-in: say who you are (-Email).", root);

        /* The user's logbook, here. */
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                     [NSString stringWithFormat:@"logbook-import-%@", [NSProcessInfo processInfo].globallyUniqueString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
        LBLocalStore *store = [[LBLocalStore alloc] initWithDirectory:[NSURL fileURLWithPath:path] modelURL:LBBeside(@"Model", @"Logbook.momd")
                                                                error:&error];
        if (!store) return LBFail(@"no store: %@", error.localizedDescription);
        int status = 0;
        @try {
            store.email = email;
            if (signIn.kind != ODataSignInNone) store.signIn = signIn;
            store.serviceRoot = root;
            printf("Reading your logbook from %s…\n", root.absoluteString.UTF8String);
            fflush(stdout);
            if (![store syncAndWait:&error]) return LBFail(@"not synced down: %@", error.localizedDescription);
            User *user = store.user;
            Vehicle *vehicle = nil;
            for (Vehicle *each in user.ownedVehicles) {
                if ([each.vehicleName isEqualToString:named]) vehicle = each;
            }
            if (!vehicle) {
                NSArray *names = [[user.ownedVehicles valueForKey:@"vehicleName"] allObjects];
                return LBFail(@"%@ owns no vehicle named %@ (%@). Add it in Logbook first: Drivvo's export says no make or year.", user.email,
                              named, names.count ? [names componentsJoinedByString:@", "] : @"none");
            }
            printf("%s's export of %s: %s, into %s.\n", import.source.UTF8String, [import.vehicleNames componentsJoinedByString:@", "].UTF8String,
                   import.summary.UTF8String, vehicle.vehicleName.UTF8String);
            if (![import planForVehicle:vehicle by:user error:&error]) return LBFail(@"%@", error.localizedDescription);
            if (import.leftOut.count) {
                printf("Logbook has no place for these, or takes them so:\n");
                for (NSString *each in import.leftOut) printf("  - %s\n", each.UTF8String);
                if (![settings boolForKey:@"LeaveOut"]) return LBFail(@"nothing imported: -LeaveOut YES imports it as said.");
            }
            NSUInteger made = 0, skipped = 0;
            BOOL done = [import importIntoVehicle:vehicle by:user context:store.context
                                          saving:^BOOL(NSManagedObjectContext *context, NSError **failure) { return [store save:failure]; }
                                            made:&made skipped:&skipped error:&error];
            printf("%lu made, %lu there already.\n", (unsigned long)made, (unsigned long)skipped);
            if (!done) status = LBFail(@"%@", error.localizedDescription);
            if (![store syncAndWait:&error])
                return LBFail(@"not synced up: %@. Run it again: what reached the server is passed over, the rest made again.", error.localizedDescription);
            NSArray *refused = store.issues;
            if (refused.count) {
                for (ODataSyncIssue *issue in refused) fprintf(stderr, "  refused by the server: %s\n", issue.message.UTF8String);
                return LBFail(@"the server refused %lu of them.", (unsigned long)refused.count);
            }
            if (!status) printf("Synced: on the server now.\n");
        } @finally {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        }
        return status;
    }
}
