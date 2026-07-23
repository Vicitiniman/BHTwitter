//
//  MediaDownloads.x
//  NeoFreeBird
//

#import "HookHelpers.h"

static char kBHTVideoDownloadMediaKey;
static char kBHTVideoDownloadHandlerKey;

static NSArray<TFSTwitterEntityMedia*>* BHTVideoEntitiesFromMediaInfos(
    NSArray* mediaInfos) {
    NSMutableArray<TFSTwitterEntityMedia*>* entities = [NSMutableArray array];
    for (id info in mediaInfos) {
        TFSTwitterEntityMedia* media =
            [info respondsToSelector:@selector(mediaEntity)]
                ? [info mediaEntity]
                : nil;
        if ((media.mediaType == 2 || media.mediaType == 3) &&
            media.videoInfo.variants.count > 0) {
            [entities addObject:media];
        }
    }
    return [entities copy];
}

static NSURL* BHTPreferredDownloadURL(TFSTwitterEntityMedia* media) {
    if (!media || (media.mediaType != 2 && media.mediaType != 3)) {
        return nil;
    }
    TFSTwitterEntityMediaVideoVariant* bestMP4 = nil;
    TFSTwitterEntityMediaVideoVariant* fallback = nil;
    for (TFSTwitterEntityMediaVideoVariant* variant in
         media.videoInfo.variants) {
        if (variant.url.length == 0) continue;
        if (!fallback) fallback = variant;
        if ([variant.contentType isEqualToString:@"video/mp4"] &&
            (!bestMP4 || variant.bitrate > bestMP4.bitrate)) {
            bestMP4 = variant;
        }
    }
    NSString* rawURL = bestMP4.url;
    if (rawURL.length == 0) rawURL = fallback.url;
    if (rawURL.length == 0) rawURL = media.videoInfo.primaryUrl;
    return rawURL.length > 0 ? [NSURL URLWithString:rawURL] : nil;
}

// MARK: - Tweet video/GIF long press

// X 12.9 gives its own inline download action priority and routes non-Blue
// accounts to an upsell. Install a media-specific long press that wins that
// recognizer race and opens NeoFreeBird's quality/GIF picker directly.
%hook _TtC21TweetMediaAttachments14MultiMediaView
%property (nonatomic, strong) UILongPressGestureRecognizer* bhtDownloadLongPress;
%property (nonatomic, strong) DownloadInlineButton* bhtDownloadHandler;
- (void)layoutSubviews {
    %orig;

    NSArray* entities =
        BHTVideoEntitiesFromMediaInfos(self.inlineMediaInfos);
    BOOL enabled = [BHTSettings boolForKey:@"download_videos"] &&
                   entities.count > 0;
    if (enabled && !self.bhtDownloadLongPress) {
        UILongPressGestureRecognizer* recognizer =
            [[UILongPressGestureRecognizer alloc]
                initWithTarget:self
                        action:@selector(bhtHandleVideoDownloadLongPress:)];
        recognizer.minimumPressDuration = 0.55;
        self.bhtDownloadLongPress = recognizer;
        [self addGestureRecognizer:recognizer];
    }
    self.bhtDownloadLongPress.enabled = enabled;

    if (enabled) {
        for (UIGestureRecognizer* recognizer in
             self.gestureRecognizers) {
            if (recognizer != self.bhtDownloadLongPress &&
                [recognizer
                    isKindOfClass:UILongPressGestureRecognizer.class]) {
                [recognizer
                    requireGestureRecognizerToFail:
                        self.bhtDownloadLongPress];
            }
        }
    }
}
%new
- (void)bhtHandleVideoDownloadLongPress:
    (UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan ||
        ![BHTSettings boolForKey:@"download_videos"]) {
        return;
    }
    NSArray* entities =
        BHTVideoEntitiesFromMediaInfos(self.inlineMediaInfos);
    if (entities.count == 0) return;
    if (!self.bhtDownloadHandler) {
        self.bhtDownloadHandler = [%c(DownloadInlineButton) new];
    }
    [self.bhtDownloadHandler
        presentDownloadOptionsForMediaEntities:entities];
}
%end

// X's video-settings row can still be reached from the player menu. Make it
// eligible for video/GIF entities, retain the source entity on the native model,
// then replace tappedDownload with the same NeoFreeBird picker.
%hook TFSTwitterEntityMedia
- (BOOL)allowDownload {
    if ([BHTSettings boolForKey:@"download_videos"] &&
        (self.mediaType == 2 || self.mediaType == 3)) {
        return YES;
    }
    return %orig;
}
%end

%hook T1VideoDownloadViewModel
+ (NSURL*)urlIfCanDownloadWithAccount:(id)account
                          mediaEntity:
                              (TFSTwitterEntityMedia*)mediaEntity {
    if ([BHTSettings boolForKey:@"download_videos"]) {
        NSURL* url = BHTPreferredDownloadURL(mediaEntity);
        if (url) return url;
    }
    return %orig;
}

+ (id)makeVideDownloaderWithAccount:(id)account
                 fromViewController:(UIViewController*)viewController
                        mediaEntity:
                            (TFSTwitterEntityMedia*)mediaEntity
                    statusViewModel:(id)statusViewModel
                      scribeContext:(id)scribeContext {
    id downloader = %orig;
    if (downloader &&
        [BHTSettings boolForKey:@"download_videos"] &&
        (mediaEntity.mediaType == 2 || mediaEntity.mediaType == 3)) {
        objc_setAssociatedObject(
            downloader, &kBHTVideoDownloadMediaKey, mediaEntity,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return downloader;
}

- (void)tappedDownload {
    TFSTwitterEntityMedia* media =
        objc_getAssociatedObject(self, &kBHTVideoDownloadMediaKey);
    if ([BHTSettings boolForKey:@"download_videos"] && media) {
        DownloadInlineButton* handler =
            objc_getAssociatedObject(self, &kBHTVideoDownloadHandlerKey);
        if (!handler) {
            handler = [%c(DownloadInlineButton) new];
            objc_setAssociatedObject(
                self, &kBHTVideoDownloadHandlerKey, handler,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [handler presentDownloadOptionsForMediaEntities:@[media]];
        return;
    }
    %orig;
}
%end

// MARK: - DM video download

// The DM UI is Swift now: media messages live in DMConversation.MessageAttachmentView,
// which hosts a shared TweetMediaAttachments media view exposing its models through
// -inlineMediaInfos. Collect the entities from whichever descendant carries them.
static NSArray* DMVideoEntities(UIView* attachmentView) {
    NSMutableArray* entities = [NSMutableArray new];

    EnumerateSubviewsRecursively(attachmentView, ^(UIView* view) {
        if (![view respondsToSelector:@selector(inlineMediaInfos)]) {
            return;
        }

        for (TFSTwitterMediaInfo* info in
             [(_TtC21TweetMediaAttachments14MultiMediaView*)view inlineMediaInfos]) {
            TFSTwitterEntityMedia* media = info.mediaEntity;
            if (media.videoInfo.variants.count > 0) {
                [entities addObject:media];
            }
        }
    });

    return [entities copy];
}

%hook _TtC14DMConversation21MessageAttachmentView
%property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
%property (nonatomic, strong) DownloadInlineButton* downloadHandler;
- (void)layoutSubviews {
    %orig;

    if ([BHTSettings boolForKey:@"download_videos"] &&
        [BHTSettings boolForKey:@"dm_media_downloads"] &&
        self.downloadMenuInteraction == nil) {
        self.downloadMenuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:self.downloadMenuInteraction];
    }
}
%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    if (![BHTSettings boolForKey:@"download_videos"] ||
        ![BHTSettings boolForKey:@"dm_media_downloads"]) {
        return nil;
    }
    NSArray* videoEntities = DMVideoEntities(self);
    if (videoEntities.count == 0) {
        return nil;
    }

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                         UIAction* saveAction = [UIAction
                             actionWithTitle:
                                 [[BHTBundle sharedBundle]
                                     localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         if (self.downloadHandler == nil) {
                                             self.downloadHandler = [%c(DownloadInlineButton) new];
                                         }
                                         [self.downloadHandler
                                             presentDownloadOptionsForMediaEntities:videoEntities];
                                     }];
                         return [UIMenu menuWithTitle:@"" children:@[saveAction]];
                     }];
}
%end

// MARK: - Upload custom voice

// Overwrites the recording at the attachment's existing file path, so the
// composer picks up the replacement without any model changes.
%hook T1MediaAttachmentsViewCell
%property (nonatomic, strong) UIButton* uploadButton;
- (void)updateCellElements {
    %orig;

    BOOL isVoiceRecording = [self.attachment isKindOfClass:%c(TTMAssetVoiceRecording)];

    BOOL customUploadEnabled = [BHTSettings boolForKey:@"custom_voice_upload"];

    if (customUploadEnabled && isVoiceRecording && self.uploadButton == nil) {
        TFNButton* removeButton = [self valueForKey:@"_removeButton"];
        if (removeButton == nil) {
            return;
        }

        self.uploadButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImageSymbolConfiguration* smallConfig =
            [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleSmall];
        UIImage* arrowUpImage = [UIImage systemImageNamed:@"arrow.up" withConfiguration:smallConfig];
        [self.uploadButton setImage:arrowUpImage forState:UIControlStateNormal];
        [self.uploadButton addTarget:self
                              action:@selector(handleUploadButton:)
                    forControlEvents:UIControlEventTouchUpInside];
        [self.uploadButton setTintColor:UIColor.labelColor];
        [self.uploadButton setBackgroundColor:[UIColor blackColor]];
        [self.uploadButton.layer setCornerRadius:29 / 2];
        [self.uploadButton setTranslatesAutoresizingMaskIntoConstraints:false];

        [self addSubview:self.uploadButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.uploadButton.trailingAnchor constraintEqualToAnchor:removeButton.leadingAnchor
                                                             constant:-10],
            [self.uploadButton.topAnchor constraintEqualToAnchor:removeButton.topAnchor],
            [self.uploadButton.widthAnchor constraintEqualToConstant:29],
            [self.uploadButton.heightAnchor constraintEqualToConstant:29],
        ]];
    }

    self.uploadButton.hidden = !customUploadEnabled || !isVoiceRecording;
}
%new
- (void)handleUploadButton:(UIButton*)sender {
    if (![BHTSettings boolForKey:@"custom_voice_upload"]) {
        return;
    }
    UIImagePickerController* videoPicker = [[UIImagePickerController alloc] init];
    videoPicker.mediaTypes = @[(NSString*)kUTTypeMovie];
    videoPicker.delegate = self;

    [topMostController() presentViewController:videoPicker animated:YES completion:nil];
}
%new
- (void)imagePickerController:(UIImagePickerController*)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id>*)info {
    NSURL* videoURL = info[UIImagePickerControllerMediaURL];
    TTMAssetVoiceRecording* attachment = self.attachment;
    NSURL* recorder_url = [NSURL fileURLWithPath:attachment.filePath];

    if (recorder_url != nil) {
        NSFileManager* fileManager = [NSFileManager defaultManager];

        NSError* error = nil;
        if ([fileManager fileExistsAtPath:[recorder_url path]]) {
            [fileManager removeItemAtURL:recorder_url error:&error];
            if (error) {
                NSLog(@"[BHTwitter] Error removing existing file: %@", error);
            }
        }

        [fileManager copyItemAtURL:videoURL toURL:recorder_url error:&error];
        if (error) {
            NSLog(@"[BHTwitter] Error copying file: %@", error);
        }
    }

    [picker dismissViewControllerAnimated:true completion:nil];
}
%new
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker {
    [picker dismissViewControllerAnimated:true completion:nil];
}
%end

// MARK: - Save tweet as an image

%hook TTAStatusInlineShareButton
- (void)didLongPressActionButton:(UILongPressGestureRecognizer*)gestureRecognizer {
    if ([BHTSettings boolForKey:@"tweet_to_image"]) {
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
            UIView* statusView = self.superview;
            while (statusView && ![statusView respondsToSelector:@selector(eventHandler)]) {
                statusView = statusView.superview;
            }

            UIView* tweetView = nil;
            id eventHandler = [(T1StandardStatusView*)statusView eventHandler];
            if ([eventHandler isKindOfClass:UIView.class]) {
                tweetView = eventHandler;
            }

            if (tweetView == nil) {
                UIView* ancestor = self.superview;
                while (ancestor && ![ancestor isKindOfClass:UITableViewCell.class] &&
                       ![ancestor isKindOfClass:UICollectionViewCell.class]) {
                    ancestor = ancestor.superview;
                }
                tweetView = ancestor;
            }

            if (tweetView == nil) {
                return %orig;
            }

            UIImage* tweetImage = imageFromView(tweetView);
            NSData* pngData = UIImagePNGRepresentation(tweetImage);
            NSURL* pngURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]]];
            [pngData writeToURL:pngURL atomically:YES];
            UIActivityViewController* acVC =
                [[UIActivityViewController alloc] initWithActivityItems:@[pngURL]
                                                  applicationActivities:nil];
            if (is_iPad()) {
                acVC.popoverPresentationController.sourceView = self;
                acVC.popoverPresentationController.sourceRect = self.frame;
            }
            [topMostController() presentViewController:acVC animated:true completion:nil];
            return;
        }
    }
    return %orig;
}
%end

// MARK: - Tweet video download

// _t1_actionItemsForStatus:... is a category method on UIViewController, so the
// hook has to land on the base class to cover every share/action sheet.
%hook UIViewController
- (NSArray*)_t1_actionItemsForStatus:(__unsafe_unretained id)status
                             account:(__unsafe_unretained id)account
                     shareableEntity:(__unsafe_unretained id)shareableEntity
                           entityURL:(__unsafe_unretained id)entityURL
                              source:(__unsafe_unretained id)source
                             options:(NSUInteger)options
                     scribeComponent:(__unsafe_unretained id)scribeComponent
                           doneBlock:(__unsafe_unretained id)doneBlock {
    NSArray* origItems = %orig;

    if (![BHTSettings boolForKey:@"download_videos"] ||
        ![status respondsToSelector:@selector(entities)]) {
        return origItems;
    }

    NSArray* mediaEntities = [[status entities] media];
    BOOL hasVideo = NO;
    // mediaType 2 = GIF, 3 = video
    for (TFSTwitterEntityMedia* media in mediaEntities) {
        if ([media isKindOfClass:%c(TFSTwitterEntityMedia)] &&
            (media.mediaType == 2 || media.mediaType == 3)) {
            hasVideo = YES;
            break;
        }
    }
    if (!hasVideo) {
        return origItems;
    }

    static char downloaderKey;
    DownloadInlineButton* downloader = objc_getAssociatedObject(self, &downloaderKey);
    if (!downloader) {
        downloader = [%c(DownloadInlineButton) new];
        objc_setAssociatedObject(self, &downloaderKey, downloader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    TFNActionItem* downloadItem = [%c(TFNActionItem)
        actionItemWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"DOWNLOAD_VIDEOS_TITLE"]
                  imageName:@"arrow_down_circle_stroke"
                     action:^{
                         [downloader presentDownloadOptionsForMediaEntities:mediaEntities];
                     }];

    NSMutableArray* newItems = origItems ? [origItems mutableCopy] : [NSMutableArray array];
    NSUInteger insertIndex = newItems.count > 0 ? newItems.count - 1 : 0;
    [newItems insertObject:downloadItem atIndex:insertIndex];
    return newItems;
}
%end
