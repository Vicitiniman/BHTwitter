//
//  TimelinesSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/TimelinesSettingsViewController.h"
#import "Headers/TWHeaders.h"
#import "Likes/BHTLikesTab.h"

extern void applyHideCustomTimelinesSetting(void);

@implementation TimelinesSettingsViewController

- (NSString*)pageKey {
    return @"timelines";
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"hide_custom_timelines"]) {
        applyHideCustomTimelinesSetting();
    } else if ([key isEqualToString:@"enable_likes_tab"]) {
        BHTRefreshVisibleAppTabs();
    }
}

@end
