//
//  BHTSettings.h
//  NeoFreeBird
//
//  Created by nyaathea
//

#import <Foundation/Foundation.h>

// Single source of truth for every user setting: per-page toggle lists,
// page titles and the default value used when a key was never toggled.
@interface BHTSettings : NSObject

+ (NSArray<NSDictionary*>*)settingsForPage:(NSString*)pageKey;
+ (NSString*)titleKeyForPage:(NSString*)pageKey;
+ (NSString*)subtitleKeyForPage:(NSString*)pageKey;
+ (NSDictionary*)settingForKey:(NSString*)key;
+ (BOOL)boolForKey:(NSString*)key;
+ (NSInteger)integerForKey:(NSString*)key;

@end
