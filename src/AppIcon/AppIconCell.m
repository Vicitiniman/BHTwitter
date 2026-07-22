//
//  AppIconCell.m
//  BHTwitter
//
//  Created by Bandar Alruwaili on 10/12/2023.
//

#import "AppIconCell.h"
#import <QuartzCore/QuartzCore.h>

// The native cell rounds the icon to width / 4.491 (~22.27%).
static const CGFloat kAppIconCornerDivisor = 4.491;

@interface UIImage (TFNAdditions)
+ (id)tfn_vectorImageNamed:(id)arg1
                  fitsSize:(struct CGSize)arg2
                 fillColor:(id)arg3;
@end

@interface UIColor (NativeTokens)
+ (id)tfnuiColors;
@end

@interface NSObject (NativeTokens)
- (UIColor*)dividerColor;
@end

// The native icon border / unselected indicator use tfnuiColors.dividerColor.
static UIColor* AppIconDividerColor(void) {
    id colors = [UIColor respondsToSelector:@selector(tfnuiColors)]
                    ? [UIColor tfnuiColors]
                    : nil;
    if (colors && [colors respondsToSelector:@selector(dividerColor)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIColor* divider = [colors performSelector:@selector(dividerColor)];
#pragma clang diagnostic pop
        if ([divider isKindOfClass:[UIColor class]]) {
            return divider;
        }
    }
    return [UIColor separatorColor];
}

// The 24pt selection indicator: a filled check-circle when active, an outline
// circle otherwise. Uses the app's own vector art, falling back to SF Symbols.
static UIImage* AppIconIndicator(BOOL active, UIColor* accentColor) {
    UIColor* fill = active ? accentColor : AppIconDividerColor();
    NSString* vectorName = active ? @"checkmark_circle_fill_white" : @"circle";
    UIImage* image = [UIImage tfn_vectorImageNamed:vectorName
                                          fitsSize:CGSizeMake(24, 24)
                                         fillColor:fill];
    if (!image) {
        UIImage* symbol = [UIImage
            systemImageNamed:(active ? @"checkmark.circle.fill" : @"circle")];
        image = [symbol imageWithTintColor:fill
                             renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    return image;
}

@interface AppIconCell ()
@property (nonatomic, strong) UIImageView* iconView;
@property (nonatomic, strong) UIImageView* checkView;
@end

@implementation AppIconCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;

        self.iconView = [UIImageView new];
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        self.iconView.clipsToBounds = YES;
        self.iconView.layer.cornerCurve = kCACornerCurveContinuous;
        self.iconView.layer.borderColor = AppIconDividerColor().CGColor;
        self.iconView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.iconView.accessibilityIgnoresInvertColors = YES;
        [self.contentView addSubview:self.iconView];

        self.checkView = [UIImageView new];
        self.checkView.translatesAutoresizingMaskIntoConstraints = NO;
        self.checkView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:self.checkView];

        [NSLayoutConstraint activateConstraints:@[
            [self.iconView.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor],
            [self.iconView.leadingAnchor
                constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.iconView.trailingAnchor
                constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.iconView.heightAnchor
                constraintEqualToAnchor:self.contentView.widthAnchor],

            [self.checkView.centerXAnchor
                constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.checkView.topAnchor
                constraintEqualToAnchor:self.iconView.bottomAnchor
                               constant:14],
            [self.checkView.widthAnchor constraintEqualToConstant:24],
            [self.checkView.heightAnchor constraintEqualToConstant:24]
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.iconView.layer.cornerRadius =
        round(CGRectGetWidth(self.iconView.bounds) / kAppIconCornerDivisor);
}

- (void)configureWithImage:(UIImage*)image
                    active:(BOOL)active
               accentColor:(UIColor*)accentColor {
    self.iconView.image = image;
    self.iconView.layer.borderColor = AppIconDividerColor().CGColor;
    self.checkView.image = AppIconIndicator(active, accentColor);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
}

+ (NSString*)reuseIdentifier {
    return @"appicon";
}

@end
