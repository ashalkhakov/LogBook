#import "LBAnswersController.h"
#import "LBMainWindowController.h"
#import "LBDisplay.h"
#import "Inspection+CoreDataClass.h"
#import "Answer+CoreDataClass.h"
#import "Option+CoreDataClass.h"

static void *LBChecklistChanged = &LBChecklistChanged;

static NSArray *LBByPosition(NSSet *objects) {
    return [objects.allObjects sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(position))
                                                                                             ascending:YES] ]];
}

@interface LBAnswerRow ()
- (instancetype)initWithInspection:(Inspection *)inspection question:(Question *)question;
- (Answer *)answer;
- (Answer *)answerMade;
- (void)answerChanged;
@end

@interface LBOptionChoice ()
- (instancetype)initWithOption:(Option *)option row:(LBAnswerRow *)row;
@end

@implementation LBOptionChoice {
    __weak LBAnswerRow *_row;
}

- (instancetype)initWithOption:(Option *)option row:(LBAnswerRow *)row {
    if ((self = [super init])) {
        _option = option;
        _row = row;
    }
    return self;
}

- (NSString *)optionText {
    return _option.optionText ?: @"";
}

- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:[LBOptionChoice class]] && ((LBOptionChoice *)other)->_option == _option;
}

- (NSUInteger)hash {
    return _option.hash;
}

- (BOOL)chosen {
    return [[_row answer].options containsObject:_option];
}

- (void)setChosen:(BOOL)chosen {
    if (chosen == self.chosen) return;
    Answer *answer = [_row answerMade];
    if (chosen) [answer addOptionsObject:_option];
    else [answer removeOptionsObject:_option];
    [_row answerChanged];
}

@end

@implementation LBAnswerRow {
    Inspection *_inspection;
}

- (instancetype)initWithInspection:(Inspection *)inspection question:(Question *)question {
    if ((self = [super init])) {
        _inspection = inspection;
        _question = question;
        NSMutableArray *choices = [NSMutableArray array];
        for (Option *option in LBByPosition(question.options)) [choices addObject:[[LBOptionChoice alloc] initWithOption:option row:self]];
        _choices = choices;
    }
    return self;
}

/* A row is its question's, made again as the answers are read again:
   equal so that the one chosen stays chosen. */
- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:[LBAnswerRow class]] && ((LBAnswerRow *)other)->_question == _question
        && ((LBAnswerRow *)other)->_inspection == _inspection;
}

- (NSUInteger)hash {
    return _question.hash;
}

- (Answer *)answer {
    for (Answer *answer in _inspection.answers) {
        if (answer.question == _question && !answer.isDeleted) return answer;
    }
    return nil;
}

/* Its answer, made when the question is first answered. */
- (Answer *)answerMade {
    Answer *answer = [self answer];
    if (answer) return answer;
    answer = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Answer class])
                                           inManagedObjectContext:_inspection.managedObjectContext];
    answer.inspection = _inspection;
    answer.question = _question;
    return answer;
}

- (void)answerChanged {
    [self willChangeValueForKey:NSStringFromSelector(@selector(answerText))];
    [self didChangeValueForKey:NSStringFromSelector(@selector(answerText))];
}

- (NSString *)questionText {
    return _question.questionText ?: @"";
}

- (BOOL)takesOptions {
    return _question.lbTakesOptions;
}

- (BOOL)isYesOrNo {
    return !_question.lbTakesOptions;
}

- (NSString *)answerText {
    Answer *answer = [self answer];
    if (!self.takesOptions) return answer.yesNo ?: @"";
    NSMutableArray *chosen = [NSMutableArray array];
    for (LBOptionChoice *choice in _choices) {
        if (choice.chosen) [chosen addObject:choice.optionText];
    }
    return [chosen componentsJoinedByString:@", "];
}

- (NSString *)yesNo {
    return [self answer].yesNo ?: @"";
}

- (void)setYesNo:(NSString *)yesNo {
    NSString *said = yesNo.length ? yesNo : nil;
    if ([said isEqualToString:[self answer].yesNo] || (!said && ![self answer].yesNo)) return;
    [self answerMade].yesNo = said;
    [self answerChanged];
}

- (NSString *)note {
    return [self answer].note;
}

- (void)setNote:(NSString *)note {
    NSString *said = note.length ? note : nil;
    if (!said && ![self answer]) return;
    [self answerMade].note = said;
}

@end

@interface LBAnswersController ()
@property (nonatomic, readwrite, copy) NSArray<LBAnswerRow *> *rows;
@end

@implementation LBAnswersController {
    Inspection *_inspection;
}

- (instancetype)init {
    if ((self = [super init])) _rows = @[];
    return self;
}

- (void)dealloc {
    [_inspection removeObserver:self forKeyPath:NSStringFromSelector(@selector(checklist)) context:LBChecklistChanged];
}

- (void)showInspection:(Inspection *)inspection {
    if (inspection != _inspection) {
        NSString *checklist = NSStringFromSelector(@selector(checklist));
        [_inspection removeObserver:self forKeyPath:checklist context:LBChecklistChanged];
        _inspection = inspection;
        [_inspection addObserver:self forKeyPath:checklist options:0 context:LBChecklistChanged];
    }
    [self arrange];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == LBChecklistChanged) [self checklistChanged];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

/* Another checklist chosen: the answers to the one before's questions go.
   The inspection read again (refreshed) says so too, of the checklist it
   has: only a change not saved yet is one. */
- (void)checklistChanged {
    if (!_inspection.changedValues[NSStringFromSelector(@selector(checklist))]) {
        [self arrange];
        return;
    }
    for (Answer *answer in [_inspection.answers copy]) {
        if (answer.question.checklist != _inspection.checklist) [answer.managedObjectContext deleteObject:answer];
    }
    [self arrange];
}

- (void)arrange {
    NSMutableArray *rows = [NSMutableArray array];
    for (Question *question in LBByPosition(_inspection.checklist.questions)) {
        [rows addObject:[[LBAnswerRow alloc] initWithInspection:_inspection question:question]];
    }
    self.rows = rows;
}

@end
