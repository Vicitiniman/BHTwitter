//
//  CustomTabBarCell.m
//  NeoFreeBird
//
//  Styling mirrors the app's native TabCustomizationViewCell so the editor's
//  tiles match the stock tab-customization screen.
//

#import "CustomTabBarCell.h"
#import <QuartzCore/QuartzCore.h>
#import "Core/TwitterChirpFont.h"
#import "CustomTabBarNativeColors.h"

@interface UIImage (TFNAdditions)
+ (id)tfn_vectorImageNamed:(id)arg1
                  fitsSize:(struct CGSize)arg2
                 fillColor:(id)arg3;
@end

@interface CustomTabBarCell ()
@property (nonatomic, strong) UIView* container;
@property (nonatomic, strong) UIImageView* iconView;
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, copy) NSString* imageName;
@property (nonatomic, assign) BOOL tabSelected;
@property (nonatomic, assign) BOOL fixed;
@property (nonatomic, strong) UIColor* accentColor;
@end

@implementation CustomTabBarCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.container = [UIView new];
        self.container.translatesAutoresizingMaskIntoConstraints = NO;
        self.container.layer.cornerRadius = 12;
        self.container.layer.cornerCurve = kCACornerCurveContinuous;
        self.container.layer.borderWidth = 2;
        [self.contentView addSubview:self.container];

        self.iconView = [UIImageView new];
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.container addSubview:self.iconView];

        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.5;
        [self.contentView addSubview:self.titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.container.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor],
            [self.container.leadingAnchor
                constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.container.trailingAnchor
                constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.container.heightAnchor
                constraintEqualToAnchor:self.container.widthAnchor],

            [self.iconView.centerXAnchor
                constraintEqualToAnchor:self.container.centerXAnchor],
            [self.iconView.centerYAnchor
                constraintEqualToAnchor:self.container.centerYAnchor],
            [self.iconView.widthAnchor constraintEqualToConstant:28],
            [self.iconView.heightAnchor constraintEqualToConstant:28],

            [self.titleLabel.topAnchor
                constraintEqualToAnchor:self.container.bottomAnchor
                               constant:8],
            [self.titleLabel.leadingAnchor
                constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.titleLabel.trailingAnchor
                constraintEqualToAnchor:self.contentView.trailingAnchor]
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString*)title
                 imageName:(NSString*)imageName
                  selected:(BOOL)selected
                     fixed:(BOOL)fixed
               accentColor:(UIColor*)accentColor {
    self.titleLabel.text = title;
    self.imageName = imageName;
    self.tabSelected = selected;
    self.fixed = fixed;
    self.accentColor = accentColor;
    [self applyAppearance];
}

- (void)applyAppearance {
    // Card background: the fixed (Home) tile uses the inactive container colour.
    self.container.backgroundColor =
        self.fixed ? CustomTabBarInactiveCardBackgroundColor()
                   : CustomTabBarCardBackgroundColor();

    self.container.layer.borderColor =
        (self.tabSelected ? self.accentColor : [UIColor clearColor]).CGColor;

    // Soft card shadow, always on (matches the native cell).
    self.container.layer.shadowColor = CustomTabBarCardShadowColor().CGColor;
    self.container.layer.shadowOffset = CGSizeMake(0, 2);
    self.container.layer.shadowRadius = 16;
    self.container.layer.shadowOpacity = 1.0;
    self.container.layer.masksToBounds = NO;

    if (self.imageName.length) {
        self.iconView.image =
            [UIImage tfn_vectorImageNamed:self.imageName
                                 fitsSize:CGSizeMake(28, 28)
                                fillColor:CustomTabBarIconColor()];
    } else {
        self.iconView.image = nil;
    }

    self.titleLabel.textColor = CustomTabBarTitleColor();
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
    self.titleLabel.text = nil;
    self.container.layer.borderColor = [UIColor clearColor].CGColor;
    self.container.layer.shadowOpacity = 0;
}

+ (NSString*)reuseIdentifier {
    return @"CustomTabBarCell";
}

@end
