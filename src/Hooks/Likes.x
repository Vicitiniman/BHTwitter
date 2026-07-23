#import "HookHelpers.h"
#import "Likes/BHTLikesTab.h"
#import "Likes/BHTLikesNavigationUtility.h"

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
    if (![CustomTabBarUtility likesTabEnabled] ||
        ![tabView.scribePage isEqualToString:BHTLikesPageID()]) {
        return;
    }
    UIImageView* imageView = BHTLikesIconView(tabView);
    if (imageView) {
        imageView.image = BHTLikesHeartImage(tabView.selected);
        imageView.contentMode = UIViewContentModeCenter;
        imageView.tintColor =
            tabView.selected ? CurrentAccentColor()
                             : UIColor.secondaryLabelColor;
        imageView.accessibilityLabel = @"Likes";
    }
}

static void BHTApplyLikesHeartToNativeBar(T1TabBarViewController* controller) {
    if (![CustomTabBarUtility likesTabEnabled]) return;
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

// MARK: - Native Activity History ordering

@interface BHTUnifiedSegmentedController : UIViewController
- (void)reloadDataWithSelectingIndex:(NSInteger)index;
@end

static char kBHTActivityOriginalCountKey;
static char kBHTActivityConfigurationReadyKey;
static char kBHTActivityAppliedSignatureKey;

static NSInteger BHTActivityOriginalCount(UIViewController* controller) {
    NSNumber* count =
        objc_getAssociatedObject(controller, &kBHTActivityOriginalCountKey);
    // The compatibility report and the decrypted X 12.9 implementation both
    // confirm four pages. This fallback is used only if the V1/V2 count method
    // has not yet run.
    return count ? count.integerValue : 4;
}

static void BHTRememberActivityOriginalCount(UIViewController* controller,
                                             NSInteger count) {
    if (count <= 0) return;
    objc_setAssociatedObject(controller, &kBHTActivityOriginalCountKey,
                             @(count),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL BHTActivityConfigurationActive(UIViewController* controller) {
    return BHTIsManagedLikesActivityHistoryController(controller) &&
           [objc_getAssociatedObject(
               controller, &kBHTActivityConfigurationReadyKey) boolValue];
}

static NSInteger BHTActivityOriginalIndex(UIViewController* controller,
                                          NSInteger visibleIndex) {
    if (!BHTActivityConfigurationActive(controller)) return visibleIndex;
    NSInteger mapped = [BHTLikesNavigationUtility
        originalIndexForVisibleIndex:visibleIndex
                       originalCount:BHTActivityOriginalCount(controller)];
    return mapped == NSNotFound ? visibleIndex : mapped;
}

static double BHTActivityOriginalFractionalIndex(
    UIViewController* controller, double visibleIndex) {
    if (!BHTActivityConfigurationActive(controller) || visibleIndex < 0) {
        return visibleIndex;
    }
    NSInteger lower = floor(visibleIndex);
    NSInteger upper = ceil(visibleIndex);
    NSInteger mappedLower =
        BHTActivityOriginalIndex(controller, lower);
    NSInteger mappedUpper =
        BHTActivityOriginalIndex(controller, upper);
    double fraction = visibleIndex - lower;
    return mappedLower + (mappedUpper - mappedLower) * fraction;
}

static UIViewController* BHTFindUnifiedSegmentedController(
    UIViewController* controller) {
    Class wanted =
        NSClassFromString(@"TFNUISwift.UnifiedSegmentedController");
    if (wanted && [controller isKindOfClass:wanted]) return controller;
    for (UIViewController* child in controller.childViewControllers) {
        UIViewController* found =
            BHTFindUnifiedSegmentedController(child);
        if (found) return found;
    }
    return nil;
}

static void BHTApplyActivityHistoryConfiguration(
    UIViewController* controller) {
    if (!BHTActivityConfigurationActive(controller)) return;
    NSInteger originalCount = BHTActivityOriginalCount(controller);
    NSArray<NSString*>* order = [BHTLikesNavigationUtility
        visiblePageIDsForOriginalCount:originalCount];
    NSString* signature =
        [NSString stringWithFormat:@"%ld:%@",
                                   (long)originalCount,
                                   [order componentsJoinedByString:@","]];
    NSString* applied =
        objc_getAssociatedObject(controller,
                                 &kBHTActivityAppliedSignatureKey);
    if ([applied isEqualToString:signature]) return;

    BHTUnifiedSegmentedController* segmented =
        (BHTUnifiedSegmentedController*)
            BHTFindUnifiedSegmentedController(controller);
    if (![segmented
            respondsToSelector:@selector(reloadDataWithSelectingIndex:)]) {
        return;
    }

    NSInteger targetIndex = [BHTLikesNavigationUtility
        visibleIndexForPageID:BHTLikesPostsPageID
                originalCount:originalCount];
    if (targetIndex == NSNotFound) targetIndex = 0;
    [segmented reloadDataWithSelectingIndex:targetIndex];
    objc_setAssociatedObject(controller,
                             &kBHTActivityAppliedSignatureKey,
                             signature,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
}

void BHTRefreshLikesActivityHistoryConfiguration(
    UIViewController* rootController) {
    if (!rootController) return;
    Class activityClass = NSClassFromString(
        @"XActivityHistory.ActivityHistoryContainerViewController");
    if (activityClass &&
        [rootController isKindOfClass:activityClass]) {
        BHTApplyActivityHistoryConfiguration(rootController);
    }
    for (UIViewController* child in
         rootController.childViewControllers) {
        BHTRefreshLikesActivityHistoryConfiguration(child);
    }
}

// This Swift controller is the native Bookmarks / Videos / Articles / Likes
// surface. The hooks are gated by the BHTLikesViewController ancestor, so X's
// stock Activity History screen and Grok destination are never modified.
%hook _TtC16XActivityHistory38ActivityHistoryContainerViewController

- (NSInteger)numberOfTabsV1In:(id)segmentedController {
    NSInteger originalCount = %orig;
    if (BHTIsManagedLikesActivityHistoryController(
            (UIViewController*)self)) {
        BHTRememberActivityOriginalCount((UIViewController*)self,
                                         originalCount);
    }
    if (!BHTActivityConfigurationActive((UIViewController*)self)) {
        return originalCount;
    }
    return [BHTLikesNavigationUtility
        visiblePageIDsForOriginalCount:originalCount].count;
}

- (NSInteger)numberOfTabsV2In:(id)segmentedController {
    NSInteger originalCount = %orig;
    if (BHTIsManagedLikesActivityHistoryController(
            (UIViewController*)self)) {
        BHTRememberActivityOriginalCount((UIViewController*)self,
                                         originalCount);
    }
    if (!BHTActivityConfigurationActive((UIViewController*)self)) {
        return originalCount;
    }
    return [BHTLikesNavigationUtility
        visiblePageIDsForOriginalCount:originalCount].count;
}

- (UIViewController*)unifiedSegmentedController:(id)controller
                      v1ViewControllerAtIndex:(NSInteger)index {
    return %orig(controller,
                 BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (NSString*)unifiedSegmentedController:(id)controller
                         v1TitleAtIndex:(NSInteger)index {
    return %orig(controller,
                 BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (NSInteger)unifiedSegmentedController:(id)controller
                         v1CaretAtIndex:(NSInteger)index {
    return %orig(controller,
                 BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (UIViewController*)unifiedSegmentedController:(id)controller
                      v2ViewControllerAtIndex:(NSInteger)index {
    return %orig(controller,
                 BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (id)unifiedSegmentedController:(id)controller
             v2DescriptorAtIndex:(NSInteger)index {
    return %orig(controller,
                 BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (void)unifiedSegmentedController:(id)controller
          willSelectViewController:(UIViewController*)viewController
                           atIndex:(NSInteger)index
                      indexChanged:(BOOL)indexChanged {
    %orig(controller, viewController,
          BHTActivityOriginalIndex((UIViewController*)self, index),
          indexChanged);
}

- (void)unifiedSegmentedController:(id)controller
           didSelectViewController:(UIViewController*)viewController
                           atIndex:(NSInteger)index
                     previousIndex:(NSInteger)previousIndex
                           trigger:(NSInteger)trigger {
    NSInteger mappedPrevious =
        previousIndex < 0
            ? previousIndex
            : BHTActivityOriginalIndex((UIViewController*)self,
                                       previousIndex);
    %orig(controller, viewController,
          BHTActivityOriginalIndex((UIViewController*)self, index),
          mappedPrevious, trigger);
}

- (void)unifiedSegmentedController:(id)controller
        didScrollToFractionalIndex:(double)index {
    %orig(controller,
          BHTActivityOriginalFractionalIndex(
              (UIViewController*)self, index));
}

- (void)unifiedSegmentedController:(id)controller
                  didTapTabAtIndex:(NSInteger)index {
    %orig(controller,
          BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (void)unifiedSegmentedController:(id)controller
                didLongPressAtIndex:(NSInteger)index {
    %orig(controller,
          BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (void)viewDidLoad {
    // Let X safely build its verified four-page controller first. Enabling the
    // remap only after that transaction avoids feeding a hidden/reordered index
    // into its one-time initial-tab resolver.
    %orig;
    if (BHTIsManagedLikesActivityHistoryController(
            (UIViewController*)self)) {
        objc_setAssociatedObject(
            self, &kBHTActivityConfigurationReadyKey, @YES,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIViewController* weakController =
            (UIViewController*)self;
        dispatch_async(dispatch_get_main_queue(), ^{
            BHTApplyActivityHistoryConfiguration(weakController);
        });
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    BHTApplyActivityHistoryConfiguration((UIViewController*)self);
}

%end

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
                ((id (*)(id, SEL))objc_msgSend)(self,
                                                @selector(tabView));
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
