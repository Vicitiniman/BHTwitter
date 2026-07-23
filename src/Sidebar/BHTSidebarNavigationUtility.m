#import "Sidebar/BHTSidebarNavigationUtility.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "Core/BHTBundle.h"
#import "CustomTabBar/CustomTabBarUtility.h"

#if defined(__arm64__)
// Native Swift instance methods carry `self` in x20. BHTSidebarRuntime uses
// this small ABI bridge when invoking TwitterDash's exported array setters;
// a normal C function pointer would put the object in x1 and crash.
__asm__(
    ".text\n"
    ".p2align 2\n"
    ".private_extern _BHTInvokeTwitterDashArraySetter\n"
    "_BHTInvokeTwitterDashArraySetter:\n"
    "stp x29, x30, [sp, #-32]!\n"
    "str x20, [sp, #16]\n"
    "mov x29, sp\n"
    "mov x20, x1\n"
    "blr x2\n"
    "ldr x20, [sp, #16]\n"
    "ldp x29, x30, [sp], #32\n"
    "ret\n"
);
#endif

NSString* const BHTSidebarProfileItemID = @"profile";
NSString* const BHTSidebarBlueItemID = @"blue";
NSString* const BHTSidebarHistoryItemID = @"history";
NSString* const BHTSidebarCommunitiesItemID = @"communities";
NSString* const BHTSidebarNewsItemID = @"news";
NSString* const BHTSidebarListsItemID = @"lists";
NSString* const BHTSidebarChatItemID = @"chat";
NSString* const BHTSidebarNotificationsItemID = @"notifications";
NSString* const BHTSidebarSpacesItemID = @"spaces";
NSString* const BHTSidebarFollowRequestsItemID = @"follow_requests";
NSString* const BHTSidebarNavigationSettingsDidChangeNotification =
    @"BHTSidebarNavigationSettingsDidChangeNotification";

static NSString* const kBHTSidebarVisibleItemsKey =
    @"bht_sidebar_navigation_visible";

@implementation BHTSidebarNavigationUtility

+ (NSArray<NSString*>*)canonicalItemIDs {
    return @[
        BHTSidebarProfileItemID,
        BHTSidebarBlueItemID,
        BHTSidebarHistoryItemID,
        BHTSidebarCommunitiesItemID,
        BHTSidebarNewsItemID,
        BHTSidebarListsItemID,
        BHTSidebarChatItemID,
        BHTSidebarNotificationsItemID,
        BHTSidebarSpacesItemID,
        BHTSidebarFollowRequestsItemID
    ];
}

+ (NSArray<NSDictionary*>*)availableItems {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    return @[
        @{
            TabPageKey: BHTSidebarProfileItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_PROFILE_TITLE"],
            TabImageKey: @"sf:person.crop.circle"
        },
        @{
            TabPageKey: BHTSidebarBlueItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_BLUE_TITLE"],
            TabImageKey: @"sf:checkmark.seal"
        },
        @{
            TabPageKey: BHTSidebarHistoryItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_HISTORY_TITLE"],
            TabImageKey: @"sf:clock.arrow.circlepath"
        },
        @{
            TabPageKey: BHTSidebarCommunitiesItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_COMMUNITIES_TITLE"],
            TabImageKey: @"sf:person.3"
        },
        @{
            TabPageKey: BHTSidebarNewsItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_NEWS_TITLE"],
            TabImageKey: @"sf:newspaper"
        },
        @{
            TabPageKey: BHTSidebarListsItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_LISTS_TITLE"],
            TabImageKey: @"sf:list.bullet"
        },
        @{
            TabPageKey: BHTSidebarChatItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_CHAT_TITLE"],
            TabImageKey: @"sf:bubble.left.and.bubble.right"
        },
        @{
            TabPageKey: BHTSidebarNotificationsItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_NOTIFICATIONS_TITLE"],
            TabImageKey: @"sf:bell"
        },
        @{
            TabPageKey: BHTSidebarSpacesItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_SPACES_TITLE"],
            TabImageKey: @"sf:mic"
        },
        @{
            TabPageKey: BHTSidebarFollowRequestsItemID,
            TabTitleKey:
                [bundle localizedStringForKey:@"SIDEBAR_FOLLOW_REQUESTS_TITLE"],
            TabImageKey: @"sf:person.badge.clock"
        }
    ];
}

+ (NSDictionary*)metadataForItemID:(NSString*)itemID {
    for (NSDictionary* entry in [self availableItems]) {
        if ([entry[TabPageKey] isEqualToString:itemID]) return entry;
    }
    return nil;
}

+ (NSArray<NSString*>*)visibleItemIDsInOrder {
    NSArray<NSString*>* saved = [[NSUserDefaults standardUserDefaults]
        stringArrayForKey:kBHTSidebarVisibleItemsKey];
    NSArray<NSString*>* source = saved ?: [self canonicalItemIDs];
    NSSet<NSString*>* valid =
        [NSSet setWithArray:[self canonicalItemIDs]];
    NSMutableArray<NSString*>* sanitized = [NSMutableArray array];
    for (NSString* itemID in source) {
        if ([valid containsObject:itemID] &&
            ![sanitized containsObject:itemID]) {
            [sanitized addObject:itemID];
        }
    }
    return [sanitized copy];
}

+ (void)setVisibleItemIDs:(NSArray<NSString*>*)visible {
    NSSet<NSString*>* valid =
        [NSSet setWithArray:[self canonicalItemIDs]];
    NSMutableArray<NSString*>* sanitized = [NSMutableArray array];
    for (NSString* itemID in visible) {
        if ([valid containsObject:itemID] &&
            ![sanitized containsObject:itemID]) {
            [sanitized addObject:itemID];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:sanitized
                                              forKey:kBHTSidebarVisibleItemsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BHTSidebarNavigationSettingsDidChangeNotification
                      object:nil];
    [self refreshRegisteredDashContentControllers];
}

+ (void)resetSelection {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:kBHTSidebarVisibleItemsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BHTSidebarNavigationSettingsDidChangeNotification
                      object:nil];
    [self refreshRegisteredDashContentControllers];
}

+ (NSHashTable*)registeredDashContentControllers {
    static NSHashTable* controllers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controllers = [NSHashTable weakObjectsHashTable];
    });
    return controllers;
}

+ (void)registerDashContentController:(id)controller {
    if (!controller) return;
    @synchronized([self registeredDashContentControllers]) {
        [[self registeredDashContentControllers] addObject:controller];
    }
}

+ (id)dataSourceForDashContentController:(id)controller {
    if (!controller) return nil;
    @try {
        return [controller valueForKey:@"dataSource"];
    } @catch (__unused NSException* exception) {
        Ivar ivar = class_getInstanceVariable([controller class], "dataSource");
        return ivar ? object_getIvar(controller, ivar) : nil;
    }
}

+ (void)applyConfigurationToDashContentController:(id)controller {
    Class runtime = NSClassFromString(@"BHTSidebarRuntime");
    SEL controllerSelector =
        NSSelectorFromString(@"applyToDashContentController:");
    if (controller && [runtime respondsToSelector:controllerSelector]) {
        BOOL applied =
            ((BOOL (*)(id, SEL, id))objc_msgSend)(
                runtime, controllerSelector, controller);
        if (applied) return;
    }

    id dataSource = [self dataSourceForDashContentController:controller];
    SEL selector = NSSelectorFromString(@"applyToDataSource:");
    if (!dataSource || ![runtime respondsToSelector:selector]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(runtime, selector, dataSource);
}

+ (void)refreshRegisteredDashContentControllers {
    NSArray* controllers;
    @synchronized([self registeredDashContentControllers]) {
        controllers =
            [[self registeredDashContentControllers] allObjects];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        for (id controller in controllers) {
            if ([controller
                    respondsToSelector:@selector(updateVisiblePanelIDs)]) {
                ((void (*)(id, SEL))objc_msgSend)(
                    controller, @selector(updateVisiblePanelIDs));
            }
        }
    });
}

@end
