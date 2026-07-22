// AppIconItem.m
// BHTwitter
//

#import "AppIconItem.h"

@implementation AppIconItem

- (instancetype)initWithBundleIconName:(NSString*)iconName
                         iconFileNames:(NSArray<NSString*>*)files
                         isPrimaryIcon:(BOOL)isPrimary {
    if (self = [super init]) {
        _bundleIconName = [iconName copy];
        _bundleIconFiles = [files copy];
        _isPrimaryIcon = isPrimary;
    }
    return self;
}

@end
