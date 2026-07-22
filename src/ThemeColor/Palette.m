//
//  Palette.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "ThemeColor/Palette.h"
#import <objc/runtime.h>

@protocol AEColorPalette <NSObject>
- (UIColor*)backgroundColor;
@end

@interface TAETwitterColorPaletteSettingInfo : NSObject
- (id<AEColorPalette>)colorPalette;
@end

@interface TAEColorSettings : NSObject
+ (instancetype)sharedSettings;
- (TAETwitterColorPaletteSettingInfo*)currentColorPalette;
@end

@implementation Palette

+ (TAETwitterColorPaletteSettingInfo*)currentPaletteInfo {
    Class settingsClass = objc_getClass("TAEColorSettings");
    if (![settingsClass respondsToSelector:@selector(sharedSettings)]) {
        return nil;
    }

    id settings = [settingsClass sharedSettings];
    if (![settings respondsToSelector:@selector(currentColorPalette)]) {
        return nil;
    }

    return [settings currentColorPalette];
}

+ (UIColor*)currentBackgroundColor {
    TAETwitterColorPaletteSettingInfo* info = [self currentPaletteInfo];
    if ([info respondsToSelector:@selector(colorPalette)]) {
        id<AEColorPalette> palette = [info colorPalette];
        if ([palette respondsToSelector:@selector(backgroundColor)]) {
            UIColor* background = [palette backgroundColor];
            if (background) {
                return background;
            }
        }
    }
    return [UIColor systemBackgroundColor];
}

@end
