//
//  AppIconCell.h
//  BHTwitter
//
//  Created by Bandar Alruwaili on 10/12/2023.
//
//  Styling mirrors the app's native AppIconCell.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppIconCell : UICollectionViewCell

- (void)configureWithImage:(nullable UIImage*)image
                    active:(BOOL)active
               accentColor:(UIColor*)accentColor;

+ (NSString*)reuseIdentifier;

@end

NS_ASSUME_NONNULL_END
