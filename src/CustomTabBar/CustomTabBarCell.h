//
//  CustomTabBarCell.h
//  NeoFreeBird
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CustomTabBarCell : UICollectionViewCell

- (void)configureWithTitle:(nullable NSString*)title
                 imageName:(nullable NSString*)imageName
                  selected:(BOOL)selected
                     fixed:(BOOL)fixed
               accentColor:(UIColor*)accentColor;

+ (NSString*)reuseIdentifier;

@end

NS_ASSUME_NONNULL_END
