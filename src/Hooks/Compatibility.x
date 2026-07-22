#import "HookHelpers.h"
#import "Compatibility/BHTCompatibilityReporter.h"

%ctor {
    // Swift classes and feature modules finish registering after the tweak is
    // loaded.  Delay the first snapshot, then refresh it whenever tab entries
    // are captured.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BHTWriteCompatibilityReport();
    });
}
