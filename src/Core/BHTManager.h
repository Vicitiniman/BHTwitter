//
//  BHTdownloadManager.h
//  BHT
//
//  Created by BandarHelal on 24/12/1441 AH.
//

#import "Headers/TWHeaders.h"

@interface BHTManager : NSObject
+ (void)cleanCache;
+ (NSString*)getVideoQuality:(NSString*)url;
+ (id)sharedFontGroup;
+ (UIFont*)menuTitleFont;
+ (BOOL)doesContainDigitsOnly:(NSString*)string;
+ (UIViewController*)BHTSettingsWithAccount:(TFNTwitterAccount*)twAccount;
+ (void)showSaveVC:(NSURL*)url;
+ (void)save:(NSURL*)url;
+ (void)saveGIF:(NSURL*)url;
+ (MediaInformation*)getM3U8Information:(NSURL*)mediaURL;
+ (NSString*)getDownloadingPercent:(float)progress;

+ (BOOL)isTwitterBranded;

@end
