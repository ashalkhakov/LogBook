// Whether two selectors are the same (an action and a @selector()). Not
// ==: on GNUstep (libobjc2) the action a XIB gives and the compiler's
// @selector() of the same name are different pointers. Not sel_isEqual
// either: on macOS it is declared in <objc/runtime.h> only, whose
// Category type the model's Category class clashes with.

#import <Foundation/Foundation.h>
#include <string.h>

static inline BOOL LBSameSelector(SEL a, SEL b) {
    if (a == b) return YES;
    return a && b && strcmp(sel_getName(a), sel_getName(b)) == 0;
}
