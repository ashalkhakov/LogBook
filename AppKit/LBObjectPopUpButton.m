#import "LBObjectPopUpButton.h"
#import "LBDisplay.h"

static NSString * const LBChoicesBinding = @"choices";
static NSString * const LBChosenBinding = @"chosen";

@implementation LBObjectPopUpButton

+ (void)initialize {
    if (self == [LBObjectPopUpButton class]) {
        [self exposeBinding:LBChoicesBinding];
        [self exposeBinding:LBChosenBinding];
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) [self setUp];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame pullsDown:(BOOL)flag {
    if ((self = [super initWithFrame:frame pullsDown:flag])) [self setUp];
    return self;
}

- (void)setUp {
    _allowsNone = YES;
    self.target = self;
    self.action = @selector(choose:);
    [self rebuild];
}

static NSString *LBTitleOf(id object) {
    return [object respondsToSelector:@selector(lbTitle)] ? [(id<LBTitled>)object lbTitle] : [object description];
}

/* A selection's markers (none, several) are no object. */
static id LBObjectOf(id value) {
    return [value isKindOfClass:[NSManagedObject class]] ? value : nil;
}

- (void)rebuild {
    [self removeAllItems];
    if (_allowsNone) [self addItemWithTitle:@"None"];
    for (id object in _choices) {
        [self addItemWithTitle:LBTitleOf(object)];
        self.lastItem.representedObject = object;
    }
    [self showChosen];
}

- (void)showChosen {
    NSInteger index = _chosen ? [self indexOfItemWithRepresentedObject:_chosen] : -1;
    if (index >= 0) [self selectItemAtIndex:index];
    else if (_allowsNone) [self selectItemAtIndex:0];
    else [self selectItem:nil];
}

/* Listed by title. */
- (void)setChoices:(NSArray *)choices {
    NSSortDescriptor *byTitle = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbTitle)) ascending:YES
                                                               selector:@selector(localizedCaseInsensitiveCompare:)];
    _choices = [choices isKindOfClass:[NSArray class]] ? [choices sortedArrayUsingDescriptors:@[ byTitle ]] : nil;
    [self rebuild];
}

- (void)setChosen:(id)chosen {
    _chosen = LBObjectOf(chosen);
    [self showChosen];
}

- (void)setAllowsNone:(BOOL)allowsNone {
    _allowsNone = allowsNone;
    [self rebuild];
}

/* A choice made: the bound object told. */
- (void)choose:(id)sender {
    _chosen = self.selectedItem.representedObject;
    NSDictionary *info = [self infoForBinding:LBChosenBinding];
    [info[NSObservedObjectKey] setValue:_chosen forKeyPath:info[NSObservedKeyPathKey]];
}

@end
