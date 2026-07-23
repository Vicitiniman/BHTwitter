//
//  AppIconViewController.m
//  NeoFreeBird
//
//  Created by Bandar Alruwaili on 10/12/2023.
//  Modified by actuallyaridan on 25/05/2025.
//

#import "AppIconViewController.h"
#import <UIKit/UIKit.h>
#import "AppIconCell.h"
#import "AppIconItem.h"
#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import "ThemeColor/Palette.h"

extern UIColor* CurrentAccentColor(void);

// UIApplication's alternateIconName getter goes stale on sideloaded installs
// (setting the icon works, but the getter keeps reporting an old name across
// reinstalls), so the last choice made here is what the radios trust.
static NSString* const kLastSelectedIconKey = @"bh_last_selected_app_icon";
static NSString* const kPrimaryIconSentinel = @"PrimaryIcon";

@interface AppIconViewController () <UICollectionViewDelegate,
                                     UICollectionViewDataSource,
                                     UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView* appIconCollectionView;
@property (nonatomic, copy) NSArray<AppIconItem*>* icons;
@end

@implementation AppIconViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.title = [[BHTBundle sharedBundle]
        localizedTwitterStringForKey:@"SUBSCRIPTION_APP_ICON_SETTINGS_TITLE"];

    UICollectionViewFlowLayout* flow = [UICollectionViewFlowLayout new];
    flow.sectionInset = UIEdgeInsetsMake(16, 16, 16, 16);
    flow.minimumLineSpacing = 10;
    flow.minimumInteritemSpacing = 10;

    self.appIconCollectionView =
        [[UICollectionView alloc] initWithFrame:CGRectZero
                           collectionViewLayout:flow];
    self.appIconCollectionView.contentInsetAdjustmentBehavior =
        UIScrollViewContentInsetAdjustmentAlways;
    [self.appIconCollectionView registerClass:[AppIconCell class]
                   forCellWithReuseIdentifier:[AppIconCell reuseIdentifier]];
    [self.appIconCollectionView registerClass:[UICollectionReusableView class]
                   forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                          withReuseIdentifier:@"HeaderView"];
    self.appIconCollectionView.delegate = self;
    self.appIconCollectionView.dataSource = self;
    self.appIconCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.appIconCollectionView.backgroundColor = [Palette currentBackgroundColor];

    self.view.backgroundColor = [Palette currentBackgroundColor];

    [self.view addSubview:self.appIconCollectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.appIconCollectionView.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.appIconCollectionView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.appIconCollectionView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.appIconCollectionView.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self loadAppIcons];
}

#pragma mark - Icon data

// Icons come from Info.plist so the picker matches whatever the build ships;
// the primary icon is listed first so it can be restored.
- (void)loadAppIcons {
    NSDictionary* iconsDict =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIcons"];

    NSMutableArray<AppIconItem*>* items = [NSMutableArray new];

    NSDictionary* primary = iconsDict[@"CFBundlePrimaryIcon"];
    if ([primary isKindOfClass:[NSDictionary class]]) {
        [items addObject:[[AppIconItem alloc]
                             initWithBundleIconName:primary[@"CFBundleIconName"]
                                      iconFileNames:primary[@"CFBundleIconFiles"]
                                      isPrimaryIcon:YES]];
    }

    NSDictionary* alternates = iconsDict[@"CFBundleAlternateIcons"];
    if ([alternates isKindOfClass:[NSDictionary class]]) {
        NSArray<NSString*>* sortedKeys = [alternates.allKeys
            sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
        for (NSString* key in sortedKeys) {
            NSDictionary* alt = alternates[key];
            NSString* name = alt[@"CFBundleIconName"] ?: key;
            [items addObject:[[AppIconItem alloc]
                                 initWithBundleIconName:name
                                          iconFileNames:alt[@"CFBundleIconFiles"]
                                          isPrimaryIcon:NO]];
        }
    }

    self.icons = items;
    [self.appIconCollectionView reloadData];
}

// Thumbnails are "<name>-settings" in the asset catalog ("Icon-<Name>-settings"
// for the primary icon), falling back to the icon art itself.
- (UIImage*)thumbnailForItem:(AppIconItem*)item {
    UITraitCollection* tc = self.traitCollection;
    NSBundle* bundle = [NSBundle mainBundle];

    NSString* settingsName;
    if (item.isPrimaryIcon) {
        NSString* base = item.bundleIconName;
        if ([base hasSuffix:@"AppIcon"]) {
            base = [base substringToIndex:base.length - @"AppIcon".length];
        }
        settingsName = [NSString stringWithFormat:@"Icon-%@-settings", base];
    } else {
        settingsName = [item.bundleIconName stringByAppendingString:@"-settings"];
    }

    UIImage* img = [UIImage imageNamed:settingsName
                              inBundle:bundle
         compatibleWithTraitCollection:tc];
    if (!img && item.bundleIconName) {
        img = [UIImage imageNamed:item.bundleIconName
                                 inBundle:bundle
            compatibleWithTraitCollection:tc];
    }
    if (!img) {
        for (NSString* file in [item.bundleIconFiles reverseObjectEnumerator]) {
            img = [UIImage imageNamed:file
                                     inBundle:bundle
                compatibleWithTraitCollection:tc];
            if (img)
                break;
        }
    }
    return img;
}

- (BOOL)isItemActive:(AppIconItem*)item {
    NSString* saved = [[NSUserDefaults standardUserDefaults]
        stringForKey:kLastSelectedIconKey];
    NSString* current =
        saved ?: [UIApplication sharedApplication].alternateIconName;

    if (item.isPrimaryIcon) {
        return current == nil || [current isEqualToString:kPrimaryIconSentinel];
    }
    return [current isEqualToString:item.bundleIconName];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView*)cv {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView*)cv
     numberOfItemsInSection:(NSInteger)section {
    return self.icons.count;
}

- (UICollectionViewCell*)collectionView:(UICollectionView*)cv
                 cellForItemAtIndexPath:(NSIndexPath*)ip {
    AppIconCell* cell =
        [cv dequeueReusableCellWithReuseIdentifier:[AppIconCell reuseIdentifier]
                                      forIndexPath:ip];
    AppIconItem* item = self.icons[ip.row];

    [cell configureWithImage:[self thumbnailForItem:item]
                      active:[self isItemActive:item]
                 accentColor:CurrentAccentColor()];

    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView*)cv
    didSelectItemAtIndexPath:(NSIndexPath*)ip {
    if (![UIApplication sharedApplication].supportsAlternateIcons)
        return;

    AppIconItem* item = self.icons[ip.row];
    NSString* toSet = item.isPrimaryIcon ? nil : item.bundleIconName;

    // A block is always passed: nil name + nil handler crashes UIKit.
    [[UIApplication sharedApplication] setAlternateIconName:toSet
                                          completionHandler:
        ^(NSError* _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"[NeoFreeBird] App icon change failed: %@", error);
            } else {
                [[NSUserDefaults standardUserDefaults]
                    setObject:(toSet ?: kPrimaryIconSentinel)
                       forKey:kLastSelectedIconKey];
            }
            [cv reloadData];
        });
    }];
}

#pragma mark - Section header

- (UICollectionReusableView*)collectionView:(UICollectionView*)cv
          viewForSupplementaryElementOfKind:(NSString*)kind
                                atIndexPath:(NSIndexPath*)ip {
    UICollectionReusableView* header =
        [cv dequeueReusableSupplementaryViewOfKind:kind
                               withReuseIdentifier:@"HeaderView"
                                      forIndexPath:ip];
    [header.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    detail.textColor = [UIColor secondaryLabelColor];
    detail.numberOfLines = 0;
    detail.textAlignment = NSTextAlignmentLeft;
    detail.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"APP_ICON_HEADER_TITLE"];
    [header addSubview:detail];

    [NSLayoutConstraint activateConstraints:@[
        [detail.leadingAnchor constraintEqualToAnchor:header.leadingAnchor
                                             constant:16],
        [detail.trailingAnchor constraintEqualToAnchor:header.trailingAnchor
                                              constant:-16],
        [detail.topAnchor constraintEqualToAnchor:header.topAnchor
                                         constant:8],
        [detail.bottomAnchor constraintEqualToAnchor:header.bottomAnchor
                                            constant:-8]
    ]];

    return header;
}

- (CGSize)collectionView:(UICollectionView*)cv
                             layout:(UICollectionViewLayout*)layout
    referenceSizeForHeaderInSection:(NSInteger)section {
    return CGSizeMake(cv.bounds.size.width, 60);
}

#pragma mark - Flow layout sizing

- (CGSize)collectionView:(UICollectionView*)cv
                    layout:(UICollectionViewLayout*)layout
    sizeForItemAtIndexPath:(NSIndexPath*)indexPath {
    // Native layout: 3 columns, icon width capped at 96pt, height = width + 38
    // (icon square + 14pt gap + 24pt indicator).
    UICollectionViewFlowLayout* flow = (UICollectionViewFlowLayout*)layout;
    CGFloat available = CGRectGetWidth(cv.bounds) - flow.sectionInset.left -
                        flow.sectionInset.right -
                        flow.minimumInteritemSpacing * 2;
    CGFloat width = MIN(floor(available / 3.0), 96.0);
    return CGSizeMake(width, width + 38.0);
}

@end
