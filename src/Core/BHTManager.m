//
//  BHTdownloadManager.m
//  BHTwitter
//
//  Created by BandarHelal.
//

#import "Core/BHTManager.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Settings/ModernSettingsViewController.h"

@implementation BHTManager
+ (void)cleanCache {
    NSArray<NSURL*>* DocumentFiles = [[NSFileManager defaultManager]
          contentsOfDirectoryAtURL:
              [NSURL
                  fileURLWithPath:NSSearchPathForDirectoriesInDomains(
                                      NSDocumentDirectory, NSUserDomainMask, true)
                                      .firstObject]
        includingPropertiesForKeys:@[]
                           options:NSDirectoryEnumerationSkipsHiddenFiles
                             error:nil];

    for (NSURL* file in DocumentFiles) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"mp4"]) {
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
        }
    }

    NSArray<NSURL*>* TempFiles = [[NSFileManager defaultManager]
          contentsOfDirectoryAtURL:[NSURL fileURLWithPath:NSTemporaryDirectory()]
        includingPropertiesForKeys:@[]
                           options:NSDirectoryEnumerationSkipsHiddenFiles
                             error:nil];

    for (NSURL* file in TempFiles) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"mp4"]) {
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
        }
        if ([file.pathExtension.lowercaseString isEqualToString:@"mov"]) {
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
        }
        if ([file.pathExtension.lowercaseString isEqualToString:@"tmp"]) {
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
        }
        if ([file hasDirectoryPath]) {
            if ([BHTManager isEmpty:file]) {
                [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
            }
        }
    }
}
+ (BOOL)isEmpty:(NSURL*)url {
    NSArray* FolderFiles = [[NSFileManager defaultManager]
          contentsOfDirectoryAtURL:url
        includingPropertiesForKeys:@[]
                           options:NSDirectoryEnumerationSkipsHiddenFiles
                             error:nil];
    if (FolderFiles.count == 0) {
        return true;
    } else {
        return false;
    }
}
+ (id)sharedFontGroup {
    // X 12.9 uses TFNUIDefaultFontGroup. Keep the older name as a harmless
    // fallback so the settings UI can still render on nearby app versions.
    Class fontGroupClass = objc_getClass("TFNUIDefaultFontGroup");
    if (!fontGroupClass) {
        fontGroupClass = objc_getClass("TAEStandardFontGroup");
    }
    return [fontGroupClass sharedFontGroup];
}
+ (UIFont*)menuTitleFont {
    UIFont* font = [[self sharedFontGroup] headline2BoldFont];
    if (!font)
        font = [UIFont boldSystemFontOfSize:17.0];
    return font;
}
+ (NSString*)getVideoQuality:(NSString*)url {
    NSMutableArray* q = [NSMutableArray new];
    NSArray* splits = [url componentsSeparatedByString:@"/"];
    for (int i = 0; i < [splits count]; i++) {
        NSString* item = [splits objectAtIndex:i];
        NSArray* dir = [item componentsSeparatedByString:@"x"];
        for (int k = 0; k < [dir count]; k++) {
            NSString* item2 = [dir objectAtIndex:k];
            if (!(item2.length == 0)) {
                if ([BHTManager doesContainDigitsOnly:item2]) {
                    if (!(item2.integerValue > 10000)) {
                        if (!(q.count == 2)) {
                            [q addObject:item2];
                        }
                    }
                }
            }
        }
    }
    if (q.count == 0) {
        return @"GIF";
    }
    return [NSString stringWithFormat:@"%@x%@", q.firstObject, q.lastObject];
}
+ (void)save:(NSURL*)url {
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChangesAndWait:^{
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
        }
                        error:nil];
}
+ (void)saveGIF:(NSURL*)url {
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChangesAndWait:^{
            [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:url];
        }
                        error:nil];
}
+ (void)showSaveVC:(NSURL*)url {
    UIActivityViewController* acVC =
        [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                          applicationActivities:nil];
    if (is_iPad()) {
        acVC.popoverPresentationController.sourceView = topMostController().view;
        acVC.popoverPresentationController.sourceRect =
            CGRectMake(topMostController().view.bounds.size.width / 2.0,
                       topMostController().view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    [topMostController() presentViewController:acVC animated:true completion:nil];
}

+ (MediaInformation*)getM3U8Information:(NSURL*)mediaURL {
    MediaInformationSession* mediaInformationSession =
        [FFprobeKit getMediaInformation:mediaURL.absoluteString];
    MediaInformation* mediaInformation =
        [mediaInformationSession getMediaInformation];
    return mediaInformation;
}
+ (NSString*)getDownloadingPercent:(float)progress {
    NSNumberFormatter* numberFormatter = [[NSNumberFormatter alloc] init];
    [numberFormatter setNumberStyle:NSNumberFormatterPercentStyle];
    return [numberFormatter stringFromNumber:[NSNumber numberWithFloat:progress]];
}

+ (BOOL)isTwitterBranded {
    static BOOL branded = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        branded = [[[NSBundle mainBundle] infoDictionary][@"CFBundleDisplayName"]
            isEqual:@"Twitter"];
    });
    return branded;
}

+ (UIViewController*)BHTSettingsWithAccount:(TFNTwitterAccount*)twAccount {
    return [[ModernSettingsViewController alloc] initWithAccount:twAccount];
}

// https://stackoverflow.com/a/45356575/9910699
+ (BOOL)doesContainDigitsOnly:(NSString*)string {
    NSCharacterSet* nonDigits =
        [[NSCharacterSet decimalDigitCharacterSet] invertedSet];

    BOOL containsDigitsOnly =
        [string rangeOfCharacterFromSet:nonDigits].location == NSNotFound;

    return containsDigitsOnly;
}

@end
