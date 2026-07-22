//
//  Timeline.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Hide custom timelines

static __weak NSObject* PinnedTimelinesRepository;
static NSArray* LastPinnedTimelineModels;
static BOOL PinnedTimelinesWriteBypass = NO;

// Applies a toggle without relaunching. Hiding rewrites the UNCHANGED pinned
// list purely to republish — updatePinnedTimelines: persists server-side, so
// anything else would unpin for real; the delegate hook below swaps in the
// empty list on the way through.
void applyHideCustomTimelinesSetting(void) {
    NSObject* repository = PinnedTimelinesRepository;
    if (!repository) {
        return;
    }

    if ([BHTSettings boolForKey:@"hide_custom_timelines"]) {
        NSArray* models = LastPinnedTimelineModels;
        if (models.count > 0) {
            PinnedTimelinesWriteBypass = YES;
            ((void (*)(id, SEL, id))objc_msgSend)(repository, @selector(updatePinnedTimelines:), models);
            PinnedTimelinesWriteBypass = NO;
        }
    } else if ([repository respondsToSelector:@selector(fetchPinnedTimelinesWithThrottleEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            repository, @selector(fetchPinnedTimelinesWithThrottleEnabled:), NO);
    }
}

// The trailing accessory is only reconfigured while the strip is showing, so a
// button built before hiding mid-session survives; sync its visibility here. The
// property is a Swift lazy var whose storage ivar KVC can't see, hence the fallback.
static void SyncHomeAddTabButton(id container, BOOL hidden) {
    UIView* button = nil;

    @try {
        button = [container valueForKey:@"addTabButton"];
    } @catch (__unused NSException* exception) {
        unsigned int ivarCount = 0;
        Ivar* ivars = class_copyIvarList([container class], &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char* name = ivar_getName(ivars[i]);
            if (name && strstr(name, "addTabButton")) {
                button = object_getIvar(container, ivars[i]);
                break;
            }
        }
        free(ivars);
    }

    if ([button isKindOfClass:[UIView class]]) {
        button.hidden = hidden;
    }
}

// The repository publishes the pinned list through this single delegate call, so
// handing it an empty array hides the tabs without touching persisted state.
%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController

- (void)pinnedTimelinesRepository:(id)repository
    didChangeWithPinnedTimelineModels:(NSArray*)models {
    PinnedTimelinesRepository = repository;
    if (models.count > 0) {
        LastPinnedTimelineModels = [models copy];
    }
    BOOL hide = [BHTSettings boolForKey:@"hide_custom_timelines"];

    %orig(repository, hide ? @[] : models);
    SyncHomeAddTabButton(self, hide);
}

- (id)tfn_navigationBarAccessoryView {
    id accessoryView = %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
    return accessoryView;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
}

- (BOOL)tfn_supportsTabBarCollapsing {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? NO : %orig;
}

- (BOOL)tfn_prefersTabBarPinned {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? YES : %orig;
}

%end

// X 12.9 also registers an Objective-C-visible compatibility name for the Home
// container.  Keep the same safe, non-persisting behavior on that path.
%group BHTX129HomeContainer

%hook HomeTimelineContainerViewController

- (void)pinnedTimelinesRepository:(id)repository
    didChangeWithPinnedTimelineModels:(NSArray*)models {
    PinnedTimelinesRepository = repository;
    if (models.count > 0) LastPinnedTimelineModels = [models copy];
    BOOL hide = [BHTSettings boolForKey:@"hide_custom_timelines"];
    %orig(repository, hide ? @[] : models);
    SyncHomeAddTabButton(self, hide);
}

- (id)tfn_navigationBarAccessoryView {
    id accessory = %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
    return accessory;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
}

- (BOOL)tfn_supportsTabBarCollapsing {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? NO : %orig;
}

- (BOOL)tfn_prefersTabBarPinned {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? YES : %orig;
}

%end

%end

// While hiding, the overridden pinned-tabs feature switches make the app compute
// an empty pinned list; freeze writes so it can't overwrite the real tabs.
%hook _TtC32TwitterHomeFeatureImplementation31CachedPinnedTimelinesRepository

- (void)updatePinnedTimelines:(id)timelines {
    if (!PinnedTimelinesWriteBypass && [BHTSettings boolForKey:@"hide_custom_timelines"]) {
        return;
    }

    %orig;
}

%end

// MARK: - Force tweet images to full frame

%hook T1StandardStatusAttachmentViewAdapter

// attachmentType 2 = photos, displayType 1 = full frame
- (NSUInteger)displayType {
    if (self.attachmentType == 2) {
        return [BHTSettings boolForKey:@"force_tweet_full_frame"] ? 1 : %orig;
    }

    return %orig;
}

%end

// MARK: - Hide the Spaces bar

// The bar is still the repurposed Fleets line; both home timeline implementations
// share this visibility gate, re-evaluated on every content or settings update.
%hook T1FleetLineHeaderController

- (BOOL)_t1_shouldShowFleetLine {
    if ([BHTSettings boolForKey:@"hide_spaces"]) {
        return NO;
    }

    return %orig;
}

%end

// Target the update-indicator controller rather than every TFNPillControl in
// the app (other sheets and banners reuse that control class).
%hook TUIUpdateIndicator

- (void)viewDidLayoutSubviews {
    %orig;
    if ([BHTSettings boolForKey:@"hide_timeline_prompts"]) {
        self.pillControl.hidden = YES;
        self.pillControl.alpha = 0;
        self.pillControl.userInteractionEnabled = NO;
    }
}

%end

// MARK: - Hide "Discover more", who-to-follow and prompts

// Resolves the class by name so mangled Swift names work; NSStringFromClass
// would only ever produce the demangled dotted form.
static BOOL IsInHierarchyOfClass(UIViewController* viewController, NSString* className) {
    Class targetClass = NSClassFromString(className);
    if (!targetClass) {
        return NO;
    }

    UIViewController* currentVC = viewController;

    while (currentVC) {
        if ([currentVC isKindOfClass:targetClass]) {
            return YES;
        }

        if (currentVC.parentViewController) {
            currentVC = currentVC.parentViewController;
        } else if (currentVC.navigationController) {
            currentVC = currentVC.navigationController;
        } else if (currentVC.presentingViewController) {
            currentVC = currentVC.presentingViewController;
        } else {
            break;
        }
    }

    return NO;
}

static NSString* ItemEntryID(id viewModel) {
    if (![viewModel respondsToSelector:@selector(entryID)]) {
        return nil;
    }

    NSString* entryID = [viewModel performSelector:@selector(entryID)];
    return [entryID isKindOfClass:[NSString class]] ? entryID : nil;
}

static NSString* ItemScribeComponent(id viewModel) {
    if (![viewModel respondsToSelector:@selector(scribeComponent)]) {
        return nil;
    }

    NSString* component = [viewModel performSelector:@selector(scribeComponent)];
    return [component isKindOfClass:[NSString class]] ? component : nil;
}

static id ItemObjectValue(id viewModel, SEL selector, const char* ivarName) {
    if ([viewModel respondsToSelector:selector]) {
        return ((id (*)(id, SEL))objc_msgSend)(viewModel, selector);
    }

    Ivar ivar = class_getInstanceVariable([viewModel class], ivarName);
    if (!ivar && ivarName[0] != '_') {
        NSString* name = [NSString stringWithUTF8String:ivarName];
        NSString* underscored = [@"_" stringByAppendingString:name];
        ivar = class_getInstanceVariable([viewModel class], underscored.UTF8String);
    }
    return ivar ? object_getIvar(viewModel, ivar) : nil;
}

static BOOL ItemHasTopicBanner(id viewModel) {
    id banner = ItemObjectValue(viewModel, NSSelectorFromString(@"banner"), "banner");
    NSString* bannerClass = banner ? NSStringFromClass([banner classForCoder]) : nil;
    return [bannerClass isEqualToString:@"TFNTwitterURTTimelineStatusTopicBanner"] ||
           [bannerClass hasSuffix:@".URTTimelineStatusTopicBanner"];
}

static BOOL StringContainsTopic(NSString* value) {
    return [value isKindOfClass:[NSString class]] &&
           [[value lowercaseString] containsString:@"topic"];
}

static BOOL StringIsTopicSuggestion(NSString* value) {
    if (!StringContainsTopic(value)) {
        return NO;
    }
    NSString* lower = [value lowercaseString];
    return [lower containsString:@"follow"] || [lower containsString:@"suggest"];
}

static BOOL ShouldHideTimelineItem(id item, BOOL hideWhoToFollow, BOOL hidePrompts,
                                   BOOL hideDiscoverMore, BOOL hideTopics,
                                   BOOL hideTopicsToFollow, BOOL inConversation,
                                   BOOL inProfile) {
    id viewModel = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([viewModel classForCoder]);
    NSString* component = ItemScribeComponent(viewModel);
    NSString* entryID = ItemEntryID(viewModel);

    if (hidePrompts && [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"]) {
        return YES;
    }

    if (hideWhoToFollow && [component isEqualToString:@"suggest_who_to_follow"]) {
        return YES;
    }

    if (hideTopics && ItemHasTopicBanner(viewModel)) {
        return YES;
    }

    BOOL isTopicCollection =
        [className isEqualToString:@"T1TwitterSwift.URTTimelineTopicCollectionViewModel"] ||
        [className isEqualToString:@"TwitterURT.URTTimelineTopicCollectionViewModel"] ||
        [className hasSuffix:@".URTTimelineTopicCollectionViewModel"];
    if (hideTopicsToFollow && inProfile &&
        (isTopicCollection || StringIsTopicSuggestion(component) ||
         StringIsTopicSuggestion(entryID))) {
        return YES;
    }

    if (hideTopics &&
        [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"] &&
        (StringContainsTopic(component) || StringContainsTopic(entryID))) {
        return YES;
    }

    if (hideDiscoverMore && inConversation &&
        [entryID hasPrefix:@"tweetdetailrelatedtweets"]) {
        return YES;
    }

    if (hideWhoToFollow && [entryID containsString:@"who-to-follow"]) {
        return YES;
    }

    return NO;
}

static NSArray* FilteredTimelineSections(TFNItemsDataViewController* dataViewController,
                                         NSArray* sections) {
    BOOL hideWhoToFollow = [BHTSettings boolForKey:@"hide_who_to_follow"];
    BOOL hidePrompts = [BHTSettings boolForKey:@"hide_timeline_prompts"];
    BOOL hideDiscoverMore = [BHTSettings boolForKey:@"hide_discover_more"];
    BOOL hideTopics = [BHTSettings boolForKey:@"hide_topics"];
    BOOL hideTopicsToFollow = [BHTSettings boolForKey:@"hide_topics_to_follow"];
    BOOL inConversation =
        IsInHierarchyOfClass(dataViewController, @"T1ConversationContainerViewController");
    BOOL inProfile = IsInHierarchyOfClass(dataViewController, @"T1ProfileViewController");

    if (!hideWhoToFollow && !hidePrompts && !hideTopics &&
        !hideTopicsToFollow && !(hideDiscoverMore && inConversation)) {
        return sections;
    }

    // Modules can share a section with unrelated items, so filtering is per item;
    // a purely filtered section (like the Discover More one) empties and is dropped.
    BOOL modified = NO;
    NSMutableArray* filteredSections = [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < items.count; i++) {
            if (ShouldHideTimelineItem(items[i], hideWhoToFollow, hidePrompts,
                                       hideDiscoverMore, hideTopics,
                                       hideTopicsToFollow, inConversation,
                                       inProfile)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        modified = YES;
        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? [filteredSections copy] : sections;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig(FilteredTimelineSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredTimelineSections(self, sections), identifiers, animation, completion);
}

%end

%ctor {
    %init;
    Class compatibilityClass = NSClassFromString(@"HomeTimelineContainerViewController");
    Class swiftClass = NSClassFromString(
        @"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController");
    if (compatibilityClass && compatibilityClass != swiftClass) {
        %init(BHTX129HomeContainer);
    }
}
