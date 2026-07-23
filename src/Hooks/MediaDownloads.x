//
//  MediaDownloads.x
//  NeoFreeBird
//

#import "HookHelpers.h"

static char kBHTVideoDownloadMediaKey;
static char kBHTVideoDownloadHandlerKey;
static char kBHTInlineDownloadLongPressKey;
static char kBHTInlineDownloadHandlerKey;
static char kBHTCarouselDownloadLongPressKey;
static char kBHTCarouselDownloadHandlerKey;

static id BHTObjectForSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

// Do not key video detection off mediaType alone. X 12.9 has multiple media
// model bridges and the numeric enum value is not stable across all of them;
// videoInfo.variants is the reliable indication that the entity is downloadable.
static BOOL BHTIsDownloadableVideoEntity(id media) {
    id videoInfo = BHTObjectForSelector(media, @selector(videoInfo));
    NSArray* variants = BHTObjectForSelector(videoInfo, @selector(variants));
    return variants.count > 0;
}

static BOOL BHTVideoVariantIsMP4(id variant) {
    NSString* contentType =
        [BHTObjectForSelector(variant, @selector(contentType))
            lowercaseString];
    if ([contentType hasPrefix:@"video/mp4"]) {
        return YES;
    }
    NSString* rawURL = BHTObjectForSelector(variant, @selector(url));
    NSURL* url =
        rawURL.length > 0 ? [NSURL URLWithString:rawURL] : nil;
    return [url.pathExtension.lowercaseString isEqualToString:@"mp4"];
}

static void BHTPrioritizeDownloadLongPress(
    UIView* root,
    UILongPressGestureRecognizer* downloadRecognizer) {
    if (!root || !downloadRecognizer) return;
    EnumerateSubviewsRecursively(root, ^(UIView* view) {
        for (UIGestureRecognizer* recognizer in view.gestureRecognizers) {
            if (recognizer != downloadRecognizer &&
                [recognizer
                    isKindOfClass:UILongPressGestureRecognizer.class]) {
                [recognizer
                    requireGestureRecognizerToFail:downloadRecognizer];
            }
        }
    });
}

static NSArray<TFSTwitterEntityMedia*>* BHTVideoEntitiesFromMediaInfos(
    NSArray* mediaInfos) {
    NSMutableArray<TFSTwitterEntityMedia*>* entities = [NSMutableArray array];
    for (id info in mediaInfos) {
        TFSTwitterEntityMedia* media =
            [info respondsToSelector:@selector(mediaEntity)]
                ? [info mediaEntity]
                : info;
        if (BHTIsDownloadableVideoEntity(media)) {
            [entities addObject:media];
        }
    }
    return [entities copy];
}

static TFSTwitterEntityMedia* BHTMediaEntityFromInlineView(id inlineView) {
    id viewModel = BHTObjectForSelector(inlineView, @selector(viewModel));

    // T1InlineMediaViewModel exposes the playing entity through
    // playerSessionProducer.sessionProducible.mediaEntity.
    id producer =
        BHTObjectForSelector(viewModel, @selector(playerSessionProducer));
    id producible =
        BHTObjectForSelector(producer, @selector(sessionProducible));
    id media = BHTObjectForSelector(producible, @selector(mediaEntity));

    // Nearby X builds expose one of these shorter paths instead.
    if (!media) {
        media = BHTObjectForSelector(viewModel, @selector(mediaEntity));
    }
    if (!media) {
        media = BHTObjectForSelector(inlineView, @selector(mediaEntity));
    }
    return BHTIsDownloadableVideoEntity(media) ? media : nil;
}

static NSArray* BHTVideoEntitiesFromStatus(id status) {
    NSMutableArray* results = [NSMutableArray array];
    NSMutableSet* seen = [NSMutableSet set];
    void (^appendMedia)(NSArray*) = ^(NSArray* mediaEntities) {
        for (id media in mediaEntities) {
            if (!BHTIsDownloadableVideoEntity(media)) continue;
            NSValue* identity =
                [NSValue valueWithNonretainedObject:media];
            if ([seen containsObject:identity]) continue;
            [seen addObject:identity];
            [results addObject:media];
        }
    };

    id nestedStatus = BHTObjectForSelector(status, @selector(status));
    NSArray* sources =
        nestedStatus && nestedStatus != status ? @[status, nestedStatus]
                                               : @[status ?: NSNull.null];
    for (id source in sources) {
        if (source == NSNull.null) continue;
        appendMedia(BHTObjectForSelector(
            source, @selector(representedMediaEntities)));
        for (NSString* selectorName in
             @[@"extendedEntities", @"entities"]) {
            id entitySet = BHTObjectForSelector(
                source, NSSelectorFromString(selectorName));
            appendMedia(BHTObjectForSelector(entitySet, @selector(media)));
        }
    }
    return [results copy];
}

static NSURL* BHTPreferredDownloadURL(TFSTwitterEntityMedia* media) {
    if (!BHTIsDownloadableVideoEntity(media)) {
        return nil;
    }
    TFSTwitterEntityMediaVideoVariant* bestMP4 = nil;
    TFSTwitterEntityMediaVideoVariant* fallback = nil;
    for (TFSTwitterEntityMediaVideoVariant* variant in
         media.videoInfo.variants) {
        if (variant.url.length == 0) continue;
        if (!fallback) fallback = variant;
        if (BHTVideoVariantIsMP4(variant) &&
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
        recognizer.minimumPressDuration = 0.4;
        recognizer.cancelsTouchesInView = NO;
        self.bhtDownloadLongPress = recognizer;
        [self addGestureRecognizer:recognizer];
    }
    self.bhtDownloadLongPress.enabled = enabled;

    if (enabled)
        BHTPrioritizeDownloadLongPress(
            self, self.bhtDownloadLongPress);
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

// Mixed-media and multi-item posts use the separate carousel class, which has
// the same media-info API but is not a MultiMediaView subclass.
%hook _TtC21TweetMediaAttachments22MultiMediaCarouselView
- (void)layoutSubviews {
    %orig;

    NSArray* entities =
        BHTVideoEntitiesFromMediaInfos(self.inlineMediaInfos);
    BOOL enabled = [BHTSettings boolForKey:@"download_videos"] &&
                   entities.count > 0;
    UILongPressGestureRecognizer* recognizer =
        objc_getAssociatedObject(self, &kBHTCarouselDownloadLongPressKey);
    if (enabled && !recognizer) {
        recognizer = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(bhtHandleCarouselDownloadLongPress:)];
        recognizer.minimumPressDuration = 0.4;
        recognizer.cancelsTouchesInView = NO;
        objc_setAssociatedObject(
            self, &kBHTCarouselDownloadLongPressKey, recognizer,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addGestureRecognizer:recognizer];
    }
    recognizer.enabled = enabled;

    if (enabled)
        BHTPrioritizeDownloadLongPress(self, recognizer);
}
%new
- (void)bhtHandleCarouselDownloadLongPress:
    (UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan ||
        ![BHTSettings boolForKey:@"download_videos"]) {
        return;
    }

    NSArray* entities =
        BHTVideoEntitiesFromMediaInfos(self.inlineMediaInfos);
    if (entities.count == 0) return;

    DownloadInlineButton* handler =
        objc_getAssociatedObject(self, &kBHTCarouselDownloadHandlerKey);
    if (!handler) {
        handler = [%c(DownloadInlineButton) new];
        objc_setAssociatedObject(
            self, &kBHTCarouselDownloadHandlerKey, handler,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [handler presentDownloadOptionsForMediaEntities:entities];
}
%end

// Timeline videos can still use the legacy T1InlineMediaView while GIFs use
// TweetMediaAttachments.MultiMediaView. Cover that path as well so both media
// types expose the same NeoFreeBird long-press menu.
%hook T1InlineMediaView
- (void)layoutSubviews {
    %orig;

    TFSTwitterEntityMedia* media = BHTMediaEntityFromInlineView(self);
    BOOL enabled =
        [BHTSettings boolForKey:@"download_videos"] && media != nil;
    UILongPressGestureRecognizer* recognizer =
        objc_getAssociatedObject(self, &kBHTInlineDownloadLongPressKey);
    if (enabled && !recognizer) {
        recognizer = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(bhtHandleInlineVideoDownloadLongPress:)];
        recognizer.minimumPressDuration = 0.4;
        recognizer.cancelsTouchesInView = NO;
        objc_setAssociatedObject(
            self, &kBHTInlineDownloadLongPressKey, recognizer,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addGestureRecognizer:recognizer];
    }
    recognizer.enabled = enabled;

    if (enabled)
        BHTPrioritizeDownloadLongPress(self, recognizer);
}
%new
- (void)bhtHandleInlineVideoDownloadLongPress:
    (UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan ||
        ![BHTSettings boolForKey:@"download_videos"]) {
        return;
    }

    TFSTwitterEntityMedia* media = BHTMediaEntityFromInlineView(self);
    if (!media) return;

    DownloadInlineButton* handler =
        objc_getAssociatedObject(self, &kBHTInlineDownloadHandlerKey);
    if (!handler) {
        handler = [%c(DownloadInlineButton) new];
        objc_setAssociatedObject(
            self, &kBHTInlineDownloadHandlerKey, handler,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [handler presentDownloadOptionsForMediaEntities:@[media]];
}
%end

// X's video-settings row can still be reached from the player menu. Make it
// eligible for video/GIF entities, retain the source entity on the native model,
// then replace tappedDownload with the same NeoFreeBird picker.
%hook TFSTwitterEntityMedia
- (BOOL)allowDownload {
    if ([BHTSettings boolForKey:@"download_videos"] &&
        BHTIsDownloadableVideoEntity(self)) {
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
        BHTIsDownloadableVideoEntity(mediaEntity)) {
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

    if (![BHTSettings boolForKey:@"download_videos"]) {
        return origItems;
    }

    NSArray* mediaEntities = BHTVideoEntitiesFromStatus(status);
    if (mediaEntities.count == 0) {
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
