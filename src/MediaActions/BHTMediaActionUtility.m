#import "MediaActions/BHTMediaActionUtility.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>
#import "Core/BHTBundle.h"
#import "CustomTabBar/CustomTabBarUtility.h"

NSString* const BHTMediaActionLikeIdentifier = @"like";
NSString* const BHTMediaActionCopyLinkIdentifier = @"copy_link";
NSString* const BHTMediaActionReactIdentifier = @"react";
NSString* const BHTMediaActionOfflineIdentifier = @"offline";
NSString* const BHTMediaActionEditPhotoIdentifier = @"edit_photo";
NSString* const BHTMediaActionGrokEditIdentifier = @"grok_edit";
NSString* const BHTMediaActionDownloadIdentifier = @"download";
NSString* const BHTMediaActionShareFileIdentifier = @"share_file";
NSString* const BHTMediaActionShareViaIdentifier = @"share_via";
NSString* const BHTMediaActionPreferencesDidChangeNotification =
    @"BHTMediaActionPreferencesDidChangeNotification";

static char kBHTMediaActionIdentifierKey;

static NSString* BHTMediaActionKindSuffix(BHTMediaActionKind kind) {
    switch (kind) {
        case BHTMediaActionKindPhoto:
            return @"photo";
        case BHTMediaActionKindGIF:
            return @"gif";
        case BHTMediaActionKindVideo:
        default:
            return @"video";
    }
}

static NSString* BHTMediaActionOrderKey(BHTMediaActionKind kind) {
    return [NSString
        stringWithFormat:@"bht_media_actions_%@_order",
                         BHTMediaActionKindSuffix(kind)];
}

static NSString* BHTMediaActionHiddenKey(BHTMediaActionKind kind) {
    return [NSString
        stringWithFormat:@"bht_media_actions_%@_hidden",
                         BHTMediaActionKindSuffix(kind)];
}

static NSString* BHTMediaActionStringValue(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }
    if ([value isKindOfClass:NSAttributedString.class]) {
        return [(NSAttributedString*)value string];
    }
    return nil;
}

static NSString* BHTMediaActionTitle(id item) {
    if (!item) return nil;

    // X has renamed TFNActionItem's public-facing title accessor between
    // releases. Probe only object-returning selectors and guard every fallback
    // so an app update cannot turn menu customization into a crash.
    NSArray<NSString*>* selectors =
        @[@"title", @"actionTitle", @"displayTitle", @"text",
          @"accessibilityLabel"];
    for (NSString* selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![item respondsToSelector:selector]) continue;
        NSMethodSignature* signature =
            [item methodSignatureForSelector:selector];
        const char* returnType = signature.methodReturnType;
        while (returnType &&
               strchr("rnNoORV", returnType[0]) != NULL) {
            returnType++;
        }
        if (!returnType || returnType[0] != '@') continue;
        @try {
            id value =
                ((id(*)(id, SEL))objc_msgSend)(item, selector);
            NSString* title = BHTMediaActionStringValue(value);
            if (title.length) return title;
        } @catch (__unused NSException* exception) {
        }
    }

    // Some TFNActionItem builds expose the title only through KVC-compatible
    // storage. Keep this narrow and exception-safe.
    for (NSString* key in @[@"title", @"actionTitle", @"displayTitle",
                             @"text"]) {
        @try {
            NSString* title =
                BHTMediaActionStringValue([item valueForKey:key]);
            if (title.length) return title;
        } @catch (__unused NSException* exception) {
        }
    }
    return nil;
}

static NSString* BHTMediaActionNativeIdentifier(id item) {
    for (NSString* selectorName in
         @[@"actionIdentifier", @"actionId", @"identifier"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![item respondsToSelector:selector]) continue;
        NSMethodSignature* signature =
            [item methodSignatureForSelector:selector];
        const char* returnType = signature.methodReturnType;
        while (returnType &&
               strchr("rnNoORV", returnType[0]) != NULL) {
            returnType++;
        }
        if (!returnType || returnType[0] != '@') continue;
        @try {
            NSString* identifier = BHTMediaActionStringValue(
                ((id(*)(id, SEL))objc_msgSend)(item, selector));
            if (identifier.length) {
                NSString* lowered = identifier.lowercaseString;
                NSArray<NSString*>* components =
                    [lowered componentsSeparatedByCharactersInSet:
                                 NSCharacterSet
                                     .alphanumericCharacterSet
                                     .invertedSet];
                return [components componentsJoinedByString:@""];
            }
        } @catch (__unused NSException* exception) {
        }
    }
    return nil;
}

static NSString* BHTNormalizedMediaActionTitle(NSString* title) {
    if (!title.length) return @"";
    NSString* normalized =
        [[title stringByFoldingWithOptions:
                    NSDiacriticInsensitiveSearch |
                    NSWidthInsensitiveSearch
                               locale:NSLocale.currentLocale] lowercaseString];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"…"
                                                        withString:@"..."];
    return [normalized
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL BHTTitleContainsEvery(NSString* title,
                                  NSArray<NSString*>* fragments) {
    for (NSString* fragment in fragments) {
        if ([title rangeOfString:fragment].location == NSNotFound) return NO;
    }
    return YES;
}

static NSString* BHTMediaActionInferredIdentifier(id item) {
    NSString* explicit =
        objc_getAssociatedObject(item, &kBHTMediaActionIdentifierKey);
    if (explicit.length) return explicit;

    NSString* nativeIdentifier =
        BHTMediaActionNativeIdentifier(item);
    if ([nativeIdentifier containsString:@"offline"]) {
        return BHTMediaActionOfflineIdentifier;
    }
    if ([nativeIdentifier containsString:@"reactwith"]) {
        return BHTMediaActionReactIdentifier;
    }
    if ([nativeIdentifier containsString:@"copyphoto"] ||
        [nativeIdentifier containsString:@"copyvideo"] ||
        [nativeIdentifier containsString:@"copygif"] ||
        [nativeIdentifier containsString:@"copylink"]) {
        return BHTMediaActionCopyLinkIdentifier;
    }
    if ([nativeIdentifier containsString:@"editphoto"]) {
        return BHTMediaActionEditPhotoIdentifier;
    }
    if ([nativeIdentifier containsString:@"grokimagine"] ||
        [nativeIdentifier containsString:@"grokedit"] ||
        [nativeIdentifier containsString:@"grokcreate"]) {
        return BHTMediaActionGrokEditIdentifier;
    }
    if ([nativeIdentifier containsString:@"tweetphoto"] ||
        [nativeIdentifier containsString:@"tweetvideo"] ||
        [nativeIdentifier containsString:@"tweetgif"]) {
        return BHTMediaActionLikeIdentifier;
    }
    if ([nativeIdentifier containsString:@"savephoto"] ||
        [nativeIdentifier containsString:@"downloadvideo"] ||
        [nativeIdentifier containsString:@"downloadgif"]) {
        return BHTMediaActionDownloadIdentifier;
    }
    if ([nativeIdentifier containsString:@"sharevia"]) {
        return BHTMediaActionShareViaIdentifier;
    }

    NSString* title =
        BHTNormalizedMediaActionTitle(BHTMediaActionTitle(item));
    if (!title.length) return nil;

    if ([title containsString:@"offline"]) {
        return BHTMediaActionOfflineIdentifier;
    }
    if ([title containsString:@"react"] &&
        ([title containsString:@"video"] ||
         [title containsString:@"gif"] ||
         [title containsString:@"photo"] ||
         [title containsString:@"media"])) {
        return BHTMediaActionReactIdentifier;
    }
    if (([title hasPrefix:@"tweet "] ||
         [title hasPrefix:@"post "]) &&
        ([title containsString:@"photo"] ||
         [title containsString:@"video"] ||
         [title containsString:@"gif"] ||
         [title containsString:@"media"])) {
        // Keep the established internal identifier so existing Beta 12 menu
        // preferences migrate cleanly. The editor now labels this native row
        // as Tweet Photo/Video/GIF instead of the misleading "Like".
        return BHTMediaActionLikeIdentifier;
    }
    if ([title containsString:@"copy"] &&
        ([title containsString:@"link"] ||
         [title containsString:@"photo"] ||
         [title containsString:@"video"] ||
         [title containsString:@"gif"] ||
         [title containsString:@"media"])) {
        return BHTMediaActionCopyLinkIdentifier;
    }
    if ([title containsString:@"edit"] &&
        [title containsString:@"photo"]) {
        return BHTMediaActionEditPhotoIdentifier;
    }
    if ([title containsString:@"grok"] &&
        ([title containsString:@"edit"] ||
         [title containsString:@"create"] ||
         [title containsString:@"imagine"])) {
        return BHTMediaActionGrokEditIdentifier;
    }
    if (([title hasPrefix:@"like "] || [title hasPrefix:@"unlike "] ||
         [title isEqualToString:@"like"] ||
         [title isEqualToString:@"unlike"]) &&
        ![title containsString:@"reaction"]) {
        return BHTMediaActionLikeIdentifier;
    }
    if ([title containsString:@"share"] &&
        ([title containsString:@" file"] ||
         [title containsString:@"without saving"] ||
         [title containsString:@"direct share"])) {
        return BHTMediaActionShareFileIdentifier;
    }
    NSString* localizedShareVia = BHTNormalizedMediaActionTitle(
        [[BHTBundle sharedBundle]
            localizedTwitterStringForKey:@"SHARE_VIA_ACTION"]);
    if ((localizedShareVia.length > 0 &&
         [title isEqualToString:localizedShareVia]) ||
        BHTTitleContainsEvery(title, @[@"share", @"via"]) ||
        [title containsString:@"share..."] ||
        [title isEqualToString:@"share"] ||
        [title containsString:@"more share options"]) {
        return BHTMediaActionShareViaIdentifier;
    }
    if ([title containsString:@"download"] ||
        BHTTitleContainsEvery(title, @[@"save", @"photos"]) ||
        [title hasPrefix:@"save video"] ||
        [title hasPrefix:@"save gif"] ||
        [title hasPrefix:@"save photo"]) {
        return BHTMediaActionDownloadIdentifier;
    }
    return nil;
}

static BOOL BHTMediaActionHasExplicitIdentifier(id item) {
    return [objc_getAssociatedObject(item,
                                     &kBHTMediaActionIdentifierKey) length] > 0;
}

void BHTMediaActionSetIdentifier(id item, NSString* identifier) {
    if (!item || !identifier.length) return;
    objc_setAssociatedObject(item, &kBHTMediaActionIdentifierKey, identifier,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
}

NSArray* BHTMediaActionApplyPreferences(NSArray* items,
                                        BHTMediaActionKind kind) {
    if (![items isKindOfClass:NSArray.class] || items.count == 0) {
        return items ?: @[];
    }

    NSArray<NSString*>* ordered =
        [BHTMediaActionUtility orderedActionIdentifiersForKind:kind];
    NSSet<NSString*>* known =
        [NSSet setWithArray:
                   [BHTMediaActionUtility
                       canonicalActionIdentifiersForKind:kind]];
    NSSet<NSString*>* hidden =
        [NSSet setWithArray:
                   [BHTMediaActionUtility
                       hiddenActionIdentifiersForKind:kind]];

    NSMutableDictionary<NSString*, NSNumber*>* ranks =
        [NSMutableDictionary dictionary];
    [ordered enumerateObjectsUsingBlock:^(NSString* identifier,
                                          NSUInteger index,
                                          __unused BOOL* stop) {
        ranks[identifier] = @(index);
    }];

    NSMutableDictionary<NSString*, NSDictionary*>* preferredByIdentifier =
        [NSMutableDictionary dictionary];
    NSMapTable* identifierByItem =
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
                             valueOptions:NSPointerFunctionsStrongMemory];
    [items enumerateObjectsUsingBlock:^(id item, NSUInteger index,
                                        __unused BOOL* stop) {
        NSString* identifier = BHTMediaActionInferredIdentifier(item);
        if (![known containsObject:identifier]) return;
        [identifierByItem setObject:identifier forKey:item];
        NSDictionary* candidate = @{
            @"item": item,
            @"identifier": identifier,
            @"sourceIndex": @(index),
            @"explicit": @(BHTMediaActionHasExplicitIdentifier(item))
        };
        NSDictionary* existing = preferredByIdentifier[identifier];
        // X can expose a Blue-gated stock Download action while NeoFreeBird
        // injects its working replacement. Keep one row per known identifier,
        // preferring the explicitly tagged tweak action over a title-inferred
        // stock duplicate.
        if (!existing ||
            ([candidate[@"explicit"] boolValue] &&
             ![existing[@"explicit"] boolValue])) {
            preferredByIdentifier[identifier] = candidate;
        }
    }];

    NSMutableArray<NSDictionary*>* recognized =
        [NSMutableArray array];
    for (NSDictionary* candidate in preferredByIdentifier.allValues) {
        if (![hidden containsObject:candidate[@"identifier"]]) {
            [recognized addObject:candidate];
        }
    }

    [recognized sortUsingComparator:^NSComparisonResult(
                    NSDictionary* left, NSDictionary* right) {
        NSInteger leftRank =
            [ranks[left[@"identifier"]] integerValue];
        NSInteger rightRank =
            [ranks[right[@"identifier"]] integerValue];
        if (leftRank < rightRank) return NSOrderedAscending;
        if (leftRank > rightRank) return NSOrderedDescending;
        return [left[@"sourceIndex"] compare:right[@"sourceIndex"]];
    }];

    // Fill the original known-action slots with the configured known-action
    // order. Unknown, future-X, and cancel items remain untouched and in their
    // original relative order. Hidden known slots simply collapse.
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:items.count];
    NSUInteger nextRecognized = 0;
    for (id item in items) {
        NSString* identifier = [identifierByItem objectForKey:item];
        if (!identifier) {
            [result addObject:item];
            continue;
        }
        if (nextRecognized < recognized.count) {
            [result addObject:recognized[nextRecognized++][@"item"]];
        }
    }
    return [result copy];
}

@implementation BHTMediaActionUtility

+ (NSArray<NSString*>*)canonicalActionIdentifiers {
    return @[
        BHTMediaActionLikeIdentifier,
        BHTMediaActionCopyLinkIdentifier,
        BHTMediaActionReactIdentifier,
        BHTMediaActionOfflineIdentifier,
        BHTMediaActionEditPhotoIdentifier,
        BHTMediaActionGrokEditIdentifier,
        BHTMediaActionDownloadIdentifier,
        BHTMediaActionShareFileIdentifier,
        BHTMediaActionShareViaIdentifier
    ];
}

+ (NSArray<NSString*>*)canonicalActionIdentifiersForKind:
    (BHTMediaActionKind)kind {
    if (kind == BHTMediaActionKindPhoto) {
        return @[
            BHTMediaActionLikeIdentifier,
            BHTMediaActionCopyLinkIdentifier,
            BHTMediaActionDownloadIdentifier,
            BHTMediaActionReactIdentifier,
            BHTMediaActionEditPhotoIdentifier,
            BHTMediaActionGrokEditIdentifier,
            BHTMediaActionShareFileIdentifier,
            BHTMediaActionShareViaIdentifier
        ];
    }
    return @[
        BHTMediaActionLikeIdentifier,
        BHTMediaActionCopyLinkIdentifier,
        BHTMediaActionReactIdentifier,
        BHTMediaActionOfflineIdentifier,
        BHTMediaActionDownloadIdentifier,
        BHTMediaActionGrokEditIdentifier,
        BHTMediaActionShareFileIdentifier,
        BHTMediaActionShareViaIdentifier
    ];
}

+ (NSArray<NSDictionary*>*)availableActionsForKind:
    (BHTMediaActionKind)kind {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSString* tweetTitleKey =
        kind == BHTMediaActionKindPhoto
            ? @"MEDIA_ACTION_TWEET_PHOTO_TITLE"
            : (kind == BHTMediaActionKindGIF
                   ? @"MEDIA_ACTION_TWEET_GIF_TITLE"
                   : @"MEDIA_ACTION_TWEET_VIDEO_TITLE");
    NSString* copyTitleKey =
        kind == BHTMediaActionKindPhoto
            ? @"MEDIA_ACTION_COPY_PHOTO_TITLE"
            : (kind == BHTMediaActionKindGIF
                   ? @"MEDIA_ACTION_COPY_GIF_LINK_TITLE"
                   : @"MEDIA_ACTION_COPY_VIDEO_LINK_TITLE");
    NSDictionary<NSString*, NSDictionary*>* metadata = @{
        BHTMediaActionLikeIdentifier: @{
            TabPageKey: BHTMediaActionLikeIdentifier,
            TabTitleKey:
                [bundle localizedStringForKey:tweetTitleKey],
            TabImageKey: @"sf:square.and.pencil"
        },
        BHTMediaActionCopyLinkIdentifier: @{
            TabPageKey: BHTMediaActionCopyLinkIdentifier,
            TabTitleKey:
                [bundle localizedStringForKey:copyTitleKey],
            TabImageKey: @"sf:link"
        },
        BHTMediaActionReactIdentifier: @{
            TabPageKey: BHTMediaActionReactIdentifier,
            TabTitleKey:
                [bundle localizedStringForKey:@"MEDIA_ACTION_REACT_TITLE"],
            TabImageKey: @"sf:arrowshape.turn.up.right"
        },
        BHTMediaActionOfflineIdentifier: @{
            TabPageKey: BHTMediaActionOfflineIdentifier,
            TabTitleKey:
                [bundle localizedStringForKey:@"MEDIA_ACTION_OFFLINE_TITLE"],
            TabImageKey: @"sf:arrow.down.circle"
        },
        BHTMediaActionEditPhotoIdentifier: @{
            TabPageKey: BHTMediaActionEditPhotoIdentifier,
            TabTitleKey:
                [bundle localizedStringForKey:
                            @"MEDIA_ACTION_EDIT_PHOTO_TITLE"],
            TabImageKey: @"sf:pencil"
        },
        BHTMediaActionGrokEditIdentifier: @{
            TabPageKey: BHTMediaActionGrokEditIdentifier,
            TabTitleKey:
                [bundle localizedStringForKey:
                            @"MEDIA_ACTION_GROK_EDIT_TITLE"],
            TabImageKey: @"sf:sparkles"
        },
        BHTMediaActionDownloadIdentifier: @{
            TabPageKey: BHTMediaActionDownloadIdentifier,
            TabTitleKey:
                [bundle localizedStringForKey:@"MEDIA_ACTION_DOWNLOAD_TITLE"],
            TabImageKey: @"sf:arrow.down.to.line"
        },
        BHTMediaActionShareFileIdentifier: @{
            TabPageKey: BHTMediaActionShareFileIdentifier,
            TabTitleKey:
                [bundle localizedStringForKey:@"MEDIA_ACTION_SHARE_FILE_TITLE"],
            TabImageKey: @"sf:paperplane"
        },
        BHTMediaActionShareViaIdentifier: @{
            TabPageKey: BHTMediaActionShareViaIdentifier,
            TabTitleKey:
                [bundle localizedStringForKey:@"MEDIA_ACTION_SHARE_VIA_TITLE"],
            TabImageKey: @"sf:square.and.arrow.up"
        }
    };
    NSMutableArray<NSDictionary*>* actions = [NSMutableArray array];
    for (NSString* identifier in
         [self canonicalActionIdentifiersForKind:kind]) {
        NSDictionary* item = metadata[identifier];
        if (item) [actions addObject:item];
    }
    return [actions copy];
}

+ (NSDictionary*)metadataForIdentifier:(NSString*)identifier
                                   kind:(BHTMediaActionKind)kind {
    for (NSDictionary* metadata in [self availableActionsForKind:kind]) {
        if ([metadata[TabPageKey] isEqualToString:identifier]) {
            return metadata;
        }
    }
    return nil;
}

+ (NSArray<NSString*>*)sanitizedIdentifiers:(NSArray*)source
                             appendMissing:(BOOL)appendMissing
                                      kind:(BHTMediaActionKind)kind {
    NSArray<NSString*>* canonical =
        [self canonicalActionIdentifiersForKind:kind];
    NSSet<NSString*>* valid = [NSSet setWithArray:canonical];
    NSMutableArray<NSString*>* sanitized = [NSMutableArray array];
    for (id candidate in source) {
        if ([candidate isKindOfClass:NSString.class] &&
            [valid containsObject:candidate] &&
            ![sanitized containsObject:candidate]) {
            [sanitized addObject:candidate];
        }
    }
    if (appendMissing) {
        for (NSString* identifier in canonical) {
            if ([sanitized containsObject:identifier]) continue;
            NSUInteger canonicalIndex =
                [canonical indexOfObject:identifier];
            NSUInteger insertionIndex = sanitized.count;
            for (NSUInteger index = canonicalIndex + 1;
                 index < canonical.count; index++) {
                NSUInteger existingIndex =
                    [sanitized indexOfObject:canonical[index]];
                if (existingIndex != NSNotFound) {
                    insertionIndex = existingIndex;
                    break;
                }
            }
            [sanitized insertObject:identifier
                            atIndex:insertionIndex];
        }
    }
    return [sanitized copy];
}

+ (NSArray<NSString*>*)orderedActionIdentifiersForKind:
    (BHTMediaActionKind)kind {
    NSArray* saved = [[NSUserDefaults standardUserDefaults]
        arrayForKey:BHTMediaActionOrderKey(kind)];
    return [self sanitizedIdentifiers:
                     (saved ?: [self
                                   canonicalActionIdentifiersForKind:kind])
                           appendMissing:YES
                                    kind:kind];
}

+ (NSArray<NSString*>*)hiddenActionIdentifiersForKind:
    (BHTMediaActionKind)kind {
    NSArray* saved = [[NSUserDefaults standardUserDefaults]
        arrayForKey:BHTMediaActionHiddenKey(kind)];
    return [self sanitizedIdentifiers:(saved ?: @[])
                         appendMissing:NO
                                  kind:kind];
}

+ (NSArray<NSString*>*)visibleActionIdentifiersForKind:
    (BHTMediaActionKind)kind {
    NSSet<NSString*>* hidden =
        [NSSet setWithArray:[self hiddenActionIdentifiersForKind:kind]];
    NSMutableArray<NSString*>* visible = [NSMutableArray array];
    for (NSString* identifier in
         [self orderedActionIdentifiersForKind:kind]) {
        if (![hidden containsObject:identifier]) {
            [visible addObject:identifier];
        }
    }
    return [visible copy];
}

+ (void)setOrderedActionIdentifiers:(NSArray<NSString*>*)ordered
            hiddenActionIdentifiers:(NSArray<NSString*>*)hidden
                                kind:(BHTMediaActionKind)kind {
    NSArray<NSString*>* safeOrder =
        [self sanitizedIdentifiers:ordered
                     appendMissing:YES
                              kind:kind];
    NSArray<NSString*>* safeHidden =
        [self sanitizedIdentifiers:hidden
                     appendMissing:NO
                              kind:kind];
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:safeOrder forKey:BHTMediaActionOrderKey(kind)];
    [defaults setObject:safeHidden forKey:BHTMediaActionHiddenKey(kind)];
    [defaults synchronize];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BHTMediaActionPreferencesDidChangeNotification
                      object:nil
                    userInfo:@{@"kind": @(kind)}];
}

+ (void)resetPreferencesForKind:(BHTMediaActionKind)kind {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:BHTMediaActionOrderKey(kind)];
    [defaults removeObjectForKey:BHTMediaActionHiddenKey(kind)];
    [defaults synchronize];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BHTMediaActionPreferencesDidChangeNotification
                      object:nil
                    userInfo:@{@"kind": @(kind)}];
}

@end
