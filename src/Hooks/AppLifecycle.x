//
//  AppLifecycle.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Padlock helpers

static const NSInteger PadlockOverlayTag = 909;

static NSArray<UIWindow*>* allActiveWindows(void) {
    NSMutableArray<UIWindow*>* result = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (!w.hidden)
                        [result addObject:w];
                }
            }
        }
    }
    if (result.count == 0) {
        for (UIWindow* w in UIApplication.sharedApplication.windows) {
            if (!w.hidden)
                [result addObject:w];
        }
    }
    return result;
}

static UIWindow* activeKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (w.isKeyWindow)
                        return w;
                }
                for (UIWindow* w in ws.windows) {
                    if (!w.hidden)
                        return w;
                }
            }
        }
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow)
            return w;
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (!w.hidden)
            return w;
    }
    return nil;
}

static UIViewController* topViewController(UIViewController* root) {
    if (!root)
        return nil;
    UIViewController* vc = root;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        vc = ((UINavigationController*)vc).visibleViewController ?: vc;
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UIViewController* sel = ((UITabBarController*)vc).selectedViewController;
        if (sel)
            vc = sel;
    }
    return vc;
}

static void showPadlockOverlay(void) {
    UIWindow* window = activeKeyWindow();
    if (!window)
        return;

    for (UIWindow* w in allActiveWindows()) {
        for (UIView* v in w.subviews) {
            if (v.tag == PadlockOverlayTag)
                [v removeFromSuperview];
        }
    }

    UIView* overlay = [[UIView alloc] initWithFrame:window.bounds];
    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = UIColor.systemBackgroundColor;
    overlay.userInteractionEnabled = YES;
    overlay.tag = PadlockOverlayTag;

    UIImageView* icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.labelColor;

    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"PADLOCK_LOCKED_LABEL"];
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;

    [overlay addSubview:icon];
    [overlay addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor
                                           constant:-20],
        [label.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor
                                        constant:8]
    ]];

    [window addSubview:overlay];
}

static void removePadlockOverlay(void) {
    for (UIWindow* w in allActiveWindows()) {
        NSMutableArray<UIView*>* toRemove = [NSMutableArray array];
        for (UIView* v in w.subviews) {
            if (v.tag == PadlockOverlayTag)
                [toRemove addObject:v];
        }
        for (UIView* v in toRemove)
            [v removeFromSuperview];
    }
}

// Deliberately in-memory only: the padlock must always re-prompt after a
// relaunch, so persisting this would only risk skipping it.
static BOOL padlockAuthenticated = NO;

static BOOL isAuthenticated(void) {
    return padlockAuthenticated;
}

static void setAuthenticated(BOOL yes) {
    padlockAuthenticated = yes;
}

static void presentAuthIfNeeded(void) {
    if (isAuthenticated()) {
        removePadlockOverlay();
        return;
    }

    UIWindow* window = activeKeyWindow();
    if (!window) {
        showPadlockOverlay();
        return;
    }

    UIViewController* root = window.rootViewController;
    if (!root) {
        window.rootViewController = [UIViewController new];
        root = window.rootViewController;
    }
    UIViewController* host = topViewController(root);

    AuthViewController* auth = [[AuthViewController alloc] init];
    auth.completion = ^(BOOL authenticated) {
        setAuthenticated(authenticated);
        if (authenticated) {
            removePadlockOverlay();
        }
    };
    auth.modalPresentationStyle = UIModalPresentationFullScreen;
    if ([auth respondsToSelector:@selector(setModalInPresentation:)]) {
        auth.modalInPresentation = YES;
    }

    if (host.presentedViewController == nil) {
        [host presentViewController:auth animated:NO completion:nil];
    } else {
        [host dismissViewControllerAnimated:NO
                                 completion:^{
                                     UIViewController* newTop =
                                         topViewController(root);
                                     [newTop presentViewController:auth
                                                          animated:NO
                                                        completion:nil];
                                 }];
    }
}

// MARK: - App Delegate hooks

%hook T1AppDelegate

- (_Bool)application:(__unsafe_unretained UIApplication*)application
    didFinishLaunchingWithOptions:(__unsafe_unretained id)arg2 {
    _Bool orig = %orig;

    [BHTManager cleanCache];
    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        applySelectedThemeColor();
    });

    return orig;
}

- (void)applicationDidBecomeActive:(__unsafe_unretained id)arg1 {
    %orig;

    applySelectedThemeColor();

    if ([BHTSettings boolForKey:@"padlock"]) {
        if (isAuthenticated()) {
            removePadlockOverlay();
        } else {
            showPadlockOverlay();
            dispatch_async(dispatch_get_main_queue(), ^{
                presentAuthIfNeeded();
            });
        }
    } else {
        removePadlockOverlay();
    }
}

- (void)applicationWillResignActive:(__unsafe_unretained id)arg1 {
    %orig;

    if ([BHTSettings boolForKey:@"padlock"]) {
        // Cover the UI (and the app-switcher snapshot) and mark unauthenticated so
        // the next activation prompts again; the overlay persists into background.
        showPadlockOverlay();
        setAuthenticated(NO);
    }

    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }
}

%end

// MARK: - Restore Launch Animation

// The launch animation reveals the app through a growing X-shaped mask
// (revealMaskLayer / holePathInView); detach it so the logo zoom is kept but
// the splash simply fades out.

static void stripLaunchRevealMask(UIView* view) {
    // The X-shaped hole lives on the container subview's layer.mask; the top
    // view itself is unmasked, but clear it too for safety.
    view.layer.mask = nil;
    for (UIView* sub in view.subviews) {
        sub.layer.mask = nil;
    }
}

%hook T1AnimatedLaunchScreenView

- (void)layoutSubviews {
    %orig;
    // layoutSubviews re-installs the mask each pass, so re-strip after %orig.
    if ([BHTSettings boolForKey:@"restore_launch_animation"]) {
        stripLaunchRevealMask((UIView*)self);
    }
}

- (void)animateRevealWithCompletion:(id)completion {
    if (![BHTSettings boolForKey:@"restore_launch_animation"]) {
        %orig;
        return;
    }
    stripLaunchRevealMask((UIView*)self);

    [UIView animateWithDuration:0.5
                     animations:^{
                         for (UIView* sub in ((UIView*)self).subviews) {
                             sub.backgroundColor = [UIColor clearColor];
                         }
                     }];

    %orig;
}

%end
