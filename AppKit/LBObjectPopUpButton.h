// A pop-up of objects to choose one from (a unit, a kind of cost, a tyre
// set, a driver), the same on macOS and GNUstep (whose pop-ups have no
// content binding): the app ships it.
//
// In a XIB, two bindings: choices (the objects: an array controller's
// arrangedObjects, or an array) and chosen (the one chosen: a form's
// selection.<relationship>), which a choice sets. Each is titled by its
// -lbTitle (LBDisplay.h); the first item is "None" where none may be
// chosen (allowsNone, a user defined runtime attribute; default YES).

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LBObjectPopUpButton : NSPopUpButton
@property (nonatomic, copy, nullable) NSArray *choices;
@property (nonatomic, strong, nullable) id chosen;
@property (nonatomic) BOOL allowsNone;
@end

NS_ASSUME_NONNULL_END
