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
   amounts in the user's currency (Drivvo's export says neither).

   MainTrack: its store (Maintrack.sqlite, read from a copy): each bike a
   bicycle of the user's (the one of its name, else made), each component
   one of the bike it was first fitted to, each ride a trip, each
   assignment a component change fitting it (retiring the one of its part
   taken off then), each invoice a service, its log entries the tasks; the
   readings worked out from the rides. It makes its own vehicles: the one
   given is not used. */
@interface LBImport : NSObject

/* An InvenTree instance's stock, read over its REST API (api/): its
   categories, locations, companies, parts, supplier and manufacturer
   parts, stock items, purchase orders and their lines, and its stock
   tracking. It goes into a catalog (catalogName), its structure (the top
   locations warehouses, the rest locations in them), its parts items, its
   serialed stock items units, its orders purchase orders (complete:
   closed; placed: confirmed), each item received as InvenTree tracked it
   (where and when) by a receipt of its order, moved after as it was, and
   one bought outside an order found (an opening adjustment) where it first
   was. fetch, where given, answers each request instead of the network (a
   check's fixtures): the path asked (part/?limit=100&offset=0), its JSON. */
+ (nullable instancetype)importOfInvenTree:(NSURL *)root
                                     token:(NSString *)token
                                     fetch:(nullable NSData *_Nullable (^)(NSString *path, NSError **error))fetch
                                     error:(NSError **)error;

/* The export at the URL, read; nil and why where it is none Logbook
   reads. */
+ (nullable instancetype)importOfFile:(NSURL *)file error:(NSError **)error;
+ (nullable instancetype)importOfData:(NSData *)data named:(NSString *)name error:(NSError **)error;

/* Whose export: "Drivvo", "MainTrack". */
@property (nonatomic, readonly, copy) NSString *source;
/* The vehicles the export is of, as it names them. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *vehicleNames;
/* It makes the vehicles its records go into (MainTrack's bikes): none is
   chosen for it. */
@property (nonatomic, readonly) BOOL makesVehicles;
/* How many records it has, of each kind ("fill-ups": 10). */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *counts;
/* Those counts said: "2 fill-ups, 1 service". */
@property (nonatomic, readonly, copy) NSString *summary;

/* Said once the import has been planned against the vehicle: each thing
   of the export Logbook has no place for ("Refuelling 3: its payment
   method 'Card'"). */
@property (nonatomic, readonly, copy) NSArray<NSString *> *leftOut;

/* It brings stock into a catalog (InvenTree's, MainTrack's parts). */
@property (nonatomic, readonly) BOOL makesStock;
/* What its amounts are in, where the export says none of its own (Drivvo's
   export, MainTrack's store: their apps keep the currency in their
   settings): asked as it is imported, the user's at first; nil, the
   user's. Imported again in another, what it made before is said in it
   (an amount there already of the export's, its currency changed). */
@property (nonatomic, copy, nullable) NSString *currency;
// Whether it asks for that: its amounts in no currency of their own.
@property (nonatomic, readonly) BOOL takesACurrency;
// What the last import changed to that currency: records, bikes and parts
// it made before in another.
@property (nonatomic, readonly) NSUInteger recurrenced;
/* The catalog stock goes into (the user's of that name, made where they
   have none): MainTrack's parts "Bike parts" where none is named; an
   InvenTree's must be named. */
@property (nonatomic, copy, nullable) NSString *catalogName;

/* Drivvo's export goes into the user's vehicle it is: by its licence plate
   (case, spaces and dashes aside), else its name, else its model where one
   vehicle only has it. Planned with no vehicle, the one matched; none, a
   new one is made as the import starts, of what the export says (its
   name, else its model; the model, plate, fuel, year), the make and (where
   the export says 0) the year given here, which it says nothing of. */
- (nullable Vehicle *)vehicleOfUser:(User *)user how:(NSString *_Nullable *_Nullable)how;
/* After planning: the vehicle matched (nil: a new one), and how ("by its
   licence plate", "by its model"). */
@property (nonatomic, readonly, strong, nullable) Vehicle *matchedVehicle;
@property (nonatomic, readonly, copy, nullable) NSString *matchedHow;
/* After planning: no vehicle matched, so one is made; the name it takes,
   and the year the export says (0: none). */
@property (nonatomic, readonly) BOOL makesItsVehicle;
@property (nonatomic, readonly, copy, nullable) NSString *madeVehicleName;
@property (nonatomic, readonly) NSInteger exportYear;
/* What the vehicle made takes that the export does not say. */
@property (nonatomic, copy, nullable) NSString *madeVehicleMake;
@property (nonatomic) NSInteger madeVehicleYear;

/* The forms the records are entered through, by name (ORMForm
   formNamed: where nil). */
@property (nonatomic, copy, nullable) ORMForm *_Nullable (^formNamed)(NSString *name, NSError **error);

/* What it would make of the vehicle's records, the user entering them:
   leftOut said; NO and why where the export cannot go into it at all (a
   driver who does not drive it, a unit Logbook has not). */
- (BOOL)planForVehicle:(nullable Vehicle *)vehicle by:(User *)user error:(NSError **)error;

/* Planned, then entered, each record its form's save: made, those of it
   the vehicle had already passed over. Stops at the first refused, saying
   which record and why; those before it stay made. */
- (BOOL)importIntoVehicle:(nullable Vehicle *)vehicle
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
