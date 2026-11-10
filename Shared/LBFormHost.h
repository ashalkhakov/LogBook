// A form ORMKit generates from the model (Model/Logbook.orm's forms, by
// ormtool xforms: <Form>.xhtml, and beside it the table its names stand
// for, <Form>.ormform) as XFormsKit runs it, Logbook answering what it
// asks (ORMKit's docs/FORMS.md, In and out):
//
//   form:read               the object read, or a new one, its given
//                           values in it (the vehicle it is for)
//   form:choices/<name>     a reference's choices (the vehicle's drivers)
//   form:save               the instance written into its object, saved
//
// Either against a context of the model's (the desktop app's, over the
// server; a check's own store), saved as its owner saves, or straight
// against the server's OData service. A save refused is said at the
// fields it is about (XFModel's host errors) and in the form's own words
// for the rest (formMessages). What it answers comes from an ORMFormSession
// (ORMRuntime), the form's contract run, which a view of the app's own runs
// as well. The desktop app's and the checks'; not the iOS app's.

#pragma once
#import <CoreData/CoreData.h>
#import <XFormsKit/XFormsKit.h>

@class ORMForm, ORMFormSession, ODataSignIn;

NS_ASSUME_NONNULL_BEGIN

@interface LBFormHost : NSObject

// The form in the bundle's resources (<name>.xhtml and <name>.ormform),
// given the values it opens with: nil, and why, where it is not there.
- (nullable instancetype)initWithFormNamed:(NSString *)name
                                  inBundle:(NSBundle *)bundle
                                     given:(NSDictionary<NSString *, NSString *> *)given
                                     error:(NSError **)error;
// The same, of the document and its table.
- (instancetype)initWithForm:(ORMForm *)form
                    document:(NSString *)xml
                       given:(NSDictionary<NSString *, NSString *> *)given NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly, strong) ORMForm *form;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *given;
// The form being filled in, which the document's reads, choices and save
// are answered from.
@property (nonatomic, readonly, strong) ORMFormSession *session;

// Against a context of the form's own, on its queue (the main one), saved
// by saving (the app's own way: LBStore's -saveContext:error:), or by the
// context's -save: where it is nil; refused, it is rolled back.
- (void)useContext:(NSManagedObjectContext *)context
            saving:(nullable BOOL (^)(NSManagedObjectContext *context, NSError **error))saving;
// Against the service at the root, its names those of the model's: signed
// in where it asks (signIn), else as anyone.
- (void)useServiceRoot:(NSURL *)root model:(NSManagedObjectModel *)model signIn:(nullable ODataSignIn *)signIn;

// The object the form edits, by its key; nil for a new one.
@property (nonatomic, copy, nullable) NSString *key;

// The form, made to be run: its reads, choices and save answered here.
// nil, and why, where the document is not one XFormsKit runs.
- (nullable XFProcessor *)makeProcessor:(NSError **)error;
@property (nonatomic, readonly, strong, nullable) XFProcessor *processor;

// What the last save said of no one field, said; and what it saved (its
// key), or nil.
@property (nonatomic, readonly, copy) NSArray<NSString *> *formMessages;
@property (nonatomic, readonly, copy, nullable) NSString *savedKey;

// The form's instance, element by element, as XForms holds it.
- (NSDictionary<NSString *, NSString *> *)instance;

@end

NS_ASSUME_NONNULL_END
