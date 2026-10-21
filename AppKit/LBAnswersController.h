// An inspection's answers, in the Records tab's Inspection form
// (MainWindow.xib): a row for each question of the checklist it went
// through, in order; a yes-or-no question answered Yes or No, an any-of one
// by the options chosen, either with a note. An Answer is made when a
// question is first answered, as the phone makes one; one to a question of
// another checklist is deleted when the inspection's checklist changes
// (the model allows none).

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBMainWindowController, Inspection, Question, Option;

NS_ASSUME_NONNULL_BEGIN

// An option of an any-of question, chosen or not in its answer.
@interface LBOptionChoice : NSObject
@property (nonatomic, readonly) Option *option;
@property (nonatomic, readonly) NSString *optionText;
@property (nonatomic) BOOL chosen;
@end

// A question of the inspection's checklist, and its answer.
@interface LBAnswerRow : NSObject
@property (nonatomic, readonly) Question *question;
@property (nonatomic, readonly) NSString *questionText;
// The answer said: "Yes", "No", the options chosen; "" before.
@property (nonatomic, readonly) NSString *answerText;
// A yes-or-no question's answer: "Yes", "No", or "" for none yet.
@property (nonatomic, copy) NSString *yesNo;
@property (nonatomic, copy, nullable) NSString *note;
@property (nonatomic, readonly) BOOL takesOptions;
@property (nonatomic, readonly) BOOL isYesOrNo;
@property (nonatomic, readonly, copy) NSArray<LBOptionChoice *> *choices;
@end

@interface LBAnswersController : NSObject
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
// The rows the form's table shows; none when no inspection is chosen.
@property (nonatomic, readonly, copy) NSArray<LBAnswerRow *> *rows;
// The inspection chosen (nil when the record chosen is none), or what the
// server has of it read again.
- (void)showInspection:(nullable Inspection *)inspection;
@end

NS_ASSUME_NONNULL_END
