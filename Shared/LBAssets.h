// Assets as Stock makes them (docs/CSDP.md, A unit that is an asset):
// every asset a unit of a product, its make, model and serial the
// product's and the unit's. Declared apart from the stock procedures
// (LBStockProcedures.h, which carries them out), for what shows an asset.

#pragma once
#import <CoreData/CoreData.h>
#import "Asset+CoreDataClass.h"
#import "StockUnit+CoreDataClass.h"
#import "User+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

@interface Asset (LBStock)
// Its make, model and serial: its product's maker and name, its unit's
// serial number (a vehicle's VIN). Set, the product's and the unit's are:
// every asset of the product has the make and model it is given.
@property (nonatomic, copy, nullable) NSString *lb_make;
@property (nonatomic, copy, nullable) NSString *lb_model;
@property (nonatomic, copy, nullable) NSString *lb_serial;
// Whether it has no meter (a bicycle): set, its meter unit cleared;
// cleared, its meter counts in its owner's unit of distance (km, else).
@property (nonatomic) BOOL lb_hasNoMeter;
@end

// A new asset, as Stock makes one (docs/CSDP.md, A unit that is an
// asset): its product, a stock item of the owner's catalog (their first,
// by name; "My assets" made where they have none) made by the maker and
// named the model, found so, else made; a unit of it, with its serial
// (a vehicle's VIN); bought from the seller (a supplier of that name,
// "Previous owner" where none is said, made where the catalog has none)
// on the day for the price, a purchase of one, confirmed and received at
// the catalog's first location; or, where the price is not known, come
// in by an opening-stock move on the day; then put in service, a move out
// of stock made for the asset. The asset is new, of the class (Asset or a
// subclass: Vehicle), owned by the owner, its unit set; a vehicle metered
// in the owner's unit of distance (km, where they say none: one with no
// meter is the caller's to say, its meter unit cleared); its name and the
// rest are the caller's. Nothing saved. Refused as the order's procedures
// refuse.
FOUNDATION_EXPORT __kindof Asset *_Nullable LBMakeAsset(Class cls, User *owner, NSString *make, NSString *model,
                                                        NSString *_Nullable serial, NSDate *day,
                                                        NSDecimalNumber *_Nullable price, NSString *_Nullable currency,
                                                        NSString *_Nullable seller, NSError **error);
// A new asset of a new product of its own, named so, its maker not said:
// one being entered, whose make and model the user types next (changing
// its product's, which no other asset is of). Come in by an opening-stock
// move on the day, put in service, as LBMakeAsset does.
FOUNDATION_EXPORT __kindof Asset *_Nullable LBMakeNewAsset(Class cls, User *owner, NSString *name, NSDate *day, NSError **error);

// A store from before assets (v0.7, its vehicles no assets, no units):
// whether it is one, by the model it was saved with.
FOUNDATION_EXPORT BOOL LBIsStoreBeforeAssets(NSString *type, NSURL *url, NSDictionary *_Nullable options);
// Such a store migrated, once, as the server opens it (docs/CSDP.md, A
// unit that is an asset): to the model with nothing in it a must (Core
// Data's migration, inferred), each vehicle then made a unit of its
// product, found in its owner's catalog by its make and model or made,
// bought as it was acquired (or come in by an opening move where its price
// is not known), put in service, metered in its readings' unit; the
// units' dimensions seeded; the sale's kind 'Sale'. Saved, its rules
// kept; the store is then opened as any is, migrated on to the model.
// Any other store: nothing done, YES.
FOUNDATION_EXPORT BOOL LBMigrateStoreBeforeAssets(NSString *type, NSURL *url, NSManagedObjectModel *model,
                                                  NSDictionary *_Nullable options, NSError **error);

NS_ASSUME_NONNULL_END
