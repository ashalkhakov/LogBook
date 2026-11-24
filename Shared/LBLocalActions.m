#import "LBLocalActions.h"
#import "LBProcedures.h"
#import "LBStockProcedures.h"

static NSError *LBActionError(NSString *text) {
    return [NSError errorWithDomain:LBProceduresErrorDomain code:0 userInfo:@{ NSLocalizedDescriptionKey: text }];
}

/* A quantity as given: a number, or a decimal string. */
static NSDecimalNumber *LBQuantityOf(id value) {
    if ([value isKindOfClass:[NSDecimalNumber class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [NSDecimalNumber decimalNumberWithDecimal:[value decimalValue]];
    if ([value isKindOfClass:[NSString class]]) {
        NSDecimalNumber *parsed = [NSDecimalNumber decimalNumberWithString:value locale:@{ NSLocaleDecimalSeparator: @"." }];
        return parsed == [NSDecimalNumber notANumber] ? nil : parsed;
    }
    return nil;
}

/* Lines as Ship, Receive and Return take them: {"<line id>": quantity}. */
static NSDictionary<NSUUID *, NSDecimalNumber *> *LBLinesOf(id lines) {
    if (![lines isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *read = [NSMutableDictionary dictionary];
    for (id key in lines) {
        NSUUID *uuid = [key isKindOfClass:[NSUUID class]] ? key : [key isKindOfClass:[NSString class]] ? [[NSUUID alloc] initWithUUIDString:key] : nil;
        NSDecimalNumber *quantity = LBQuantityOf(lines[key]);
        if (!uuid || !quantity) return nil;
        read[uuid] = quantity;
    }
    return read;
}

static id LBByID(NSManagedObjectContext *context, Class cls, id text) {
    NSUUID *uuid = [text isKindOfClass:[NSUUID class]] ? text : [text isKindOfClass:[NSString class]] ? [[NSUUID alloc] initWithUUIDString:text] : nil;
    if (!uuid) return nil;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = [NSPredicate predicateWithFormat:@"id == %@", uuid];
    return [[context executeFetchRequest:fetch error:NULL] firstObject];
}

/* A distance unit by its code; nil for none. */
static DistanceUnit *LBUnitOf(NSManagedObjectContext *context, id code) {
    if (![code isKindOfClass:[NSString class]] || ![code length]) return nil;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([DistanceUnit class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"code == %@", code];
    return [[context executeFetchRequest:fetch error:NULL] firstObject];
}

/* A parameter, nil for none or null. */
static id LBGiven(NSDictionary *parameters, NSString *name) {
    id value = parameters[name];
    return value == [NSNull null] ? nil : value;
}

@implementation LBLocalActions

+ (id)performAction:(NSString *)name on:(NSManagedObject *)object parameters:(NSDictionary *)p by:(User *)user error:(NSError **)error {
    NSManagedObjectContext *context = object.managedObjectContext;
    NSDate *now = [NSDate date];
    NSDate *day = LBGiven(p, @"Day") ?: now;
    if ([object isKindOfClass:[Schedule class]]) {
        Schedule *schedule = (Schedule *)object;
        if ([name isEqualToString:@"Start"]) {
            return [schedule lb_startFrom:LBGiven(p, @"LastDoneAt") mileage:LBQuantityOf(LBGiven(p, @"LastDoneMileage"))
                                     unit:LBUnitOf(context, LBGiven(p, @"LastDoneMileageUnit")) by:user at:now error:error];
        }
        if ([name isEqualToString:@"Continue"]) {
            return [schedule lb_continueWithTask:LBGiven(p, @"Task") expenseKind:LBGiven(p, @"ExpenseKind") checklist:LBGiven(p, @"Checklist")
                                        interval:LBQuantityOf(LBGiven(p, @"Interval")) unit:LBUnitOf(context, LBGiven(p, @"IntervalUnit"))
                                          months:(int32_t)[LBGiven(p, @"Months") integerValue] note:LBGiven(p, @"Note") by:user at:now
                                       cancelled:NULL error:error];
        }
    }
    if ([object isKindOfClass:[Reminder class]]) {
        Reminder *reminder = (Reminder *)object;
        if ([name isEqualToString:@"Complete"]) {
            Reminder *next = nil;
            return [reminder lb_completeByEvent:LBGiven(p, @"Event") next:&next error:error] ? (next ?: (id)[NSNull null]) : nil;
        }
        if ([name isEqualToString:@"Reschedule"]) {
            return [reminder lb_rescheduleToDate:LBGiven(p, @"DueDate") mileage:LBQuantityOf(LBGiven(p, @"DueMileage"))
                                            unit:LBUnitOf(context, LBGiven(p, @"DueMileageUnit")) note:LBGiven(p, @"Note") by:user at:now
                                           error:error];
        }
        if ([name isEqualToString:@"Cancel"]) {
            Reminder *replacement = nil;
            return [reminder lb_cancelOn:LBGiven(p, @"CancelDate") replacementDueDate:LBGiven(p, @"ReplacementDueDate")
                                 mileage:LBQuantityOf(LBGiven(p, @"ReplacementDueMileage"))
                                    unit:LBUnitOf(context, LBGiven(p, @"ReplacementDueMileageUnit")) by:user at:now
                             replacement:&replacement error:error]
                       ? (replacement ?: (id)[NSNull null]) : nil;
        }
    }
    if ([object isKindOfClass:[Record class]] && [name isEqualToString:@"Discard"]) {
        return [(Record *)object lb_discardKeepingNextReminders:LBGiven(p, @"KeepNextReminder") error:error] ? [NSNull null] : nil;
    }
    if ([object isKindOfClass:[SaleOrder class]]) {
        SaleOrder *sale = (SaleOrder *)object;
        if ([name isEqualToString:@"Confirm"]) return [sale lb_confirm:error] ? sale : nil;
        if ([name isEqualToString:@"Close"]) return [sale lb_close:error] ? sale : nil;
        if ([name isEqualToString:@"Cancel"]) return [sale lb_cancel:error] ? sale : nil;
        if ([name isEqualToString:@"Reopen"]) return [sale lb_reopen:error] ? sale : nil;
        if ([name isEqualToString:@"ExpandKits"]) return [sale lb_expandKits:error] ? sale : nil;
        NSDictionary *lines = LBLinesOf(LBGiven(p, @"Lines"));
        if ([name isEqualToString:@"Ship"] && lines) {
            return [sale lb_shipLines:lines from:LBGiven(p, @"From") on:day by:user at:now error:error];
        }
        if ([name isEqualToString:@"Return"] && lines) {
            return [sale lb_returnLines:lines at:LBGiven(p, @"At") on:day reason:LBGiven(p, @"Reason") ?: @"Other" note:LBGiven(p, @"Note")
                                     by:user at:now error:error];
        }
    }
    if ([object isKindOfClass:[PurchaseOrder class]]) {
        PurchaseOrder *purchase = (PurchaseOrder *)object;
        if ([name isEqualToString:@"Confirm"]) return [purchase lb_confirm:error] ? purchase : nil;
        if ([name isEqualToString:@"Close"]) return [purchase lb_close:error] ? purchase : nil;
        if ([name isEqualToString:@"Cancel"]) return [purchase lb_cancel:error] ? purchase : nil;
        if ([name isEqualToString:@"Reopen"]) return [purchase lb_reopen:error] ? purchase : nil;
        NSDictionary *lines = LBLinesOf(LBGiven(p, @"Lines"));
        if ([name isEqualToString:@"Receive"] && lines) {
            return [purchase lb_receiveLines:lines at:LBGiven(p, @"At") on:day by:user at:now error:error];
        }
        if ([name isEqualToString:@"Return"] && lines) {
            return [purchase lb_returnLines:lines from:LBGiven(p, @"From") on:day reason:LBGiven(p, @"Reason") ?: @"Other"
                                       note:LBGiven(p, @"Note") by:user at:now error:error];
        }
    }
    if ([object isKindOfClass:[StockItem class]]) {
        StockItem *item = (StockItem *)object;
        NSDecimalNumber *quantity = LBQuantityOf(LBGiven(p, @"Quantity"));
        if ([name isEqualToString:@"Transfer"] && quantity) {
            return [item lb_transfer:quantity from:LBGiven(p, @"From") to:LBGiven(p, @"To") by:user at:now error:error];
        }
        if ([name isEqualToString:@"Adjust"] && quantity) {
            return [item lb_adjust:quantity at:LBGiven(p, @"At") reason:LBGiven(p, @"Reason") ?: @"Other" note:LBGiven(p, @"Note")
                                by:user at:now error:error];
        }
        NSDecimalNumber *batches = LBQuantityOf(LBGiven(p, @"Batches"));
        if ([name isEqualToString:@"Assemble"] && batches) {
            return [item lb_assemble:batches at:LBGiven(p, @"At") on:day disassemble:[LBGiven(p, @"Disassemble") boolValue] by:user
                                  at:now error:error];
        }
    }
    if ([object isKindOfClass:[Warehouse class]]) {
        Warehouse *warehouse = (Warehouse *)object;
        if ([name isEqualToString:@"Count"]) {
            NSMutableArray *counted = [NSMutableArray array];
            for (NSDictionary *said in LBGiven(p, @"Found") ?: @[]) {
                StockItem *item = LBByID(context, [StockItem class], said[@"Item"]);
                Location *place = LBByID(context, [Location class], said[@"Location"]);
                NSDecimalNumber *quantity = LBQuantityOf(said[@"Quantity"]);
                if (!item || !place || !quantity) {
                    if (error) *error = LBActionError(@"What was found is of this catalog's items, at its places.");
                    return nil;
                }
                [counted addObject:[LBCounted countedItem:item at:place quantity:quantity]];
            }
            return [warehouse lb_countLocation:LBGiven(p, @"Location") found:counted on:day by:user at:now error:error];
        }
        if ([name isEqualToString:@"Reorder"]) return [warehouse lb_reorderOn:day skipped:NULL error:error];
    }
    if (error) *error = LBActionError([NSString stringWithFormat:@"%@ is no action of a %@, or its parameters are not so.", name, object.entity.name]);
    return nil;
}

@end
