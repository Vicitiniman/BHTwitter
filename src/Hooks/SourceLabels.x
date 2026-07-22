//
//  SourceLabels.x
//  NeoFreeBird
//
//  X 12.9 exposes the source on TFNTwitterStatus again.  Keep this entirely
//  on-device: no web session, cookies, bearer token, or private GraphQL query.
//

#import "HookHelpers.h"

static char kBHTFooterBaseTimeKey;
static char kBHTFooterSourceKey;

static id BHTSafeValueForKey(id object, NSString* key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static id BHTStatusFromFooterViewModel(id viewModel) {
    if (!viewModel) return nil;

    for (NSString* selectorName in @[@"tweet", @"status", @"displayedStatus", @"twitterStatus"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([viewModel respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(viewModel, selector);
            if (value) return value;
        }
    }

    for (NSString* key in @[@"tweet", @"status", @"displayedStatus", @"twitterStatus"]) {
        id value = BHTSafeValueForKey(viewModel, key);
        if (value) return value;
    }
    return nil;
}

static NSString* BHTPlainSourceLabel(id rawSource) {
    if (!rawSource || rawSource == NSNull.null) return nil;

    NSString* source = nil;
    if ([rawSource isKindOfClass:[NSString class]]) {
        source = rawSource;
    } else {
        for (NSString* key in @[@"name", @"displayName", @"source", @"value"]) {
            id candidate = BHTSafeValueForKey(rawSource, key);
            if ([candidate isKindOfClass:[NSString class]] && [candidate length] > 0) {
                source = candidate;
                break;
            }
        }
    }
    if (source.length == 0) return nil;

    // composerSource commonly contains an anchor tag.  NSAttributedString's
    // HTML importer is unnecessary here and can briefly block the main thread.
    NSRegularExpression* tags =
        [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>"
                                                  options:0
                                                    error:nil];
    source = [tags stringByReplacingMatchesInString:source
                                            options:0
                                              range:NSMakeRange(0, source.length)
                                       withTemplate:@""];
    source = [source stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    source = [source stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    source = [source stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    source = [source stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return source.length > 0 ? source : nil;
}

static NSString* BHTComposerSourceForStatus(id status) {
    if (!status) return nil;
    SEL selector = NSSelectorFromString(@"composerSource");
    id source = nil;
    if ([status respondsToSelector:selector]) {
        source = ((id (*)(id, SEL))objc_msgSend)(status, selector);
    } else {
        source = BHTSafeValueForKey(status, @"composerSource");
    }
    return BHTPlainSourceLabel(source);
}

%hook T1ConversationFooterTextView

- (void)updateFooterTextView {
    @try {
        id footerItem = BHTSafeValueForKey(self, @"footerItem");
        NSString* currentTime = BHTSafeValueForKey(footerItem, @"timeAgo");
        NSString* previousSource = objc_getAssociatedObject(footerItem, &kBHTFooterSourceKey);
        NSString* baseTime = objc_getAssociatedObject(footerItem, &kBHTFooterBaseTimeKey);

        // A reused footer item may already contain the source that this hook
        // appended on its previous render.  Preserve only the native base text.
        if (baseTime.length == 0 ||
            (previousSource.length > 0 && ![currentTime containsString:previousSource])) {
            baseTime = currentTime;
            objc_setAssociatedObject(footerItem, &kBHTFooterBaseTimeKey, baseTime,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
        }

        if (![BHTSettings boolForKey:@"restore_tweet_labels"]) {
            if (footerItem && baseTime.length > 0 && ![currentTime isEqualToString:baseTime]) {
                [footerItem setValue:baseTime forKey:@"timeAgo"];
            }
            objc_setAssociatedObject(footerItem, &kBHTFooterSourceKey, nil,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
            %orig;
            return;
        }

        id viewModel = BHTSafeValueForKey(self, @"viewModel");
        id status = BHTStatusFromFooterViewModel(viewModel);
        NSString* source = BHTComposerSourceForStatus(status);
        if (footerItem && baseTime.length > 0 && source.length > 0) {
            [footerItem setValue:[NSString stringWithFormat:@"%@ · %@", baseTime, source]
                          forKey:@"timeAgo"];
            objc_setAssociatedObject(footerItem, &kBHTFooterSourceKey, source,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    } @catch (__unused NSException* exception) {
        // Private model layouts can move between builds; a missing source must
        // never prevent the native footer from rendering.
    }

    %orig;
}

%end
