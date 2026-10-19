// How the model's objects are shown: what a pick list calls each
// (lbTitle), and a record's kind, day and cost as a list of records shows
// them. Categories on the generated classes, so that windows bind to them.

#pragma once
#import <Foundation/Foundation.h>
#import "Vehicle+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "Record+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"
#import "VolumeUnit+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"
#import "TyreSet+CoreDataClass.h"
#import "Checklist+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

// What a pick list calls an object.
@protocol LBTitled <NSObject>
- (NSString *)lbTitle;
@end

@interface Vehicle (LBDisplay) <LBTitled>
@end
@interface User (LBDisplay) <LBTitled>
@end
@interface DistanceUnit (LBDisplay) <LBTitled>
@end
@interface VolumeUnit (LBDisplay) <LBTitled>
@end
@interface CostKind (LBDisplay) <LBTitled>
@end
@interface TyreSet (LBDisplay) <LBTitled>
@end
@interface Checklist (LBDisplay) <LBTitled>
@end

@interface Record (LBDisplay)
// "Fill-up", "Service", ...: its kind, as a person says it.
@property (nonatomic, readonly) NSString *lbKind;
// When: an event's moment; a tyre set's or a document's day; nil else.
@property (nonatomic, readonly, nullable) NSDate *lbDate;
// That said short: "10/19/26, 8:57 PM", a day without its time.
@property (nonatomic, readonly, nullable) NSString *lbWhen;
// What it cost: "74.10 EUR"; nil when nothing.
@property (nonatomic, readonly, nullable) NSString *lbCost;
// The model's entities a record is of, in the order Add offers them.
+ (NSArray<NSString *> *)lbKinds;
+ (NSString *)lbKindOfEntityNamed:(NSString *)name;
@end

NS_ASSUME_NONNULL_END
