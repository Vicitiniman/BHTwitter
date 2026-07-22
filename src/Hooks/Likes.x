#import "HookHelpers.h"
#import "Likes/BHTLikesTab.h"

static id BHTLikesSafeValue(id object, NSString* key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static UIImage* BHTLikesHeartImage(BOOL selected) {
    UIImageSymbolConfiguration* configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:23
                                                        weight:UIImageSymbolWeightRegular];
    UIImage* image = [UIImage systemImageNamed:selected ? @"heart.fill" : @"heart"
                              withConfiguration:configuration];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static void BHTFindLargestImageView(UIView* root, UIImageView** best,
                                    CGFloat* bestArea) {
    for (UIView* subview in root.subviews) {
        if ([subview isKindOfClass:UIImageView.class]) {
            CGSize size = subview.bounds.size;
            CGFloat area = MAX(1.0, size.width) * MAX(1.0, size.height);
            if (area > *bestArea && size.width <= 72 && size.height <= 72) {
                *best = (UIImageView*)subview;
                *bestArea = area;
            }
        }
        BHTFindLargestImageView(subview, best, bestArea);
    }
}

static UIImageView* BHTLikesIconView(T1TabView* tabView) {
    for (NSString* key in @[@"imageView", @"iconImageView", @"tabImageView"]) {
        id value = BHTLikesSafeValue(tabView, key);
        if ([value isKindOfClass:UIImageView.class]) return value;
    }
    UIImageView* best = nil;
    CGFloat bestArea = 0;
    BHTFindLargestImageView(tabView, &best, &bestArea);
    return best;
}

static void BHTApplyLikesHeartToTab(T1TabView* tabView) {
    if (![BHTSettings boolForKey:@"enable_likes_tab"] ||
        ![tabView.scribePage isEqualToString:BHTLikesPageID()]) {
        return;
    }
    UIImageView* imageView = BHTLikesIconView(tabView);
    if (imageView) {
        imageView.image = BHTLikesHeartImage(tabView.selected);
        imageView.contentMode = UIViewContentModeCenter;
        imageView.accessibilityLabel = @"Likes";
    }
}

static void BHTApplyLikesHeartToNativeBar(T1TabBarViewController* controller) {
    if (![BHTSettings boolForKey:@"enable_likes_tab"]) return;
    UITabBar* tabBar = nil;
    for (NSString* key in @[@"nativeTabBar", @"tabBar"]) {
        id value = BHTLikesSafeValue(controller, key);
        if ([value isKindOfClass:UITabBar.class]) {
            tabBar = value;
            break;
        }
    }
    NSArray* tabViews = controller.tabViews;
    NSArray<UITabBarItem*>* items = tabBar.items;
    NSUInteger count = MIN(tabViews.count, items.count);
    for (NSUInteger index = 0; index < count; index++) {
        T1TabView* tabView = tabViews[index];
        if (![tabView.scribePage isEqualToString:BHTLikesPageID()]) continue;
        UITabBarItem* item = items[index];
        item.image = BHTLikesHeartImage(NO);
        item.selectedImage = BHTLikesHeartImage(YES);
        item.accessibilityLabel = @"Likes";
    }
}

@interface T1TabView (BHTLikesTap)
@property(nonatomic, strong) UITapGestureRecognizer* bhtLikesTapGesture;
@end

// Capture the native private Likes timeline after the ad/timeline filters have
// done their work.  The native controller remains responsible for pagination.
%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    BHTCaptureLikesSections((UIViewController*)self, sections);
    %orig;
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    BHTCaptureLikesSections((UIViewController*)self, sections);
    %orig;
}

%end

%hook T1TabView

%property(nonatomic, strong) UITapGestureRecognizer* bhtLikesTapGesture;

- (NSString*)title {
    return [self.scribePage isEqualToString:BHTLikesPageID()] ? @"My Likes" : %orig;
}

- (NSString*)imageName {
    return [self.scribePage isEqualToString:BHTLikesPageID()] ? @"heart_stroke" : %orig;
}

- (void)_t1_updateTitleLabel {
    %orig;
    if ([self.scribePage isEqualToString:BHTLikesPageID()]) {
        self.titleLabel.text = @"Likes";
    }
}

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    %orig;
    BHTApplyLikesHeartToTab(self);
}

- (void)setSelected:(BOOL)selected {
    %orig;
    BHTApplyLikesHeartToTab(self);
}

- (void)layoutSubviews {
    %orig;
    BOOL isLikes = [self.scribePage isEqualToString:BHTLikesPageID()] &&
                   [BHTSettings boolForKey:@"enable_likes_tab"];
    if (!self.bhtLikesTapGesture) {
        UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(bht_openLikes:)];
        tap.cancelsTouchesInView = YES;
        tap.delaysTouchesEnded = YES;
        tap.enabled = NO;
        [self addGestureRecognizer:tap];
        self.bhtLikesTapGesture = tap;
    }

    self.bhtLikesTapGesture.enabled = isLikes;
    if (!isLikes) return;

    // The Likes destination reuses X's Grok entry for its visual slot. X may
    // select that entry with a recognizer on either T1TabView or an ancestor.
    // Make every native tap recognizer wait for ours; ours succeeds on the
    // Likes slot, cancelling the underlying Grok selection before presenting
    // the native Likes controller.
    self.userInteractionEnabled = YES;
    BHTApplyLikesHeartToTab(self);
    UIView* current = self;
    for (NSUInteger depth = 0; current && depth < 4;
         depth++, current = current.superview) {
        for (UIGestureRecognizer* recognizer in current.gestureRecognizers) {
            if (recognizer != self.bhtLikesTapGesture &&
                [recognizer isKindOfClass:UITapGestureRecognizer.class]) {
                [recognizer requireGestureRecognizerToFail:
                                self.bhtLikesTapGesture];
            }
        }
    }
}

%new
- (void)bht_openLikes:(id)sender {
    BHTPresentLikesFromView(self);
}

%end

%hook T1TabBarViewController

- (void)_t1_syncNativeTabBarItems {
    %orig;
    BHTApplyLikesHeartToNativeBar(self);
}

- (void)_t1_syncNativeTabBarSelection {
    %orig;
    BHTApplyLikesHeartToNativeBar(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    BHTApplyLikesHeartToNativeBar(self);
}

%end
