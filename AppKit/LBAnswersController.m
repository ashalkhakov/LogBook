#import "LBAnswersController.h"
#import "LBMainWindowController.h"
#import "Inspection+CoreDataClass.h"
#import "Answer+CoreDataClass.h"
#import "Question+CoreDataClass.h"
#import "Checklist+CoreDataClass.h"

static void *LBChecklistChanged = &LBChecklistChanged;
static void *LBOptionsChosen = &LBOptionsChosen;
static void *LBAnswerChosen = &LBAnswerChosen;

/* An answer's options as its row says them: their texts, joined. */
@interface LBOptionTexts : NSValueTransformer
@end

@implementation LBOptionTexts
+ (Class)transformedValueClass {
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation {
    return NO;
}

- (id)transformedValue:(id)value {
    /* A placeholder's text, as GNUstep gives one, as it is. */
    if ([value isKindOfClass:[NSString class]]) return value;
    NSArray *texts = [[value valueForKey:@"optionText"] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return [texts componentsJoinedByString:@", "] ?: @"";
}
@end

@implementation LBAnswersController {
    Inspection *_inspection;
    BOOL _showing;
}

+ (void)initialize {
    if (self == [LBAnswersController class]) [NSValueTransformer setValueTransformer:[[LBOptionTexts alloc] init] forName:@"LBOptionTexts"];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [_answerOptions addObserver:self forKeyPath:@"selectionIndexes" options:0 context:LBOptionsChosen];
    [_answerOptions addObserver:self forKeyPath:@"arrangedObjects" options:0 context:LBAnswerChosen];
}

- (void)dealloc {
    [_inspection removeObserver:self forKeyPath:NSStringFromSelector(@selector(checklist)) context:LBChecklistChanged];
    [_answerOptions removeObserver:self forKeyPath:@"selectionIndexes" context:LBOptionsChosen];
    [_answerOptions removeObserver:self forKeyPath:@"arrangedObjects" context:LBAnswerChosen];
}

/* Another answer's options listed: those it chose, selected. */
- (void)answerChosen {
    id answer = _answers.selectedObjects.count == 1 ? _answers.selectedObjects.firstObject : nil;
    _showing = YES;
    _answerOptions.selectedObjects = [answer valueForKey:@"options"] ?: @[];
    _showing = NO;
}

/* The options selected, the chosen answer's (AppKit says its options as
   selected, and pushes no selection back). */
- (void)optionsChosen {
    if (_showing) return;
    id answer = _answers.selectedObjects.count == 1 ? _answers.selectedObjects.firstObject : nil;
    NSArray *chosen = _answerOptions.selectedObjects ?: @[];
    if (!answer || [[NSSet setWithArray:[answer valueForKey:@"options"] ?: @[]] isEqualToSet:[NSSet setWithArray:chosen]]) return;
    /* Only while the list is its question's options: while it is being
       changed for another answer, its selection is not this one's. */
    NSArray *theirs = [answer valueForKeyPath:@"choices.options"] ?: @[];
    if (![[NSSet setWithArray:_answerOptions.arrangedObjects ?: @[]] isEqualToSet:[NSSet setWithArray:theirs]] || !theirs.count) return;
    /* And only options of its own question: what GNUstep says of the list
       while it changes can be another answer's (said, to be found). */
    id question = [answer valueForKey:@"question"];
    for (id option in chosen) {
        if ([option valueForKey:@"question"] != question) {
            NSLog(@"LBAnswersController: options of another question not taken: %@ chose %@ of %@; listed %@, its choices %@",
                  [question valueForKey:@"questionText"], [chosen valueForKey:@"optionText"],
                  [[chosen valueForKey:@"question"] valueForKey:@"questionText"],
                  [_answerOptions.arrangedObjects valueForKey:@"optionText"], [theirs valueForKey:@"optionText"]);
            return;
        }
    }
    [answer setValue:chosen forKey:@"options"];
}

- (void)showInspection:(Inspection *)inspection {
    /* The answers in their questions' order. */
    if (!_answers.sortDescriptors.count) {
        _answers.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"question.position" ascending:YES] ];
        _answers.automaticallyRearrangesObjects = YES;
    }
    if (inspection != _inspection) {
        NSString *checklist = NSStringFromSelector(@selector(checklist));
        [_inspection removeObserver:self forKeyPath:checklist context:LBChecklistChanged];
        _inspection = inspection;
        [_inspection addObserver:self forKeyPath:checklist options:0 context:LBChecklistChanged];
    }
    if (_inspection.isInserted) [self answerEachQuestion];
    [_answers rearrangeObjects];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == LBChecklistChanged) [self checklistChanged];
    else if (context == LBOptionsChosen) [self optionsChosen];
    else if (context == LBAnswerChosen) [self answerChosen];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

/* Another checklist chosen: the answers to the one before's questions go,
   and each of its questions has one. The inspection read again
   (refreshed) says so too, of the checklist it has: only a change not
   saved yet is one. */
- (void)checklistChanged {
    if (!_inspection.changedValues[NSStringFromSelector(@selector(checklist))] && !_inspection.isInserted) return;
    for (Answer *answer in [_inspection.answers copy]) {
        if (answer.question.checklist != _inspection.checklist) [answer.managedObjectContext deleteObject:answer];
    }
    [self answerEachQuestion];
}

/* An answer, not yet said, for each question of its checklist that has
   none: the form's rows. */
- (void)answerEachQuestion {
    NSMutableSet *answered = [NSMutableSet set];
    for (Answer *answer in _inspection.answers) {
        if (answer.question && !answer.isDeleted) [answered addObject:answer.question];
    }
    for (Question *question in _inspection.checklist.questions) {
        if ([answered containsObject:question]) continue;
        Answer *answer = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Answer class])
                                                       inManagedObjectContext:_inspection.managedObjectContext];
        answer.id = [NSUUID UUID];
        /* Its question first: the form's rows have it as it is one. */
        answer.question = question;
        answer.inspection = _inspection;
    }
    [_answers rearrangeObjects];
}

@end
