// An inspection's answers, in the Records tab's Inspection form
// (MainWindow.xib): RecordInspection's repeat of them, a view of the form
// like the rest of the tab (LBFormValues.h). What it keeps is the model's:
// an inspection being entered, or whose checklist changes, has an answer
// for each question of its checklist, its rows in the questions' order; the
// answers to another checklist's questions are deleted (the model allows
// none). A yes-or-no question's answer says Yes or No (the form's list), an
// any-of one chooses its question's options (the form's choices for the
// row), either with a note.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBMainWindowController, Inspection;

NS_ASSUME_NONNULL_BEGIN

@interface LBAnswersController : NSObject
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
// The form's rows of answers, as the tab's table shows them.
@property (nonatomic, weak) IBOutlet NSArrayController *answers;
// The chosen answer's question's options, the form's choices for its row:
// those selected, its options.
@property (nonatomic, weak) IBOutlet NSArrayController *answerOptions;
// The inspection chosen (nil when the record chosen is none), or what the
// server has of it read again.
- (void)showInspection:(nullable Inspection *)inspection;
@end

NS_ASSUME_NONNULL_END
