//
//  DownloadInlineButton.m
//  NeoFreeBird
//
//  Original author: BandarHelal at 09/04/2022
//  Modified by: actuallyaridan at 27/04/2025
//

#import "Download/DownloadInlineButton.h"
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"

#pragma mark - Helpers
static UIWindow* KeyWindow(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class])
            continue;
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow)
                return window;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController* TopMostController(void) {
    UIViewController* top = KeyWindow().rootViewController;
    BOOL advanced = YES;
    while (top && advanced) {
        advanced = NO;
        if (top.presentedViewController) {
            top = top.presentedViewController;
            advanced = YES;
        } else if ([top isKindOfClass:UINavigationController.class] &&
                   ((UINavigationController*)top).visibleViewController) {
            top = ((UINavigationController*)top).visibleViewController;
            advanced = YES;
        } else if ([top isKindOfClass:UITabBarController.class] &&
                   ((UITabBarController*)top).selectedViewController) {
            top = ((UITabBarController*)top).selectedViewController;
            advanced = YES;
        } else if (top.childViewControllers.count == 1) {
            top = top.childViewControllers.firstObject;
            advanced = YES;
        }
    }
    return top;
}

static BOOL BHTMediaLooksLikeGIF(TFSTwitterEntityMedia* media) {
    if (media.mediaType == 2) {
        return YES;
    }
    for (TFSTwitterEntityMediaVideoVariant* variant in
         media.videoInfo.variants) {
        if ([variant.url containsString:@"/tweet_video/"]) {
            return YES;
        }
    }
    return [media.videoInfo.primaryUrl containsString:@"/tweet_video/"];
}

static BOOL BHTVariantIsMP4(TFSTwitterEntityMediaVideoVariant* variant) {
    NSString* contentType = variant.contentType.lowercaseString;
    if ([contentType hasPrefix:@"video/mp4"]) {
        return YES;
    }
    NSURL* url = variant.url.length > 0
                     ? [NSURL URLWithString:variant.url]
                     : nil;
    return [url.pathExtension.lowercaseString isEqualToString:@"mp4"];
}

static BOOL BHTVariantIsHLS(TFSTwitterEntityMediaVideoVariant* variant) {
    NSString* contentType = variant.contentType.lowercaseString;
    if ([contentType containsString:@"mpegurl"]) {
        return YES;
    }
    NSURL* url = variant.url.length > 0
                     ? [NSURL URLWithString:variant.url]
                     : nil;
    return [url.pathExtension.lowercaseString isEqualToString:@"m3u8"];
}

#pragma mark - DownloadInlineButton
@interface DownloadInlineButton ()
@property (nonatomic, strong) TFNHUD* hud;
@end

@implementation DownloadInlineButton

#pragma mark - Download handler
- (void)presentDownloadOptionsForMediaEntities:(NSArray*)mediaEntities {
    @try {
        NSAttributedString* titleString = [[NSAttributedString alloc]
            initWithString:[[BHTBundle sharedBundle]
                               localizedStringForKey:@"DOWNLOAD_MENU_TITLE"]
                attributes:@{
                    NSFontAttributeName: [BHTManager menuTitleFont],
                    NSForegroundColorAttributeName: UIColor.labelColor
                }];
        TFNActiveTextItem* title = [[objc_getClass("TFNActiveTextItem") alloc]
            initWithTextModel:[[objc_getClass("TFNAttributedTextModel") alloc]
                                  initWithAttributedString:titleString]
                 activeRanges:nil];

        void (^showHUD)(NSString*) = ^(NSString* text) {
            [self.hud hide];
            self.hud = [[objc_getClass("TFNHUD") alloc] initWithText:text];
            [self.hud show];
        };
        void (^dismissHUD)(void) = ^{
            [self.hud hide];
        };

        NSString* downloadingText = [[BHTBundle sharedBundle]
            localizedTwitterStringForKey:@"DOWNLOAD_LIVE_ACTIVITY_DOWNLOADING"];

        void (^presentError)(NSString*) = ^(NSString* message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                dismissHUD();
                UINotificationFeedbackGenerator* feedback =
                    [UINotificationFeedbackGenerator new];
                [feedback prepare];
                [feedback notificationOccurred:UINotificationFeedbackTypeError];

                UIAlertController* alert = [UIAlertController
                    alertControllerWithTitle:
                        [[BHTBundle sharedBundle]
                            localizedTwitterStringForKey:@"ERROR_ALERT_TITLE"]
                                     message:message.length > 0
                                                 ? message
                                                 : [[BHTBundle sharedBundle]
                                                       localizedStringForKey:
                                                           @"UNKNOWN_ERROR"]
                              preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:
                           [UIAlertAction
                               actionWithTitle:[[BHTBundle sharedBundle]
                                                   localizedTwitterStringForKey:
                                                       @"OK_ACTION_LABEL"]
                                         style:UIAlertActionStyleDefault
                                       handler:nil]];
                [TopMostController() presentViewController:alert
                                                  animated:YES
                                                completion:nil];
            });
        };

        void (^finishFile)(NSURL*, NSString*) =
            ^(NSURL* outFile, NSString* ext) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    dismissHUD();
                    UINotificationFeedbackGenerator* feedback =
                        [UINotificationFeedbackGenerator new];
                    [feedback prepare];

                    if (![BHTSettings boolForKey:@"direct_save"]) {
                        [BHTManager showSaveVC:outFile];
                    } else {
                        [feedback
                            notificationOccurred:UINotificationFeedbackTypeSuccess];
                        if ([ext isEqualToString:@"gif"])
                            [BHTManager saveGIF:outFile];
                        else
                            [BHTManager save:outFile];
                    }
                });
            };

        // Direct MP4 variants do not need transcoding. NSURLSession is more
        // reliable for X's signed CDN URLs and avoids making an otherwise valid
        // download depend on FFmpeg's HTTPS command parser.
        void (^downloadMP4)(NSURL*) = ^(NSURL* url) {
            showHUD(downloadingText);
            NSURL* outFile = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.%@",
                                                                 NSUUID.UUID
                                                                     .UUIDString,
                                                                 @"mp4"]];
            NSURLSessionDownloadTask* task =
                [[NSURLSession sharedSession]
                    downloadTaskWithURL:url
                     completionHandler:^(NSURL* location,
                                         NSURLResponse* response,
                                         NSError* error) {
                         if (error || !location) {
                             presentError(error.localizedDescription);
                             return;
                         }
                         if ([response isKindOfClass:NSHTTPURLResponse.class] &&
                             !NSLocationInRange(
                                 ((NSHTTPURLResponse*)response).statusCode,
                                 NSMakeRange(200, 100))) {
                             NSInteger statusCode =
                                 ((NSHTTPURLResponse*)response).statusCode;
                             presentError([NSString
                                 stringWithFormat:@"Download failed (HTTP %ld: %@).",
                                                  (long)statusCode,
                                                  [NSHTTPURLResponse
                                                      localizedStringForStatusCode:
                                                          statusCode]]);
                             return;
                         }

                         NSError* moveError = nil;
                         [[NSFileManager defaultManager]
                             moveItemAtURL:location
                                    toURL:outFile
                                    error:&moveError];
                         if (moveError) {
                             presentError(moveError.localizedDescription);
                             return;
                         }
                         finishFile(outFile, @"mp4");
                     }];
            [task resume];
        };

        // Use FFmpeg's argument-array API so signed URLs and filter graphs are
        // never split or re-tokenized. cleanupFile is removed after conversion.
        void (^ffmpegDownload)(NSArray<NSString*>*, NSString*, double, NSURL*) =
            ^(NSArray<NSString*>* args, NSString* ext, double durationMs,
              NSURL* cleanupFile) {
            showHUD(downloadingText);
            NSURL* outFile = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.%@",
                                                                 NSUUID.UUID
                                                                     .UUIDString,
                                                                 ext]];
            NSMutableArray<NSString*>* command = [NSMutableArray arrayWithArray:@[
                @"-y", @"-nostdin", @"-hide_banner", @"-loglevel", @"error"
            ]];
            [command addObjectsFromArray:args];
            [command addObject:outFile.path];
            [FFmpegKit
                executeWithArgumentsAsync:command
                withCompleteCallback:^(FFmpegSession* session) {
                    ReturnCode* returnCode = [session getReturnCode];
                    if (cleanupFile) {
                        [[NSFileManager defaultManager]
                            removeItemAtURL:cleanupFile
                                     error:nil];
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([ReturnCode isSuccess:returnCode]) {
                            finishFile(outFile, ext);
                        } else {
                            presentError(nil);
                        }
                    });
                }
                withLogCallback:nil
                withStatisticsCallback:^(Statistics* statistics) {
                    NSString* detail;
                    if (durationMs > 0) {
                        detail = [BHTManager
                            getDownloadingPercent:MIN([statistics getTime] / durationMs,
                                                      1.0)];
                    } else if ([statistics getSize] > 0) {
                        detail = [NSByteCountFormatter
                            stringFromByteCount:[statistics getSize]
                                     countStyle:NSByteCountFormatterCountStyleFile];
                    } else {
                        return;
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.hud
                            setText:[NSString stringWithFormat:@"%@ %@", downloadingText,
                                                               detail]];
                    });
                }];
        };

        // X serves animated GIF posts as MP4 loops. Fetch the source with the
        // native networking stack first, then feed FFmpeg a local path for the
        // palette conversion.
        void (^downloadGIF)(NSURL*, double) =
            ^(NSURL* url, double durationMs) {
                showHUD(downloadingText);
                NSURL* inputFile =
                    [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                        URLByAppendingPathComponent:[NSString
                                                        stringWithFormat:
                                                            @"%@-source.mp4",
                                                            NSUUID.UUID
                                                                .UUIDString]];
                NSURLSessionDownloadTask* task =
                    [[NSURLSession sharedSession]
                        downloadTaskWithURL:url
                         completionHandler:^(NSURL* location,
                                             NSURLResponse* response,
                                             NSError* error) {
                             if (error || !location) {
                                 presentError(error.localizedDescription);
                                 return;
                             }
                             if ([response
                                     isKindOfClass:NSHTTPURLResponse.class] &&
                                 !NSLocationInRange(
                                     ((NSHTTPURLResponse*)response).statusCode,
                                     NSMakeRange(200, 100))) {
                                 NSInteger statusCode =
                                     ((NSHTTPURLResponse*)response).statusCode;
                                 presentError([NSString
                                     stringWithFormat:
                                         @"Download failed (HTTP %ld: %@).",
                                         (long)statusCode,
                                         [NSHTTPURLResponse
                                             localizedStringForStatusCode:
                                                 statusCode]]);
                                 return;
                             }

                             NSError* moveError = nil;
                             [[NSFileManager defaultManager]
                                 moveItemAtURL:location
                                        toURL:inputFile
                                        error:&moveError];
                             if (moveError) {
                                 presentError(moveError.localizedDescription);
                                 return;
                             }

                             dispatch_async(dispatch_get_main_queue(), ^{
                                 ffmpegDownload(
                                     @[
                                         @"-i", inputFile.path, @"-an",
                                         @"-filter_complex",
                                         @"split[a][b];[a]palettegen[p];[b][p]paletteuse",
                                         @"-loop", @"0"
                                     ],
                                     @"gif", durationMs, inputFile);
                             });
                         }];
                [task resume];
            };

        // Variant builders
        TFNActionItem* (^makeMP4Item)(NSURL*, double, NSString*) =
            ^TFNActionItem*(NSURL* url, double durationMs, NSString* itemTitle) {
                return [objc_getClass("TFNActionItem")
                    actionItemWithTitle:itemTitle
                              imageName:@"arrow_down_circle_stroke"
                                 action:^{
                                     downloadMP4(url);
                                 }];
            };

        TFNActionItem* (^makeGIFItem)(NSURL*, double) = ^TFNActionItem*(
            NSURL* url, double durationMs) {
            return [objc_getClass("TFNActionItem")
                actionItemWithTitle:
                    [[BHTBundle sharedBundle]
                        localizedStringForKey:@"DOWNLOAD_AS_GIF_OPTION_TITLE"]
                          imageName:@"arrow_down_circle_stroke"
                             action:^{
                                 downloadGIF(url, durationMs);
                             }];
        };

        TFNActionItem* (^makeHLSItem)(NSURL*, NSString*, double) = ^TFNActionItem*(
            NSURL* url, NSString* resolution, double durationMs) {
            return [objc_getClass("TFNActionItem")
                actionItemWithTitle:resolution
                          imageName:@"arrow_down_circle_stroke"
                             action:^{
                                 ffmpegDownload(
                                     @[
                                         @"-i", url.absoluteString, @"-vf",
                                         [NSString
                                             stringWithFormat:
                                                 @"scale=%@:flags=lanczos",
                                                 resolution],
                                         @"-c:v", @"h264_videotoolbox",
                                         @"-b:v", @"2M", @"-c:a", @"copy"
                                     ],
                                     @"mp4", durationMs, nil);
                             }];
        };

        // videoInfo.variants backs both video (mediaType 3) and GIF (mediaType 2);
        // photos carry no videoInfo. Probing the playlist supplies the duration
        // for progress and any HLS-only resolutions, so every quality is offered
        // in a single sheet. mp4 variants win when both carry the same
        // resolution; media without a playlist (GIFs) skips the probe entirely.
        void (^buildVariantItems)(TFSTwitterEntityMedia*, void (^)(NSArray*)) = ^(
            TFSTwitterEntityMedia* media, void (^done)(NSArray*)) {
            NSMutableArray<NSURL*>* mp4URLs = [NSMutableArray new];
            NSURL* m3u8URL = nil;
            for (TFSTwitterEntityMediaVideoVariant* variant in media.videoInfo
                     .variants) {
                NSURL* url =
                    variant.url.length ? [NSURL URLWithString:variant.url] : nil;
                if (!url)
                    continue;

                if (BHTVariantIsMP4(variant))
                    [mp4URLs addObject:url];
                else if (BHTVariantIsHLS(variant) && !m3u8URL)
                    m3u8URL = url;
            }

            NSMutableArray* items = [NSMutableArray new];
            NSMutableSet<NSString*>* offered = [NSMutableSet new];
            void (^appendMP4Items)(double) = ^(double durationMs) {
                BOOL isGIF = BHTMediaLooksLikeGIF(media);
                for (NSURL* url in mp4URLs) {
                    NSString* itemTitle =
                        isGIF ? [[BHTBundle sharedBundle]
                                    localizedStringForKey:@"DOWNLOAD_AS_MP4_OPTION_TITLE"]
                              : [BHTManager getVideoQuality:url.absoluteString];
                    [offered addObject:[BHTManager getVideoQuality:url.absoluteString]];
                    [items addObject:makeMP4Item(url, durationMs, itemTitle)];
                    if (isGIF)
                        [items addObject:makeGIFItem(url, durationMs)];
                }
            };

            if (!m3u8URL) {
                appendMP4Items(0);
                done(items);
                return;
            }

            showHUD([[BHTBundle sharedBundle]
                localizedStringForKey:@"FETCHING_PROGRESS_TITLE"]);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                MediaInformation* info = [BHTManager getM3U8Information:m3u8URL];
                double durationMs = [info getDuration].doubleValue * 1000.0;

                dispatch_async(dispatch_get_main_queue(), ^{
                    dismissHUD();
                    appendMP4Items(durationMs);
                    for (StreamInformation* stream in [info getStreams]) {
                        NSNumber* width = [stream getWidth];
                        NSNumber* height = [stream getHeight];
                        if (width == nil || height == nil)
                            continue;

                        NSString* resolution =
                            [NSString stringWithFormat:@"%@x%@", width, height];
                        if ([offered containsObject:resolution])
                            continue;

                        [offered addObject:resolution];
                        [items addObject:makeHLSItem(m3u8URL, resolution, durationMs)];
                    }
                    done(items);
                });
            });
        };

        // Filter to video/GIF so grouping keys off the real video count, not the
        // raw media count.
        NSMutableArray<TFSTwitterEntityMedia*>* videoEntities =
            [NSMutableArray new];
        for (TFSTwitterEntityMedia* media in mediaEntities) {
            if (media.videoInfo.variants.count > 0) {
                [videoEntities addObject:media];
            }
        }

        void (^presentSheet)(NSArray*) = ^(NSArray* items) {
            NSMutableArray* actions = [NSMutableArray arrayWithObject:title];
            [actions addObjectsFromArray:items];

            TFNMenuSheetViewController* sheet =
                [[objc_getClass("TFNMenuSheetViewController") alloc]
                    initWithActionItems:actions.copy];
            [sheet tfnPresentedCustomPresentFromViewController:TopMostController()
                                                      animated:YES
                                                    completion:nil];
        };

        if (videoEntities.count > 1) {
            NSMutableArray* groups = [NSMutableArray new];
            [videoEntities enumerateObjectsUsingBlock:^(TFSTwitterEntityMedia* media,
                                                        NSUInteger idx, BOOL* stop) {
                [groups
                    addObject:[objc_getClass("TFNActionItem")
                                  actionItemWithTitle:
                                      [NSString
                                          stringWithFormat:
                                              [[BHTBundle sharedBundle]
                                                  localizedStringForKey:
                                                      @"DOWNLOAD_VIDEO_NUMBER_TITLE"],
                                              (unsigned long)idx + 1]
                                            imageName:@"arrow_down_circle_stroke"
                                               action:^{
                                                   buildVariantItems(media, presentSheet);
                                               }]];
            }];
            presentSheet(groups);
        } else {
            buildVariantItems(videoEntities.firstObject, presentSheet);
        }
    } @catch (__unused NSException* ex) {
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:
                [[BHTBundle sharedBundle]
                    localizedTwitterStringForKey:@"ERROR_ALERT_TITLE"]
                             message:[[BHTBundle sharedBundle]
                                         localizedStringForKey:@"UNKNOWN_ERROR"]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
                             actionWithTitle:[[BHTBundle sharedBundle]
                                                 localizedTwitterStringForKey:
                                                     @"OK_ACTION_LABEL"]
                                       style:UIAlertActionStyleDefault
                                     handler:nil]];
        [TopMostController() presentViewController:alert
                                          animated:YES
                                        completion:nil];
    }
}

@end
