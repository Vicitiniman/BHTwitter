//
//  ColorSwatchControl.h
//  NeoFreeBird
//
//  A single accent-color swatch, cloning the native ColorThemePickerItem swatch:
//  a 36pt filled circle with a 2pt ring at its edge when selected.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ColorSwatchControl : UIControl

@property (nonatomic, assign) NSInteger colorID;

- (void)setSwatchColor:(UIColor*)color;
- (void)setSwatchSelected:(BOOL)selected;

@end

NS_ASSUME_NONNULL_END
