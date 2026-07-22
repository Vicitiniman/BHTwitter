//
//  RefreshSounds.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Restore Pull-To-Refresh Sounds

// 12.3's TFNPullToRefreshControl has no built-in sound path (no soundEffects gate,
// no bundled psst/pop assets), so we play the tweak-bundled sounds ourselves at the
// control's state transitions.

typedef NS_ENUM(NSInteger, RefreshSound) {
    RefreshSoundPull = 0, // Dragging down past the threshold to refresh
    RefreshSoundPop = 1   // Manual refresh completed
};

@interface TFNPullToRefreshControl : UIView
- (BOOL)loading;
@end

static void PlayRefreshSound(RefreshSound type) {
    // SystemSoundIDs are a global audio resource, so cache one per sound type
    // instead of re-decoding.
    static SystemSoundID sounds[2] = {0, 0};
    static BOOL initialized[2] = {NO, NO};

    if (!initialized[type]) {
        NSString* soundFile = (type == RefreshSoundPull) ? @"psst2.aac" : @"pop.aac";
        NSURL* soundURL = [[BHTBundle sharedBundle] pathForFile:soundFile];

        if (soundURL && AudioServicesCreateSystemSoundID((__bridge CFURLRef)soundURL, &sounds[type]) ==
                            kAudioServicesNoError) {
            initialized[type] = YES;
        }
    }

    if (initialized[type]) {
        AudioServicesPlaySystemSound(sounds[type]);
    }
}

// Every status transition funnels through -_setStatus:fromScrolling:; a drag past
// the threshold commits a refresh (status 1, fromScrolling) and status 0 clears it.
%hook TFNPullToRefreshControl

// Whether the in-flight refresh was started by a drag; per-instance because
// several scroll views each own a control. Gates the "pop" to manual pulls only.
static char kManualRefreshKey;

- (void)_setStatus:(unsigned long long)status fromScrolling:(BOOL)fromScrolling {
    BOOL wasActive = [self loading];

    %orig;

    if (![BHTSettings boolForKey:@"restore_refresh_sounds"]) {
        objc_setAssociatedObject(self, &kManualRefreshKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (status == 1 && !wasActive && fromScrolling) {
        PlayRefreshSound(RefreshSoundPull);
        objc_setAssociatedObject(self, &kManualRefreshKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (status == 0 && wasActive) {
        if ([objc_getAssociatedObject(self, &kManualRefreshKey) boolValue]) {
            PlayRefreshSound(RefreshSoundPop);
        }
        objc_setAssociatedObject(self, &kManualRefreshKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

%ctor {
    // AudioToolbox isn't in the tweak's linked frameworks; bind its symbols lazily.
    dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_LAZY);

    %init;
}
