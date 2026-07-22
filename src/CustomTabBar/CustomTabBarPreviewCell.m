//
//  CustomTabBarPreviewCell.m
//  NeoFreeBird
//

#import "CustomTabBarPreviewCell.h"
#import <objc/runtime.h>
#import "CustomTabBarNativeColors.h"

@interface UIImage (TFNAdditions)
+ (id)tfn_vectorImageNamed:(id)arg1
                  fitsSize:(struct CGSize)arg2
                 fillColor:(id)arg3;
@end

@interface CustomTabBarPreviewCell ()
@property (nonatomic, strong) UIView* shadowBox;
@property (nonatomic, strong) UIImageView* iconView;
@end

@implementation CustomTabBarPreviewCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 32pt shadow host, matching the native selected-item cell.
        self.shadowBox = [UIView new];
        self.shadowBox.translatesAutoresizingMaskIntoConstraints = NO;
        self.shadowBox.layer.shadowOffset = CGSizeMake(0, 2);
        self.shadowBox.layer.shadowRadius = 4;
        self.shadowBox.layer.shadowOpacity = 0;
        self.shadowBox.layer.shadowColor = CustomTabBarShadowColor().CGColor;
        [self.contentView addSubview:self.shadowBox];

        self.iconView = [UIImageView new];
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.shadowBox addSubview:self.iconView];

        [NSLayoutConstraint activateConstraints:@[
            [self.shadowBox.centerXAnchor
                constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.shadowBox.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.shadowBox.widthAnchor constraintEqualToConstant:32],
            [self.shadowBox.heightAnchor constraintEqualToConstant:32],

            [self.iconView.centerXAnchor
                constraintEqualToAnchor:self.shadowBox.centerXAnchor],
            [self.iconView.centerYAnchor
                constraintEqualToAnchor:self.shadowBox.centerYAnchor],
            [self.iconView.widthAnchor constraintEqualToConstant:24],
            [self.iconView.heightAnchor constraintEqualToConstant:24]
        ]];
    }
    return self;
}

- (void)configureWithImageName:(NSString*)imageName {
    if (imageName.length) {
        self.iconView.image =
            [UIImage tfn_vectorImageNamed:imageName
                                 fitsSize:CGSizeMake(24, 24)
                                fillColor:CustomTabBarIconColor()];
    } else {
        self.iconView.image = nil;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
}

+ (NSString*)reuseIdentifier {
    return @"CustomTabBarPreviewCell";
}

@end
