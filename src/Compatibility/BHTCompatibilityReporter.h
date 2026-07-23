#import <Foundation/Foundation.h>

NSURL* BHTCompatibilityReportURL(void);
void BHTWriteCompatibilityReport(void);
void BHTRecordNavigationEntryClasses(NSArray* entries);
void BHTRecordTimelineItemObservation(id item, NSString* location, BOOL hidden);
void BHTRecordMediaActionObservation(NSString* stage,
                                     NSString* kind,
                                     NSUInteger originalCount,
                                     NSUInteger configuredCount,
                                     NSUInteger mediaEntityCount);
