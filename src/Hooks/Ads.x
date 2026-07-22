//
//  Ads.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// Timeline items are removed from the section data before it reaches the data
// view controller, so no empty cells or gaps are left behind. This covers every
// timeline surface (home, profile, search, conversations) regardless of whether
// it renders through a table view or the newer diffable collection view path.

// The promoted state of a status item is only reachable through its Swift-side
// `status` stored property, which is still registered as an ObjC ivar.
static BOOL StatusItemIsPromoted(id item) {
    TFNTwitterStatus* status = nil;
    if ([item respondsToSelector:@selector(status)]) {
        status = ((id (*)(id, SEL))objc_msgSend)(item, @selector(status));
    }

    Ivar statusIvar = class_getInstanceVariable([item class], "status");
    if (!statusIvar) {
        statusIvar = class_getInstanceVariable([item class], "_status");
    }
    if (!statusIvar) {
        return [status respondsToSelector:@selector(isPromoted)] &&
               status.isPromoted;
    }

    status = status ?: object_getIvar(item, statusIvar);
    return [status respondsToSelector:@selector(isPromoted)] && status.isPromoted;
}

// Promoted trends and event summary heroes (the image ads at the top of
// explore) carry their promotion in the Swift-side `promotedContent` stored
// property, which isn't always reflected in the scribe item.
static BOOL ItemHasPromotedContent(id item) {
    if ([item respondsToSelector:@selector(promotedContent)] &&
        ((id (*)(id, SEL))objc_msgSend)(item, @selector(promotedContent)) != nil) {
        return YES;
    }

    Ivar promotedIvar =
        class_getInstanceVariable([item class], "promotedContent");
    if (!promotedIvar) {
        promotedIvar = class_getInstanceVariable([item class], "_promotedContent");
    }
    return promotedIvar && object_getIvar(item, promotedIvar) != nil;
}

static BOOL ItemHasPromotedTrendID(id item) {
    if ([item respondsToSelector:@selector(promotedTrendID)]) {
        NSMethodSignature* signature =
            [item methodSignatureForSelector:@selector(promotedTrendID)];
        const char* returnType = signature.methodReturnType;
        if (returnType && returnType[0] == '@') {
            id trendID = ((id (*)(id, SEL))objc_msgSend)(
                item, @selector(promotedTrendID));
            return trendID != nil && ![trendID isEqual:@0] &&
                   ![trendID isEqual:@""];
        }
        if (signature.methodReturnLength > 0 &&
            signature.methodReturnLength <= sizeof(unsigned long long)) {
            unsigned long long value =
                ((unsigned long long (*)(id, SEL))objc_msgSend)(
                    item, @selector(promotedTrendID));
            return value != 0;
        }
    }

    Ivar ivar = class_getInstanceVariable([item class], "promotedTrendID");
    if (!ivar) {
        ivar = class_getInstanceVariable([item class], "_promotedTrendID");
    }
    if (!ivar) return NO;

    const char* type = ivar_getTypeEncoding(ivar);
    if (!type) return NO;
    if (type && type[0] == '@') {
        id trendID = object_getIvar(item, ivar);
        return trendID != nil && ![trendID isEqual:@0] &&
               ![trendID isEqual:@""];
    }

    unsigned long long value = 0;
    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, NULL);
    uint8_t* bytes = (uint8_t*)(__bridge void*)item + ivar_getOffset(ivar);
    memcpy(&value, bytes, MIN(sizeof(value), size));
    return value != 0;
}

static BOOL ScribeItemIsPromoted(id item) {
    if (![item respondsToSelector:@selector(scribeItem)]) {
        return NO;
    }

    NSDictionary* scribeItem = [item performSelector:@selector(scribeItem)];
    return [scribeItem isKindOfClass:[NSDictionary class]] &&
           scribeItem[@"promoted_id"] != nil;
}

static BOOL ShouldHideItem(id item, NSString* location) {
    item = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([item classForCoder]);

    if ([BHTSettings boolForKey:@"hide_promoted"]) {
        if ([item respondsToSelector:@selector(isPromoted)] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(item, @selector(isPromoted))) {
            return YES;
        }

        if ([item
                isKindOfClass:objc_getClass("T1URTTimelineStatusItemViewModel")] &&
            StatusItemIsPromoted(item)) {
            return YES;
        }

        if ([className isEqualToString:
                           @"TwitterURT.URTTimelineGoogleNativeAdViewModel"] ||
            [className isEqualToString:@"TwitterURT.PromotableTrend"] ||
            [className isEqualToString:
                           @"T1TwitterSwift.ImmersiveGoogleNativeAdCardViewModel"] ||
            [className isEqualToString:
                           @"T1TwitterSwift.ExplorePromotedViewModel"]) {
            return YES;
        }

        if (([className isEqualToString:@"TwitterURT.URTTimelineTrendViewModel"] ||
             [className
                 isEqualToString:@"TwitterURT.URTTimelineEventSummaryViewModel"]) &&
            (ScribeItemIsPromoted(item) || ItemHasPromotedContent(item) ||
             ItemHasPromotedTrendID(item))) {
            return YES;
        }

        if (ItemHasPromotedContent(item) || ItemHasPromotedTrendID(item)) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_premium_offer"]) {
        if ([className
                isEqualToString:@"TwitterURT.URTTimelineMessageItemViewModel"]) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_trend_videos"] &&
        [location isEqualToString:@"OTHER"]) {
        if ([className
                isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
            return YES;
        }
    }

    return NO;
}

static NSArray* FilteredSections(TFNItemsDataViewController* dataViewController,
                                 NSArray* sections) {
    if (!([BHTSettings boolForKey:@"hide_promoted"] ||
          [BHTSettings boolForKey:@"hide_premium_offer"] ||
          [BHTSettings boolForKey:@"hide_trend_videos"])) {
        return sections;
    }

    NSString* location =
        [dataViewController respondsToSelector:@selector(adDisplayLocation)]
            ? dataViewController.adDisplayLocation
            : nil;

    BOOL modified = NO;
    NSMutableArray* filteredSections =
        [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSUInteger count = items.count;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < count; i++) {
            if (ShouldHideItem(items[i], location)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        modified = YES;

        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? filteredSections : sections;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections
    restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig(FilteredSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredSections(self, sections), identifiers, animation,
              completion);
}

%end

// X 12.9 asks the adapter registry for an adapter before a number of timeline
// items reach the section setters above.  Refusing a promoted item here closes
// that earlier path; the section filter remains as the structural fallback.
%hook TFNItemsDataViewAdapterRegistry

- (id)dataViewAdapterForItem:(id)item {
    if ([BHTSettings boolForKey:@"hide_promoted"] &&
        ShouldHideItem(item, nil)) {
        return nil;
    }
    return %orig;
}

%end

// X 12.9's video session initializer accepts ad metadata separately from the
// playable media entity. Keep the real media untouched and strip only that
// promoted payload, preventing preroll/session ad construction.
%hook T1PlayerMediaEntitySessionProducible

- (id)initWithMediaEntity:(id)mediaEntity
    contentMediaIdentifier:(id)contentMediaIdentifier
           ownerIdentifier:(id)ownerIdentifier
            baseScribeItem:(id)baseScribeItem
         promotedContent:(id)promotedContent {
    if ([BHTSettings boolForKey:@"hide_promoted"]) {
        promotedContent = nil;
    }
    return %orig(mediaEntity, contentMediaIdentifier, ownerIdentifier,
                 baseScribeItem, promotedContent);
}

%end

%hook TFSTwitterSspMetadata

- (BOOL)isPrerollEligible {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (id)adTagURL {
    return [BHTSettings boolForKey:@"hide_promoted"] ? nil : %orig;
}

%end

%hook TFNTwitterStatus

- (BOOL)isPoliticalAd {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isIssueAd {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isRTBCreative {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isPrerollContent {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isAdsVideoCard {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)allowDynamicAd {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (id)sspMetadata {
    return [BHTSettings boolForKey:@"hide_promoted"] ? nil : %orig;
}

- (id)promotedContent {
    return [BHTSettings boolForKey:@"hide_promoted"] ? nil : %orig;
}

- (_Bool)isCardHidden {
    return ([BHTSettings boolForKey:@"hide_promoted"] && [self isPromoted])
               ? true
               : %orig;
}

%end
