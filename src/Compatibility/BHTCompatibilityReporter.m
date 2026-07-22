#import "Compatibility/BHTCompatibilityReporter.h"
#import "Core/BHTSettings.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSArray<NSString*>* BHTNavigationEntryClasses;

NSURL* BHTCompatibilityReportURL(void) {
    NSURL* caches = [[[NSFileManager defaultManager]
        URLsForDirectory:NSCachesDirectory
               inDomains:NSUserDomainMask] firstObject];
    return [caches URLByAppendingPathComponent:@"BHTwitter-X12.9-Compatibility.json"];
}

static NSDictionary* BHTProbe(NSString* feature, NSString* className,
                              NSString* selectorName, BOOL classMethod) {
    Class cls = NSClassFromString(className);
    SEL selector = NSSelectorFromString(selectorName);
    BOOL methodPresent = classMethod ? [cls respondsToSelector:selector]
                                     : [cls instancesRespondToSelector:selector];
    return @{
        @"feature": feature,
        @"class": className,
        @"selector": selectorName,
        @"kind": classMethod ? @"class" : @"instance",
        @"classPresent": @(cls != Nil),
        @"methodPresent": @(cls != Nil && methodPresent)
    };
}

static NSArray* BHTRuntimeProbes(void) {
    return @[
        BHTProbe(@"ads", @"TFNItemsDataViewAdapterRegistry", @"dataViewAdapterForItem:", NO),
        BHTProbe(@"ads", @"TFNTwitterAPICommandContext", @"allowPromotedContent", NO),
        BHTProbe(@"ads", @"TFNItemsDataViewController", @"setSections:restoreScrollPosition:", NO),
        BHTProbe(@"ads", @"TFNItemsDataViewController", @"updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:", NO),
        BHTProbe(@"ads", @"T1URTTimelineStatusItemViewModel", @"status", NO),
        BHTProbe(@"ads", @"TwitterURT.URTTimelineGoogleNativeAdViewModel", @"init", NO),
        BHTProbe(@"ads", @"TwitterURT.PromotableTrend", @"promotedTrendID", NO),
        BHTProbe(@"ads", @"T1TwitterSwift.ImmersiveGoogleNativeAdCardViewModel", @"init", NO),
        BHTProbe(@"ads", @"T1TwitterSwift.ExplorePromotedViewModel", @"init", NO),
        BHTProbe(@"ads", @"T1PlayerMediaEntitySessionProducible", @"mediaEntity", NO),
        BHTProbe(@"ads", @"T1PlayerMediaEntitySessionProducible", @"initWithMediaEntity:contentMediaIdentifier:ownerIdentifier:baseScribeItem:promotedContent:", NO),
        BHTProbe(@"ads", @"TFSTwitterSspMetadata", @"isPrerollEligible", NO),
        BHTProbe(@"ads", @"TFSTwitterSspMetadata", @"adTagURL", NO),
        BHTProbe(@"ads", @"TFNTwitterStatus", @"allowDynamicAd", NO),
        BHTProbe(@"ads", @"TFNTwitterStatus", @"isAdsVideoCard", NO),

        BHTProbe(@"images", @"T1ImageDisplayView", @"_tfn_shouldUseHighestQualityImage", NO),
        BHTProbe(@"images", @"T1ImageDisplayView", @"_tfn_shouldUseHighQualityImage", NO),
        BHTProbe(@"images", @"T1SlideshowViewController", @"_t1_shouldDisplayLoadHighQualityImageItemForImageDisplayView:highestQuality:", NO),
        BHTProbe(@"images", @"T1StandardStatusAttachmentViewAdapter", @"displayType", NO),
        BHTProbe(@"images", @"TFNTwitterAccount", @"isLoadingHighestQualityImageVariantPermitted", NO),
        BHTProbe(@"images", @"TFNTwitterAccount", @"photoUploadHighQualityImagesSettingIsVisible", NO),
        BHTProbe(@"video", @"TFSTwitterEntityMediaVideoInfo", @"variants", NO),
        BHTProbe(@"video", @"TFSTwitterEntityMediaVideoInfo", @"primaryUrl", NO),
        BHTProbe(@"video", @"T1VideoDownloadViewModel", @"init", NO),
        BHTProbe(@"video", @"T1TwitterSwift.VideoControlsView", @"init", NO),

        BHTProbe(@"dmDownloads", @"DMConversation.MessageAttachmentView", @"layoutSubviews", NO),
        BHTProbe(@"dmDownloads", @"DMConversation.MessageSaveActionPlugin", @"init", NO),
        BHTProbe(@"dmDownloads", @"TweetMediaAttachments.MultiMediaView", @"inlineMediaInfos", NO),
        BHTProbe(@"messages", @"_TtC14DMConversation26ConversationViewController", @"viewDidLoad", NO),

        BHTProbe(@"likes", @"T1ActivityHistoryBridge", @"makeActivityHistoryViewControllerWithAccount:initialTab:", YES),
        BHTProbe(@"likes", @"T1URTFavoritesViewControllerFactory", @"makeViewControllerWithAccount:", YES),
        BHTProbe(@"likes", @"T1URTFavoritesViewControllerFactory", @"viewControllerWithAccount:", YES),
        BHTProbe(@"likes", @"T1TabbedAppNavigationViewController", @"setVisibleTabEntries:", NO),
        BHTProbe(@"likes", @"T1TabbedAppNavigationViewController", @"recalculateVisiblePanels", NO),
        BHTProbe(@"likes", @"T1TabView", @"scribePage", NO),

        BHTProbe(@"sourceLabels", @"TFNTwitterStatus", @"composerSource", NO),
        BHTProbe(@"sourceLabels", @"T1ConversationFooterTextView", @"updateFooterTextView", NO),
        BHTProbe(@"sourceLabels", @"T1ConversationFooterTextView", @"viewModel", NO),

        BHTProbe(@"home", @"HomeTimelineContainerViewController", @"pinnedTimelinesRepository:didChangeWithPinnedTimelineModels:", NO),
        BHTProbe(@"home", @"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController", @"pinnedTimelinesRepository:didChangeWithPinnedTimelineModels:", NO),
        BHTProbe(@"home", @"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController", @"tfn_supportsTabBarCollapsing", NO),
        BHTProbe(@"home", @"T1TabBarViewController", @"tfn_prefersTabBarPinned", NO),
        BHTProbe(@"home", @"T1FleetLineHeaderController", @"_t1_shouldShowFleetLine", NO),
        BHTProbe(@"home", @"TUIUpdateIndicator", @"_recreatePillControlForContentNotification:", NO),
        BHTProbe(@"home", @"T1TwitterSwift.URTTimelineTopicCollectionViewModel", @"init", NO),

        BHTProbe(@"search", @"TTSRecentSearchesDatastore", @"_tse_setRecentSearch:", NO),
        BHTProbe(@"search", @"TTSRecentSearchesDatastore", @"recentSearches", NO),
        BHTProbe(@"search", @"T1TwitterSwift.GuideContainerViewController", @"viewDidLoad", NO),

        BHTProbe(@"profiles", @"T1ProfileHeaderViewController", @"actionButtonProviders", NO),
        BHTProbe(@"profiles", @"T1ProfileFriendsFollowingViewModel", @"_t1_followCountTextWithLabel:singularLabel:count:highlighted:", NO),
        BHTProbe(@"profiles", @"TFNTwitterCanonicalUser", @"isProfileBioTranslatable", NO),
        BHTProbe(@"profiles", @"TFNTwitterCanonicalUser", @"isProfileTranslationEnabled", NO),
        BHTProbe(@"profiles", @"TTAStatusAuthorView", @"setFollowControlHidden:", NO),
        BHTProbe(@"profiles", @"TFSTwitterRelationship", @"superFollowEligibleState", NO),

        BHTProbe(@"confirmations", @"TTAStatusInlineActionButton", @"didTap", NO),
        BHTProbe(@"appearance", @"TFNUIDefaultFontGroup", @"sharedFontGroup", YES),

        BHTProbe(@"badges", @"TFSTwitterUser", @"isBlueVerified", NO),
        BHTProbe(@"badges", @"TFSTwitterUserSource", @"isBlueVerified", NO),
        BHTProbe(@"badges", @"TFSTwitterTypeaheadUser", @"isBlueVerified", NO),
        BHTProbe(@"badges", @"TFSDirectMessageUser", @"isBlueVerified", NO),
        BHTProbe(@"badges", @"T1TwitterCoreStatusViewModelAdapter", @"isFromUserBlueVerified", NO),

        BHTProbe(@"grok", @"GrokAnalyzeButtonManager", @"init", NO),
        BHTProbe(@"grok", @"TTAStatusInlineAnalyticsButton", @"init", NO),
        BHTProbe(@"grok", @"T1StatusPhotoEditorHandler", @"photoEditorCanEditWithGrok:", NO),

        BHTProbe(@"settings", @"T1GenericSettingsViewController", @"viewWillAppear:", NO),
        BHTProbe(@"settings", @"TFSFeatureSwitches", @"boolForKey:", NO),
        BHTProbe(@"settings", @"TFSInstrumentedFeatureSwitches", @"boolForKey:", NO)
    ];
}

static NSDictionary* BHTSettingsSnapshot(void) {
    NSArray<NSString*>* boolKeys = @[
        @"padlock", @"hide_promoted", @"hide_premium_offer",
        @"no_tab_bar_hiding", @"disable_rtl", @"strip_share_tracking",
        @"expand_tco_links", @"show_scroll_indicator",
        @"tab_bar_theming", @"restore_tab_labels",
        @"restore_launch_animation", @"restore_refresh_sounds",
        @"custom_fonts", @"hide_who_to_follow",
        @"hide_timeline_prompts", @"hide_discover_more", @"hide_topics",
        @"hide_topics_to_follow", @"hide_spaces", @"hide_custom_timelines",
        @"remember_timeline_tab", @"enable_likes_tab",
        @"likes_media_waterfall", @"enable_grok_translations",
        @"hide_grok_analyze", @"hide_grok_sidebar", @"hide_grok_create",
        @"disable_auto_translate", @"download_videos", @"dm_media_downloads",
        @"voice_creation_enabled", @"no_voice_messages", @"old_compose_bar",
        @"dm_reply_later_enabled", @"media_upload_4k_enabled",
        @"custom_voice_upload", @"direct_save", @"auto_highest_load",
        @"force_highest_video_quality", @"force_tweet_full_frame",
        @"disable_video_captions", @"disable_immersive_scroll",
        @"restore_video_timestamp", @"follow_confirm", @"copy_profile_info",
        @"disable_articles", @"disable_highlights", @"hide_blue_verified",
        @"hide_follow_button", @"restore_follow_button", @"square_avatars",
        @"full_profile_counts", @"enable_edit_tweet", @"tweet_confirm",
        @"like_confirm", @"tweet_to_image", @"hide_view_count",
        @"hide_bookmark_button", @"hide_downvote_button",
        @"disable_sensitive_tweet_warnings", @"bypass_age_verification",
        @"reply_sorting", @"restore_reply_context", @"restore_tweet_labels",
        @"no_history", @"hide_trends", @"hide_trend_videos",
        @"restore_twitter_names", @"refresh_pill_label",
        @"color_twitter_icon_in_top_bar", @"disable_screenshot_detection",
        @"hide_screenshot_branding", @"always_open_safari",
        @"new_inapp_webview", @"flex_twitter"
    ];
    NSMutableDictionary* snapshot =
        [NSMutableDictionary dictionaryWithCapacity:boolKeys.count + 1];
    for (NSString* key in boolKeys) {
        snapshot[key] = @([BHTSettings boolForKey:key]);
    }
    snapshot[@"undo_tweet_timeout"] =
        @([BHTSettings integerForKey:@"undo_tweet_timeout"]);
    return [snapshot copy];
}

void BHTWriteCompatibilityReport(void) {
    NSArray* probes = BHTRuntimeProbes();
    NSUInteger available = 0;
    NSMutableDictionary<NSString*, NSMutableDictionary*>* featureSummary =
        [NSMutableDictionary dictionary];
    for (NSDictionary* probe in probes) {
        BOOL present = [probe[@"methodPresent"] boolValue];
        if (present) available++;
        NSString* feature = probe[@"feature"];
        NSMutableDictionary* summary = featureSummary[feature];
        if (!summary) {
            summary = [@{@"checks": @0, @"available": @0} mutableCopy];
            featureSummary[feature] = summary;
        }
        summary[@"checks"] = @([summary[@"checks"] unsignedIntegerValue] + 1);
        summary[@"available"] = @([summary[@"available"] unsignedIntegerValue] + (present ? 1 : 0));
    }

    NSBundle* app = NSBundle.mainBundle;
    NSDictionary* report = @{
        @"generatedAt": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
        @"app": @{
            @"bundleID": app.bundleIdentifier ?: @"",
            @"version": [app objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
            @"build": [app objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
            @"ios": UIDevice.currentDevice.systemVersion ?: @""
        },
        @"tweak": @{
#ifdef NFB_VERSION_STRING
            @"version": @NFB_VERSION_STRING,
#else
            @"version": @"NeoFreeBird",
#endif
#ifdef NFB_COMMIT_STRING
            @"commit": @NFB_COMMIT_STRING,
#else
            @"commit": @"unknown",
#endif
            @"unsafeLoginOverridesIncluded": @NO,
            @"webSessionHarvestingIncluded": @NO
        },
        @"summary": @{
            @"checks": @(probes.count),
            @"available": @(available),
            @"missing": @(probes.count - available)
        },
        @"features": featureSummary,
        @"settings": BHTSettingsSnapshot(),
        @"navigationEntryClasses": BHTNavigationEntryClasses ?: @[],
        @"probes": probes
    };

    NSData* data = [NSJSONSerialization dataWithJSONObject:report
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (data) [data writeToURL:BHTCompatibilityReportURL() options:NSDataWritingAtomic error:nil];
}

void BHTRecordNavigationEntryClasses(NSArray* entries) {
    NSMutableOrderedSet<NSString*>* names = [NSMutableOrderedSet orderedSet];
    for (id entry in entries) {
        NSString* name = NSStringFromClass([entry class]);
        if (name.length) [names addObject:name];
    }
    BHTNavigationEntryClasses = names.array;
    BHTWriteCompatibilityReport();
}
