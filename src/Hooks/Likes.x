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

// X 12.9's navigation registry rejects an independently implemented
// Objective-C entry before sending it any protocol messages. The Likes entry is
// therefore a genuine BookmarksAppNavigationTabEntry made by X's own factory.
// These hooks keep its native lifecycle intact and replace only its controller.
%hook _TtC14T1TwitterSwift30BookmarksAppNavigationTabEntry

- (id)contentControllerFactory {
    BOOL isLikes = BHTIsNativeLikesEntry(self);
    if (isLikes) BHTRecordNativeLikesFactoryRequest(NO);
    return %orig;
}

- (UIViewController*)createContentController {
    BOOL isLikes = BHTIsNativeLikesEntry(self);
    if (isLikes) BHTRecordNativeLikesFactoryRequest(YES);
    UIViewController* controller = %orig;
    if (isLikes) {
        Class navigationClass =
            NSClassFromString(@"T1TwitterSwift.BookmarksNavigationController");
        if (navigationClass &&
            [controller isKindOfClass:navigationClass]) {
            T1TabView* tabView =
                [self respondsToSelector:@selector(tabView)]
                    ? [self tabView]
                    : nil;
            BHTConnectNativeLikesNavigationController(controller, tabView);
        } else {
            BHTConnectNativeLikesNavigationTree(controller, self);
        }
    }
    return controller;
}

- (UIViewController*)rootTabViewController {
    BOOL isLikes = BHTIsNativeLikesEntry(self);
    UIViewController* root = %orig;
    if (isLikes) BHTConnectNativeLikesNavigationTree(root, self);
    return root;
}

%end

%hook _TtC14T1TwitterSwift29BookmarksNavigationController

- (id)initWithAccount:(id)account tabView:(T1TabView*)tabView {
    id controller = %orig(account, tabView);
    if ([tabView.scribePage isEqualToString:BHTLikesPageID()]) {
        BHTConnectNativeLikesNavigationController(controller, tabView);
    }
    return controller;
}

- (void)viewDidLoad {
    %orig;
    if (BHTIsNativeLikesNavigationController((UIViewController*)self)) {
        BHTInstallNativeLikesNavigationController(
            (UIViewController*)self, NO);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    if (BHTIsNativeLikesNavigationController((UIViewController*)self)) {
        BHTInstallNativeLikesNavigationController(
            (UIViewController*)self, NO);
    }
}

%end

// Capture the native private Likes timeline after the ad/timeline filters have
// done their work.  The native controller remains responsible for pagination.
%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    BOOL isLikes = BHTCaptureLikesSections((UIViewController*)self, sections);
    %orig(sections, isLikes ? NO : restoreScrollPosition);
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
    BOOL wasSelected = self.selected;
    %orig;
    BHTApplyLikesHeartToTab(self);
    if (selected && !wasSelected &&
        [self.scribePage isEqualToString:BHTLikesPageID()]) {
        BHTActivateLikesTabView(self);
    }
}

- (void)layoutSubviews {
    %orig;
    BHTApplyLikesHeartToTab(self);
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
