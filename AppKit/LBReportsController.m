#import "LBReportsController.h"
#import "LBMainWindowController.h"
#import "LBReportData.h"
#import "LBDisplay.h"

/* The order the picker offers them in: the most asked for first. */
static NSString * const LBReportNames[] = { @"CostsByMonth", @"Fuel", @"Logbook" };

@implementation LBReportsController {
    NSArray<NSURL *> *_reports;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    NSMutableArray *reports = [NSMutableArray array];
    for (NSUInteger i = 0; i < sizeof LBReportNames / sizeof *LBReportNames; i++) {
        NSURL *url = [[NSBundle mainBundle] URLForResource:LBReportNames[i] withExtension:@"rdl"];
        if (url) [reports addObject:url];
    }
    _reports = reports;
    _viewer = [[RDLReportViewController alloc] init];
    _viewer.dataSource = self;
    NSView *view = _viewer.view;
    view.frame = _reportArea.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_reportArea addSubview:view];
    [_reportPicker removeAllItems];
    for (NSUInteger i = 0; i < reports.count; i++) {
        NSString *xml = [NSString stringWithContentsOfURL:reports[i] encoding:NSUTF8StringEncoding error:NULL];
        RDLReport *report = xml ? [RDLParser reportFromXMLString:xml error:NULL] : nil;
        [_reportPicker addItemWithTitle:report.name.length ? report.name : [reports[i] URLByDeletingPathExtension].lastPathComponent];
        _reportPicker.lastItem.tag = (NSInteger)i;
    }
}

- (IBAction)chooseReport:(id)sender {
    NSInteger index = _reportPicker.selectedTag;
    if (index < 0 || index >= (NSInteger)_reports.count) return;
    NSError *error = nil;
    if (![_viewer loadURL:_reports[(NSUInteger)index] error:&error]) {
        NSLog(@"Logbook: report %@ not read: %@", _reports[(NSUInteger)index].lastPathComponent, error.localizedDescription);
        return;
    }
    [self vehicleChosen];
}

- (void)vehicleChosen {
    if (!_viewer.report) return;
    Vehicle *vehicle = _windowController.vehicles.selectedObjects.firstObject;
    [_viewer setValue:vehicle.lbTitle ?: @"" forParameter:@"Vehicle"];
}

- (id)rowsForDataSet:(NSString *)dataSetName inReport:(RDLReport *)report parameters:(NSDictionary<NSString *, id> *)parameters {
    LBReportData *data = [[LBReportData alloc] initWithContext:_windowController.context];
    Vehicle *vehicle = _windowController.vehicles.selectedObjects.firstObject;
    NSError *error = nil;
    NSArray *rows = @[];
    if ([dataSetName isEqualToString:@"Costs"]) {
        rows = [data costsByMonth:&error];
    } else if ([dataSetName isEqualToString:@"FillUps"]) {
        rows = vehicle ? [data fillUpsOfVehicle:vehicle error:&error] : @[];
    } else if ([dataSetName isEqualToString:@"Records"]) {
        id from = parameters[@"From"], to = parameters[@"To"];
        rows = vehicle ? [data recordsOfVehicle:vehicle from:[from isKindOfClass:[NSDate class]] ? from : nil
                                             to:[to isKindOfClass:[NSDate class]] ? to : nil]
                       : @[];
    } else {
        return nil;
    }
    if (!rows) NSLog(@"Logbook: %@ not worked out: %@", dataSetName, error.localizedDescription);
    return rows ?: @[];
}

@end
