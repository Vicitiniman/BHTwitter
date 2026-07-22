//
//  CustomTabBarPreviewCell.h
//  NeoFreeBird
//
//  The bottom tab-bar preview cell, mirroring the native
//  TabCustomizationSelectedItemCell (a bare icon in a shadow box).
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CustomTabBarPreviewCell : UICollectionViewCell

- (void)configureWithImageName:(nullable NSString*)imageName;

+ (NSString*)reuseIdentifier;

@end

NS_ASSUME_NONNULL_END
