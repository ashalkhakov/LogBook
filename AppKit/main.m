// Logbook on AppKit (macOS and GNUstep). MainMenu.xib makes the rest.
//
//   Logbook -LBServer logbook.example.com      the server (else asked for)
//   Logbook --self-test <server root>          the app driven from within
//                                              (LBSelfTest.h)

#import <AppKit/AppKit.h>
#import "LBSelfTest.h"

int main(int argc, const char *argv[]) {
    for (int i = 1; i + 1 < argc; i++)
        if (!strcmp(argv[i], "--self-test")) {
            LBSelfTestRoot = [NSURL URLWithString:@(argv[i + 1])];
            /* A server with no sign-in: the user the app is, unless named. */
            [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"LBUser": @"self-test@example.org" }];
        }
    return NSApplicationMain(argc, argv);
}
