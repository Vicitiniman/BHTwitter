//
//  BHTHelpers.h
//  BHTwitter
//
//  Created by BandarHelal
//

#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "TAEHeaders.h"

@interface NSParagraphStyle ()
+ (NSWritingDirection)_defaultWritingDirection;
@end

@interface SFSafariViewController ()
- (NSURL*)initialURL;
@end

static void changeTwitterColor(NSInteger colorID) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    TAEColorSettings* colorSettings =
        [objc_getClass("TAEColorSettings") sharedSettings];

    [defaults setObject:@(colorID)
                 forKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    [colorSettings setPrimaryColorOption:colorID];
}
static UIImage* imageFromView(UIView* view) {
    TAEColorSettings* colorSettings =
        [objc_getClass("TAEColorSettings") sharedSettings];
    bool opaque = [colorSettings.currentColorPalette isDark] ? true : false;
    UIGraphicsBeginImageContextWithOptions(view.frame.size, opaque, 0.0);
    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:false];
    UIImage* img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return img;
}

static UIFont* _Nullable BHTFontForStoredSelection(NSString* selection,
                                                   CGFloat size,
                                                   BOOL wantsBold) {
    if (selection.length == 0) return nil;

    // Current builds persist a PostScript face name. Older BHTwitter builds
    // saved the regular choice as a family name, which fontWithName: cannot
    // reliably resolve. Keep those existing choices working by selecting the
    // closest face from the family.
    UIFont* direct = [UIFont fontWithName:selection size:size];
    if (direct) return direct;

    NSArray<NSString*>* faces = [UIFont fontNamesForFamilyName:selection];
    UIFont* fallback = nil;
    for (NSString* face in faces) {
        UIFont* candidate = [UIFont fontWithName:face size:size];
        if (!candidate) continue;
        if (!fallback) fallback = candidate;
        BOOL candidateBold =
            (candidate.fontDescriptor.symbolicTraits &
             UIFontDescriptorTraitBold) != 0;
        if (candidateBold == wantsBold) return candidate;
    }
    return fallback;
}

static UIFont* _Nullable getDefaultFont(UIFont* font) {
    if (!font ||
        ![[NSUserDefaults standardUserDefaults] boolForKey:@"custom_fonts"]) {
        return nil;
    }

    UIFontDescriptorSymbolicTraits traits =
        font.fontDescriptor.symbolicTraits;
    BOOL isBold = (traits & UIFontDescriptorTraitBold) != 0;
    NSString* key = isBold ? @"bhtwitter_font_2" : @"bhtwitter_font_1";
    NSString* selection =
        [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return BHTFontForStoredSelection(selection, font.pointSize, isBold);
}
static BOOL isDeviceLanguageRTL() {
    return [NSParagraphStyle _defaultWritingDirection] ==
           NSWritingDirectionRightToLeft;
}
static BOOL is_iPad() {
    if ([(NSString*)[UIDevice currentDevice].model hasPrefix:@"iPad"]) {
        return YES;
    }
    return NO;
}

// https://github.com/julioverne/MImport/blob/0275405812ff41ed2ca56e98f495fd05c38f41f2/mimporthook/MImport.xm#L59
static UIViewController* _Nullable _topMostController(
    UIViewController* _Nonnull cont) {
    UIViewController* topController = cont;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    if ([topController isKindOfClass:[UINavigationController class]]) {
        UIViewController* visible =
            ((UINavigationController*)topController).visibleViewController;
        if (visible) {
            topController = visible;
        }
    }
    return (topController != cont ? topController : nil);
}
static UIViewController* _Nonnull topMostController() {
    UIViewController* topController =
        [UIApplication sharedApplication].keyWindow.rootViewController;
    UIViewController* next = nil;
    while ((next = _topMostController(topController)) != nil) {
        topController = next;
    }
    return topController;
}

@interface UIImageView (TwitterLogo)
- (id)initWithImage:(UIImage*)image;
- (void)setImage:(UIImage*)image;
@end

// Defined in Hooks/BHTHookHelpers.m
extern UIColor* CurrentAccentColor(void);
