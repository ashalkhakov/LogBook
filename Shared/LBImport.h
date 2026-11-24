#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class Vehicle, User, ORMForm;

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const LBImportErrorDomain;

/* A save as the app saves a form's changes (the store's: automatic
   completion, the model's rules, then save:). */
typedef BOOL (^LBImportSaving)(NSManagedObjectContext *context, NSError **error);

/* Another app's export read, then entered into a vehicle of Logbook's
   through the model's own forms (RecordFillUp, RecordService, ...): what a
   user would type, refused where typing it would be.

   What the export says that Logbook has no place for is said, in leftOut,
   before anything is made: an import leaves nothing out unless the user
   has been told and said so. What the vehicle already has (a record of the
   kind at the same moment and reading) is passed over, so an export can be
   imported again.

   Drivvo: its CSV export, a section per kind (##Vehicle, ##Refuelling,
   ##Service), each with a header row; times in the user's time zone,
   amounts in the user's currency (Drivvo's export says neither). */
@interface LBImport : NSObject

/* The export at the URL, read; nil and why where it is none Logbook
   reads. */
+ (nullable instancetype)importOfFile:(NSURL *)file error:(NSError **)error;
+ (nullable instancetype)importOfData:(NSData *)data named:(NSString *)name error:(NSError **)error;

/* Whose export: "Drivvo". */
@property (nonatomic, readonly, copy) NSString *source;
/* The vehicles the export is of, as it names them. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *vehicleNames;
/* How many records it has, of each kind ("fill-ups": 10). */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *counts;

/* Said once the import has been planned against the vehicle: each thing
   of the export Logbook has no place for ("Refuelling 3: its payment
   method 'Card'"). */
@property (nonatomic, readonly, copy) NSArray<NSString *> *leftOut;

/* The forms the records are entered through, by name (ORMForm
   formNamed: where nil). */
@property (nonatomic, copy, nullable) ORMForm *_Nullable (^formNamed)(NSString *name, NSError **error);

/* What it would make of the vehicle's records, the user entering them:
   leftOut said; NO and why where the export cannot go into it at all (a
   driver who does not drive it, a unit Logbook has not). */
- (BOOL)planForVehicle:(Vehicle *)vehicle by:(User *)user error:(NSError **)error;

/* Planned, then entered, each record its form's save: made, those of it
   the vehicle had already passed over. Stops at the first refused, saying
   which record and why; those before it stay made. */
- (BOOL)importIntoVehicle:(Vehicle *)vehicle
                       by:(User *)user
                  context:(NSManagedObjectContext *)context
                   saving:(LBImportSaving)saving
                     made:(NSUInteger *_Nullable)made
                  skipped:(NSUInteger *_Nullable)skipped
                    error:(NSError **)error;

@end

/* RFC 4180 CSV: rows of fields, quoted or not, "" an escaped quote,
   CRLF or LF; a blank line an empty row. */
NSArray<NSArray<NSString *> *> *LBCSVRows(NSString *text);

NS_ASSUME_NONNULL_END
