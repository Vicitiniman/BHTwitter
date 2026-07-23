#import "HookHelpers.h"
#import "Likes/BHTLikesTab.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface BHTLikesViewController : UIViewController
- (instancetype)init;
- (void)ingestSections:(NSArray*)sections;
@end
@interface BHTMediaPagerController : UIViewController
- (id)currentItem;
- (void)mediaItemsDidUpdate;
- (void)openCurrentPost:(id)sender;
@end
@interface T1ActivityHistoryBridge : NSObject
+ (UIViewController*)makeActivityHistoryViewControllerWithAccount:(id)account initialTab:(NSInteger)tab;
@end
@interface T1TabbedAppNavigationViewController (BHTLikesNative)
- (id)appNavigation;
@end
@interface T1TabView (BHTLikesNative)
@property(nonatomic, strong) UITapGestureRecognizer* bhtLikesTapGesture;
@end

static char kBHTLikesEntryKey;
static char kBHTLikesControllerKey;
static char kBHTLikesTabControllerKey;
static __thread BOOL BHTBuildingLikes;

static id BHTLValue(id object, NSString* key) {
    if (!object) return nil;
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException* exception) { return nil; }
}
static void BHTLSet(id object, NSString* key, id value) {
    @try { [object setValue:value forKey:key]; }
    @catch (__unused NSException* exception) {}
}
static BOOL BHTLikesEnabled(void) {
    return [BHTSettings boolForKey:@"enable_likes_tab"];
}
static UIViewController* BHTFindVC(UIViewController* root, Class wanted) {
    if (!root || !wanted) return nil;
    if ([root isKindOfClass:wanted]) return root;
    for (UIViewController* child in root.childViewControllers) {
        UIViewController* result = BHTFindVC(child, wanted);
        if (result) return result;
    }
    return BHTFindVC(root.presentedViewController, wanted);
}
static T1TabbedAppNavigationViewController* BHTTabbedNavigation(void) {
    Class wanted = NSClassFromString(@"T1TabbedAppNavigationViewController");
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        UIViewController* result = BHTFindVC(window.rootViewController, wanted);
        if (result) return (id)result;
    }
    return nil;
}
static id BHTCurrentAccount(void) {
    Class hostClass = NSClassFromString(@"T1HostViewController");
    SEL shared = NSSelectorFromString(@"sharedHostViewController");
    id host = [hostClass respondsToSelector:shared] ? ((id(*)(id,SEL))objc_msgSend)(hostClass, shared) : nil;
    SEL current = NSSelectorFromString(@"currentAccount");
    return [host respondsToSelector:current] ? ((id(*)(id,SEL))objc_msgSend)(host, current) : nil;
}
static UIScrollView* BHTFindScroll(UIView* root) {
    if (!root) return nil;
    UIScrollView* best = [root isKindOfClass:UIScrollView.class] ? (id)root : nil;
    for (UIView* child in root.subviews) {
        UIScrollView* candidate = BHTFindScroll(child);
        if (!candidate) continue;
        CGFloat candidateRange = candidate.contentSize.height - candidate.bounds.size.height;
        CGFloat bestRange = best.contentSize.height - best.bounds.size.height;
        if (!best || candidateRange > bestRange) best = candidate;
    }
    return best;
}
static UIImageView* BHTFindIcon(UIView* root) {
    for (NSString* key in @[@"imageView", @"iconImageView", @"tabImageView"]) {
        id value = BHTLValue(root, key);
        if ([value isKindOfClass:UIImageView.class]) return value;
    }
    for (UIView* child in root.subviews) {
        if ([child isKindOfClass:UIImageView.class] && child.bounds.size.width <= 72) return (id)child;
        UIImageView* result = BHTFindIcon(child);
        if (result) return result;
    }
    return nil;
}
static void BHTColorLikesIcon(T1TabView* tabView) {
    if (!BHTLikesEnabled() || ![tabView.scribePage isEqualToString:BHTLikesPageID()]) return;
    UIImageView* icon = BHTFindIcon(tabView);
    icon.tintColor = tabView.iconColor ?: tabView.tintColor;
}
static UIViewController* BHTLikesControllerForEntry(id entry) {
    if (!entry || !BHTLikesEnabled()) return nil;
    UIViewController* existing = objc_getAssociatedObject(entry, &kBHTLikesControllerKey);
    if (existing) return existing;
    Class cls = NSClassFromString(@"BHTLikesViewController");
    UIViewController* likes = [cls respondsToSelector:@selector(new)] ? [cls new] : nil;
    if (!likes) return nil;
    objc_setAssociatedObject(entry, &kBHTLikesControllerKey, likes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    T1TabView* tabView = [entry respondsToSelector:@selector(tabView)] ? [entry tabView] : nil;
    objc_setAssociatedObject(tabView, &kBHTLikesEntryKey, entry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(tabView, &kBHTLikesTabControllerKey, likes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return likes;
}
static void BHTResetLikes(UIViewController* likes) {
    UIViewController* posts = BHTLValue(likes, @"postsController");
    UIScrollView* postsScroll = BHTFindScroll(posts.view);
    if (postsScroll) [postsScroll setContentOffset:CGPointMake(postsScroll.contentOffset.x, -postsScroll.adjustedContentInset.top) animated:NO];
    if ([posts respondsToSelector:NSSelectorFromString(@"refresh")]) ((void(*)(id,SEL))objc_msgSend)(posts, NSSelectorFromString(@"refresh"));
    UICollectionView* media = BHTLValue(likes, @"collectionView");
    if ([media isKindOfClass:UICollectionView.class]) [media setContentOffset:CGPointMake(media.contentOffset.x, -media.adjustedContentInset.top) animated:NO];
}
static NSInteger BHTMediaSubindex(id item) {
    NSString* identifier = BHTLValue(item, @"identifier");
    NSArray* parts = [(identifier ?: @"") componentsSeparatedByString:@"-"];
    return parts.count > 1 ? [parts[1] integerValue] : 0;
}
static void BHTSortLikedMedia(UIViewController* likes) {
    NSMutableArray* items = BHTLValue(likes, @"mediaItems");
    if (![items isKindOfClass:NSMutableArray.class] || items.count < 2) return;
    id pager = BHTLValue(likes, @"activeMediaPager");
    id current = [pager respondsToSelector:NSSelectorFromString(@"currentItem")] ? ((id(*)(id,SEL))objc_msgSend)(pager, NSSelectorFromString(@"currentItem")) : nil;
    NSString* currentID = BHTLValue(current, @"identifier");
    [items sortUsingComparator:^NSComparisonResult(id a, id b) {
        long long left = [BHTLValue(a, @"statusID") longLongValue];
        long long right = [BHTLValue(b, @"statusID") longLongValue];
        if (left != right) return left > right ? NSOrderedAscending : NSOrderedDescending;
        NSInteger li = BHTMediaSubindex(a), ri = BHTMediaSubindex(b);
        return li < ri ? NSOrderedAscending : (li > ri ? NSOrderedDescending : NSOrderedSame);
    }];
    [BHTLValue(likes, @"collectionView") reloadData];
    if (pager && currentID.length) {
        NSUInteger index = [items indexOfObjectPassingTest:^BOOL(id item, NSUInteger idx, BOOL* stop) {
            return [BHTLValue(item, @"identifier") isEqualToString:currentID];
        }];
        if (index != NSNotFound) BHTLSet(pager, @"currentIndex", @(index));
        if ([pager respondsToSelector:NSSelectorFromString(@"mediaItemsDidUpdate")]) ((void(*)(id,SEL))objc_msgSend)(pager, NSSelectorFromString(@"mediaItemsDidUpdate"));
    }
}
static BOOL BHTShowConversation(UINavigationController* navigation, long long statusID) {
    id appNavigation = [BHTTabbedNavigation() appNavigation];
    SEL selector = NSSelectorFromString(@"_t1_showConversationViewControllerFromNavigationController:forViewModel:statusID:source:navigationContext:statusNavigationContext:sourceNavigationMetadata:completion:");
    if (!navigation || statusID <= 0 || ![appNavigation respondsToSelector:selector]) return NO;
    NSMethodSignature* signature = [appNavigation methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 10) return NO;
    NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = appNavigation; invocation.selector = selector;
    id nilObject = nil; long long source = 0;
    [invocation setArgument:&navigation atIndex:2]; [invocation setArgument:&nilObject atIndex:3];
    [invocation setArgument:&statusID atIndex:4]; [invocation setArgument:&source atIndex:5];
    [invocation setArgument:&nilObject atIndex:6]; [invocation setArgument:&nilObject atIndex:7];
    [invocation setArgument:&nilObject atIndex:8]; [invocation setArgument:&nilObject atIndex:9];
    [invocation invoke]; return YES;
}

%hook BHTLikesViewController
- (instancetype)init {
    BOOL previous = BHTBuildingLikes;
    BHTBuildingLikes = YES;
    id result = %orig;
    BHTBuildingLikes = previous;
    return result;
}
- (void)ingestSections:(NSArray*)sections {
    %orig;
    BHTSortLikedMedia(self);
}
%end

%hook T1ActivityHistoryBridge
+ (UIViewController*)makeActivityHistoryViewControllerWithAccount:(id)account initialTab:(NSInteger)tab {
    return %orig(account, (BHTBuildingLikes && tab == 3) ? 4 : tab);
}
%end

%hook BHTMediaPagerController
- (void)openCurrentPost:(id)sender {
    id item = [self respondsToSelector:NSSelectorFromString(@"currentItem")] ? ((id(*)(id,SEL))objc_msgSend)(self, NSSelectorFromString(@"currentItem")) : nil;
    if (BHTShowConversation(self.navigationController, [BHTLValue(item, @"statusID") longLongValue])) return;
    %orig;
}
%end

%hook T1TabbedAppNavigationViewController
- (void)setVisibleTabEntries:(NSArray*)entries {
    NSArray* installed = BHTEntriesByInstallingLikesDestination(entries);
    NSMutableArray* result = [NSMutableArray array];
    BOOL found = NO;
    for (id entry in installed) {
        T1TabView* tabView = [entry respondsToSelector:@selector(tabView)] ? [entry tabView] : nil;
        BOOL likes = [tabView.scribePage isEqualToString:BHTLikesPageID()];
        if (likes && found) continue;
        if (likes) found = YES;
        [result addObject:entry];
    }
    %orig(result);
}
%end

%hook T1TabView
- (void)layoutSubviews {
    %orig;
    if (![self.scribePage isEqualToString:BHTLikesPageID()]) return;
    self.bhtLikesTapGesture.enabled = NO;
    self.bhtLikesTapGesture.cancelsTouchesInView = NO;
    BHTColorLikesIcon(self);
}
- (void)setIconColor:(UIColor*)color {
    %orig;
    BHTColorLikesIcon(self);
}
- (void)tintColorDidChange {
    %orig;
    BHTColorLikesIcon(self);
}
- (void)setSelected:(BOOL)selected {
    BOOL wasSelected = self.selected;
    %orig;
    BHTColorLikesIcon(self);
    if (!selected || wasSelected || ![self.scribePage isEqualToString:BHTLikesPageID()]) return;
    UIViewController* likes = objc_getAssociatedObject(self, &kBHTLikesTabControllerKey);
    if (!likes) likes = BHTLikesControllerForEntry(objc_getAssociatedObject(self, &kBHTLikesEntryKey));
    dispatch_async(dispatch_get_main_queue(), ^{ BHTResetLikes(likes); });
}
%end

%group BHTNativeLikesEntry
%hook BHTGrokEntry
- (T1TabView*)tabView {
    T1TabView* tabView = %orig;
    if (BHTLikesEnabled()) objc_setAssociatedObject(tabView, &kBHTLikesEntryKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return tabView;
}
- (BOOL)isExcludedFromTabBar {
    if (BHTLikesEnabled()) return NO;
    return %orig;
}
- (BOOL)isTabViewSideBarOnly {
    if (BHTLikesEnabled()) return NO;
    return %orig;
}
- (id)createContentController {
    id likes = BHTLikesControllerForEntry(self);
    if (likes) return likes;
    return %orig;
}
- (id)rootTabViewController {
    id likes = BHTLikesControllerForEntry(self);
    if (likes) return likes;
    return %orig;
}
%end
%end

%ctor {
    %init;
    Class cls = NSClassFromString(@"T1TwitterSwift.GrokAppNavigationTabEntry");
    if (cls) %init(BHTNativeLikesEntry, BHTGrokEntry = cls);
}
