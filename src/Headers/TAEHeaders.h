//
//  TAEHeaders.h
//  BHTwitter
//
//  Created by BandarHelal
//

#import <UIKit/UIKit.h>

// The font group (TAEStandardFontGroup on older versions) is
// TFNUIDefaultFontGroup in 12.3.
@interface TFNUIDefaultFontGroup : NSObject
+ (instancetype)sharedFontGroup;
- (UIFont*)headline2BoldFont;
// The five root builders every named font getter dispatches through.
- (UIFont*)fontOfSize:(CGFloat)size;
- (UIFont*)mediumFontOfSize:(CGFloat)size;
- (UIFont*)boldFontOfSize:(CGFloat)size;
- (UIFont*)heavyFontOfSize:(CGFloat)size;
- (UIFont*)monospacedDigitFontOfSize:(CGFloat)size weight:(CGFloat)weight;
@end

// X 12.9's SwiftUI text and newer timeline surfaces use this catalog instead
// of TFNUIDefaultFontGroup.
@interface XFontCatalog : NSObject
+ (UIFont*)fontForToken:(NSInteger)token;
+ (UIFont*)customFontOfSize:(CGFloat)size
                    weight:(NSInteger)weight
     scalesWithDynamicType:(BOOL)scalesWithDynamicType;
+ (UIFont*)spoofingResistantUsernameFontForToken:(NSInteger)token;
+ (UIFont*)monospaceFixedFontOfSize:(CGFloat)size;
+ (UIFont*)contentFontWithOffset:(CGFloat)offset
                          weight:(NSInteger)weight;
+ (UIFont*)tabularDigitsFontOfSize:(CGFloat)size weight:(CGFloat)weight;
+ (void)resetCachedFonts;
@end

@protocol TAEColorPalette
- (id)colorPalette;
- (UIColor*)primaryColorForOption:(NSUInteger)colorOption;
@end

@interface TAETwitterColorPaletteSettingInfo : NSObject
@property (readonly, nonatomic) id<TAEColorPalette> colorPalette;
@property (readonly, nonatomic) _Bool isDark;
@end

@interface TAEColorSettings : NSObject
@property (retain, nonatomic)
    TAETwitterColorPaletteSettingInfo* currentColorPalette;
- (void)setPrimaryColorOption:(NSInteger)colorOption;
+ (instancetype)sharedSettings;
@end

// Applies the TAE color options above to the UI
@interface T1ColorSettings : NSObject
+ (void)_t1_applyPrimaryColorOption;
+ (void)_t1_updateOverrideUserInterfaceStyle;
@end
