#import "Likes/BHTLikesTab.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <mach-o/dyld.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

#import "Core/BHTBundle.h"
#import "CustomTabBar/CustomTabBarUtility.h"
#import "Headers/TWHeaders.h"
#import "Hooks/HookHelpers.h"
#import "Likes/BHTLikesNavigationUtility.h"

static NSString* const kBHTLikesPage = @"likes";
static char kBHTLikesEntryKey;
static char kBHTRetainedNativeLikesEntryKey;
static char kBHTNativeLikesEntryMarkerKey;
static char kBHTInjectedNativeLikesEntryKey;
static char kBHTOriginalNativePageKey;
static char kBHTNativeLikesNavigationMarkerKey;
static char kBHTNativeLikesControllerKey;
static char kBHTNativeLikesNavigationKey;
static char kBHTInitialResetPanMarkerKey;
static const long long kBHTLikesPanelID = 6; // X 12.9 Bookmarks panel
static const uintptr_t kBHTX129EntryFactoryOffset = 0x6CAFE8;
static const uintptr_t kBHTX129EntryFactoryJumpTableOffset = 0x1329880;
static const uintptr_t kBHTX129BookmarksFactoryCaseOffset = 0x6CB26C;

static NSObject* BHTLikesDiagnosticsLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSMutableDictionary* BHTMutableLikesDiagnostics(void) {
    static NSMutableDictionary* diagnostics;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        diagnostics = [@{
            @"activityHistoryInitialTab": @4,
            @"navigationMode": @"nativeBookmarksCarrier",
            @"photoRequestVariant": @"orig",
            @"videoVariantPolicy": @"highestBitrateMP4",
            @"rootHookInstalled": @YES,
            @"nativeRootCreations": @0,
            @"nativeSurfaceCreations": @0,
            @"nativeEntryFactoryAttempts": @0,
            @"nativeEntryFactorySuccesses": @0,
            @"nativeNavigationInstalls": @0,
            @"factoryRequests": @0,
            @"contentControllerRequests": @0,
            @"tabActivations": @0,
            @"topResets": @0,
            @"capturedMediaItems": @0,
            @"postRouteAttempts": @0,
            @"postURLAcceptances": @0
        } mutableCopy];
    });
    return diagnostics;
}

static void BHTSetLikesDiagnostic(NSString* key, id value) {
    if (key.length == 0 || !value) return;
    @synchronized(BHTLikesDiagnosticsLock()) {
        BHTMutableLikesDiagnostics()[key] = value;
    }
}

static void BHTIncrementLikesDiagnostic(NSString* key) {
    if (key.length == 0) return;
    @synchronized(BHTLikesDiagnosticsLock()) {
        NSMutableDictionary* diagnostics = BHTMutableLikesDiagnostics();
        diagnostics[key] = @([diagnostics[key] unsignedIntegerValue] + 1);
    }
}

NSDictionary* BHTLikesDiagnosticsSnapshot(void) {
    @synchronized(BHTLikesDiagnosticsLock()) {
        NSMutableDictionary* snapshot =
            [BHTMutableLikesDiagnostics() mutableCopy];
        snapshot[@"tabEnabledByCustomNavigation"] =
            @([CustomTabBarUtility likesTabEnabled]);
        snapshot[@"configuredActivityHistoryTabs"] =
            [BHTLikesNavigationUtility visiblePageIDsInOrder];
        snapshot[@"waterfallEnabled"] =
            @([BHTLikesNavigationUtility waterfallEnabled]);
        return [snapshot copy];
    }
}

NSString* BHTLikesPageID(void) {
    return kBHTLikesPage;
}

static id BHTSafeValue(id object, NSString* key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static id BHTCallObject(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector]
               ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector)
               : nil;
}

static UIViewController* BHTFindController(UIViewController* root, Class wanted) {
    if (!root || !wanted) return nil;
    if ([root isKindOfClass:wanted]) return root;
    for (UIViewController* child in root.childViewControllers) {
        UIViewController* result = BHTFindController(child, wanted);
        if (result) return result;
    }
    return BHTFindController(root.presentedViewController, wanted);
}

void BHTRefreshVisibleAppTabs(void) {
    Class navigationClass = NSClassFromString(@"T1TabbedAppNavigationViewController");
    if (!navigationClass) return;
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        UIViewController* controller =
            BHTFindController(window.rootViewController, navigationClass);
        if ([controller respondsToSelector:@selector(recalculateVisiblePanels)]) {
            ((void (*)(id, SEL))objc_msgSend)(controller,
                                              @selector(recalculateVisiblePanels));
            return;
        }
    }
}

#pragma mark - Native Likes timeline construction

static id BHTCurrentAccount(void) {
    Class hostClass = NSClassFromString(@"T1HostViewController");
    id host = [hostClass respondsToSelector:@selector(sharedHostViewController)]
                  ? ((id (*)(id, SEL))objc_msgSend)(hostClass,
                                                    @selector(sharedHostViewController))
                  : nil;
    return [host respondsToSelector:@selector(currentAccount)]
               ? ((id (*)(id, SEL))objc_msgSend)(host, @selector(currentAccount))
               : nil;
}

static id BHTInvokeAccountFactory(id receiver, SEL selector, id account) {
    if (!receiver || !selector || ![receiver respondsToSelector:selector]) return nil;
    NSMethodSignature* signature = [receiver methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 ||
        signature.methodReturnLength == 0) {
        return nil;
    }
    NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = receiver;
    invocation.selector = selector;
    id argument = account;
    [invocation setArgument:&argument atIndex:2];
    [invocation invoke];
    __unsafe_unretained id result = nil;
    [invocation getReturnValue:&result];
    return result;
}

static UIViewController* BHTMakeNativeLikesController(id account) {
    Class factoryClass = NSClassFromString(@"T1URTFavoritesViewControllerFactory");
    NSArray<NSString*>* selectors = @[
        @"makeViewControllerWithAccount:",
        @"viewControllerWithAccount:",
        @"makeFavoritesViewControllerWithAccount:",
        @"favoritesViewControllerWithAccount:"
    ];
    // Prefer the dedicated Favorites factory: unlike Activity History it needs
    // no guessed tab enum.
    for (NSString* name in selectors) {
        id result = BHTInvokeAccountFactory(factoryClass,
                                            NSSelectorFromString(name), account);
        if ([result isKindOfClass:UIViewController.class]) return result;
    }

    id factory = [factoryClass respondsToSelector:@selector(new)]
                     ? [factoryClass new]
                     : nil;
    for (NSString* name in selectors) {
        id result = BHTInvokeAccountFactory(factory,
                                            NSSelectorFromString(name), account);
        if ([result isKindOfClass:UIViewController.class]) return result;
    }

    // X 12.9 also exposes Likes through Activity History. Keep this as the
    // compatibility fallback and report the selector so device logs can
    // confirm whether it remains available.
    Class bridge = NSClassFromString(@"T1ActivityHistoryBridge");
    SEL bridgeSelector =
        NSSelectorFromString(@"makeActivityHistoryViewControllerWithAccount:initialTab:");
    if ([bridge respondsToSelector:bridgeSelector]) {
        NSMethodSignature* signature = [bridge methodSignatureForSelector:bridgeSelector];
        if (signature.numberOfArguments == 4) {
            NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.target = bridge;
            invocation.selector = bridgeSelector;
            id accountArgument = account;
            // X 12.9's bridge enum is one-based even though its segmented
            // control is zero-based: 3 opens Articles and 4 opens Likes. The
            // device report confirms this bridge is the available factory.
            NSInteger likesTab = 4;
            [invocation setArgument:&accountArgument atIndex:2];
            [invocation setArgument:&likesTab atIndex:3];
            [invocation invoke];
            __unsafe_unretained id result = nil;
            [invocation getReturnValue:&result];
            if ([result isKindOfClass:UIViewController.class]) return result;
        }
    }
    return nil;
}

#pragma mark - Media model extraction

@interface BHTLikedMediaItem : NSObject
@property(nonatomic, copy) NSString* identifier;
@property(nonatomic, strong) NSURL* previewURL;
@property(nonatomic, strong) NSURL* originalURL;
@property(nonatomic, strong) NSURL* videoURL;
@property(nonatomic) CGFloat aspectRatio;
@property(nonatomic) long long statusID;
@property(nonatomic, copy) NSString* statusText;
@property(nonatomic, strong) NSURL* statusURL;
@end

@implementation BHTLikedMediaItem
@end

static NSURL* BHTOriginalPhotoURL(NSString* rawURL) {
    if (rawURL.length == 0) return nil;
    NSURLComponents* components = [NSURLComponents componentsWithString:rawURL];
    if (!components) return [NSURL URLWithString:rawURL];

    NSString* extension = components.path.pathExtension.lowercaseString;
    if (extension.length > 0) {
        components.path = [components.path stringByDeletingPathExtension];
    }

    NSMutableArray<NSURLQueryItem*>* items = [NSMutableArray array];
    BOOL hasFormat = NO;
    for (NSURLQueryItem* item in components.queryItems ?: @[]) {
        if ([item.name isEqualToString:@"name"]) continue;
        if ([item.name isEqualToString:@"format"]) hasFormat = YES;
        [items addObject:item];
    }
    if (!hasFormat && extension.length > 0) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"format" value:extension]];
    }
    [items addObject:[NSURLQueryItem queryItemWithName:@"name" value:@"orig"]];
    components.queryItems = items;
    return components.URL ?: [NSURL URLWithString:rawURL];
}

static long long BHTVariantScore(id variant) {
    id bitrate = BHTSafeValue(variant, @"bitrate");
    if ([bitrate respondsToSelector:@selector(longLongValue)] &&
        [bitrate longLongValue] > 0) {
        return [bitrate longLongValue];
    }
    NSString* url = BHTSafeValue(variant, @"url");
    NSRegularExpression* regex =
        [NSRegularExpression regularExpressionWithPattern:@"/(\\d+)x(\\d+)/"
                                                  options:0
                                                    error:nil];
    NSTextCheckingResult* match =
        [regex firstMatchInString:url ?: @"" options:0 range:NSMakeRange(0, url.length)];
    if (match.numberOfRanges == 3) {
        return [[url substringWithRange:[match rangeAtIndex:1]] longLongValue] *
               [[url substringWithRange:[match rangeAtIndex:2]] longLongValue];
    }
    return 0;
}

static NSURL* BHTHighestVideoURL(id media) {
    id videoInfo = BHTSafeValue(media, @"videoInfo");
    NSArray* variants = BHTSafeValue(videoInfo, @"variants");
    id best = nil;
    long long bestScore = -1;
    for (id variant in variants) {
        NSString* type = BHTSafeValue(variant, @"contentType");
        NSString* url = BHTSafeValue(variant, @"url");
        if (![type isEqualToString:@"video/mp4"] || url.length == 0) continue;
        long long score = BHTVariantScore(variant);
        if (!best || score > bestScore) {
            best = variant;
            bestScore = score;
        }
    }
    NSString* url = BHTSafeValue(best, @"url");
    return url.length ? [NSURL URLWithString:url] : nil;
}

static id BHTStatusFromItem(id item) {
    if (!item) return nil;
    if ([item respondsToSelector:@selector(entities)] &&
        [item respondsToSelector:@selector(statusID)]) {
        return item;
    }
    for (NSString* selectorName in @[@"status", @"tweet", @"twitterStatus", @"displayedStatus"]) {
        id result = BHTCallObject(item, selectorName);
        if (result) return result;
    }
    for (NSString* ivarName in @[@"status", @"_status", @"tweet", @"_tweet"]) {
        Ivar ivar = class_getInstanceVariable([item class], ivarName.UTF8String);
        if (ivar) {
            id result = object_getIvar(item, ivar);
            if (result) return result;
        }
    }
    return nil;
}

static NSString* BHTReadableStatusText(id status) {
    for (NSString* key in @[@"fullText", @"text", @"displayText", @"tweetText"]) {
        id value = BHTSafeValue(status, key);
        if ([value isKindOfClass:NSString.class] && [value length] > 0) {
            return value;
        }
        if ([value isKindOfClass:NSAttributedString.class] &&
            ((NSAttributedString*)value).string.length > 0) {
            return ((NSAttributedString*)value).string;
        }
        id string = BHTSafeValue(value, @"string");
        if ([string isKindOfClass:NSString.class] && [string length] > 0) {
            return string;
        }
    }
    return nil;
}

static NSURL* BHTStatusURL(long long statusID) {
    if (statusID <= 0) return nil;
    return [NSURL URLWithString:
        [NSString stringWithFormat:@"https://x.com/i/status/%lld", statusID]];
}

static NSArray<BHTLikedMediaItem*>* BHTMediaItemsFromSections(NSArray* sections) {
    NSMutableArray<BHTLikedMediaItem*>* result = [NSMutableArray array];
    NSMutableSet<NSString*>* identifiers = [NSMutableSet set];

    for (id section in sections) {
        NSArray* items = [section isKindOfClass:NSArray.class] ? section : @[section];
        for (id wrappedItem in items) {
            id item = unwrapDataViewItem(wrappedItem);
            id status = BHTStatusFromItem(item);
            id entitySet = BHTSafeValue(status, @"entities");
            NSArray* mediaEntities = BHTSafeValue(entitySet, @"media");
            long long statusID = [BHTSafeValue(status, @"statusID") longLongValue];

            [mediaEntities enumerateObjectsUsingBlock:^(id media, NSUInteger index, BOOL* stop) {
                NSString* mediaURL = BHTSafeValue(media, @"mediaURLHttps");
                if (mediaURL.length == 0) mediaURL = BHTSafeValue(media, @"mediaURL");
                NSURL* originalURL = BHTOriginalPhotoURL(mediaURL);
                NSURL* videoURL = BHTHighestVideoURL(media);
                if (!originalURL && !videoURL) return;

                NSString* identifier = [NSString stringWithFormat:@"%lld-%lu-%@",
                                                                   statusID,
                                                                   (unsigned long)index,
                                                                   mediaURL ?: videoURL.absoluteString];
                if ([identifiers containsObject:identifier]) return;
                [identifiers addObject:identifier];

                CGFloat width = [BHTSafeValue(BHTSafeValue(media, @"originalInfo"), @"width") doubleValue];
                CGFloat height = [BHTSafeValue(BHTSafeValue(media, @"originalInfo"), @"height") doubleValue];
                if (width <= 0 || height <= 0) {
                    width = [BHTSafeValue(media, @"width") doubleValue];
                    height = [BHTSafeValue(media, @"height") doubleValue];
                }

                BHTLikedMediaItem* model = [BHTLikedMediaItem new];
                model.identifier = identifier;
                // The waterfall deliberately uses the original image too. A
                // tap must not be the point where a low-resolution thumbnail
                // finally changes to the full variant.
                model.previewURL = originalURL ?:
                    (mediaURL.length ? [NSURL URLWithString:mediaURL] : nil);
                model.originalURL = originalURL ?: model.previewURL;
                model.videoURL = videoURL;
                model.aspectRatio = (width > 0 && height > 0) ? width / height : 1.0;
                model.statusID = statusID;
                model.statusText = BHTReadableStatusText(status);
                model.statusURL = BHTStatusURL(statusID);
                [result addObject:model];
            }];
        }
    }
    return result;
}

#pragma mark - Waterfall UI

@protocol BHTWaterfallLayoutDelegate <NSObject>
- (CGFloat)waterfallAspectRatioAtIndexPath:(NSIndexPath*)indexPath;
@end

@interface BHTWaterfallLayout : UICollectionViewLayout
@property(nonatomic) NSInteger columns;
@property(nonatomic) CGFloat spacing;
@property(nonatomic, strong) NSArray<UICollectionViewLayoutAttributes*>* attributes;
@property(nonatomic) CGSize contentSize;
@end

@implementation BHTWaterfallLayout

- (instancetype)init {
    if ((self = [super init])) {
        _columns = 3;
        _spacing = 2;
    }
    return self;
}

- (void)prepareLayout {
    [super prepareLayout];
    NSInteger count = [self.collectionView numberOfItemsInSection:0];
    NSInteger columns = MAX(2, MIN(5, self.columns));
    CGFloat width = CGRectGetWidth(self.collectionView.bounds);
    CGFloat itemWidth = floor((width - self.spacing * (columns - 1)) / columns);
    NSMutableArray<NSNumber*>* heights = [NSMutableArray array];
    for (NSInteger i = 0; i < columns; i++) [heights addObject:@0];
    NSMutableArray* attributes = [NSMutableArray arrayWithCapacity:count];
    id<BHTWaterfallLayoutDelegate> delegate = (id)self.collectionView.delegate;

    for (NSInteger item = 0; item < count; item++) {
        NSInteger column = 0;
        for (NSInteger candidate = 1; candidate < columns; candidate++) {
            if (heights[candidate].doubleValue < heights[column].doubleValue) column = candidate;
        }
        NSIndexPath* indexPath = [NSIndexPath indexPathForItem:item inSection:0];
        CGFloat ratio = [delegate respondsToSelector:@selector(waterfallAspectRatioAtIndexPath:)]
                            ? [delegate waterfallAspectRatioAtIndexPath:indexPath]
                            : 1;
        ratio = MAX(0.45, MIN(2.4, ratio));
        CGFloat itemHeight = floor(itemWidth / ratio);
        CGFloat x = column * (itemWidth + self.spacing);
        CGFloat y = heights[column].doubleValue;
        UICollectionViewLayoutAttributes* attribute =
            [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        attribute.frame = CGRectMake(x, y, itemWidth, itemHeight);
        [attributes addObject:attribute];
        heights[column] = @(CGRectGetMaxY(attribute.frame) + self.spacing);
    }

    self.attributes = attributes;
    self.contentSize = CGSizeMake(width, [[heights valueForKeyPath:@"@max.self"] doubleValue]);
}

- (NSArray*)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray* visible = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes* attribute in self.attributes) {
        if (CGRectIntersectsRect(rect, attribute.frame)) [visible addObject:attribute];
    }
    return visible;
}

- (UICollectionViewLayoutAttributes*)layoutAttributesForItemAtIndexPath:(NSIndexPath*)indexPath {
    return indexPath.item < self.attributes.count ? self.attributes[indexPath.item] : nil;
}

- (CGSize)collectionViewContentSize {
    return self.contentSize;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return fabs(CGRectGetWidth(newBounds) - CGRectGetWidth(self.collectionView.bounds)) > 0.5;
}

@end


@interface BHTLikedMediaCell : UICollectionViewCell
@property(nonatomic, strong) UIImageView* imageView;
@property(nonatomic, strong) UIImageView* videoBadge;
@property(nonatomic, strong) NSURLSessionDataTask* task;
@property(nonatomic, strong) NSURL* representedURL;
@end

@implementation BHTLikedMediaCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _imageView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        [self.contentView addSubview:_imageView];

        _videoBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.circle.fill"]];
        _videoBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _videoBadge.tintColor = UIColor.whiteColor;
        _videoBadge.layer.shadowOpacity = 0.4;
        _videoBadge.layer.shadowRadius = 2;
        [self.contentView addSubview:_videoBadge];
        [NSLayoutConstraint activateConstraints:@[
            [_videoBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-7],
            [_videoBadge.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-7],
            [_videoBadge.widthAnchor constraintEqualToConstant:24],
            [_videoBadge.heightAnchor constraintEqualToConstant:24]
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.task cancel];
    self.task = nil;
    self.representedURL = nil;
    self.imageView.image = nil;
}

@end

static NSCache<NSURL*, UIImage*>* BHTMediaImageCache(void) {
    static NSCache* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 250;
    });
    return cache;
}

@interface BHTMediaPageController : UIViewController <UIScrollViewDelegate>
- (instancetype)initWithItem:(BHTLikedMediaItem*)item index:(NSUInteger)index;
@property(nonatomic, strong) BHTLikedMediaItem* item;
@property(nonatomic) NSUInteger index;
@property(nonatomic, strong) UIScrollView* scrollView;
@property(nonatomic, strong) UIImageView* imageView;
@property(nonatomic, strong) UIButton* playButton;
@property(nonatomic, strong) NSURLSessionDataTask* task;
@end

@implementation BHTMediaPageController

- (instancetype)initWithItem:(BHTLikedMediaItem*)item index:(NSUInteger)index {
    if ((self = [super init])) {
        _item = item;
        _index = index;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.minimumZoomScale = 1;
    self.scrollView.maximumZoomScale = 6;
    self.scrollView.directionalLockEnabled = YES;
    self.scrollView.delegate = self;
    [self.view addSubview:self.scrollView];
    self.imageView = [[UIImageView alloc] initWithFrame:self.scrollView.bounds];
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.scrollView addSubview:self.imageView];

    NSURL* imageURL = self.item.originalURL ?: self.item.previewURL;
    UIImage* cached = imageURL ? [BHTMediaImageCache() objectForKey:imageURL] : nil;
    if (cached) {
        self.imageView.image = cached;
    } else if (imageURL) {
        __weak typeof(self) weakSelf = self;
        self.task = [[NSURLSession sharedSession]
            dataTaskWithURL:imageURL
          completionHandler:^(NSData* data, NSURLResponse* response,
                              NSError* error) {
            UIImage* image = data ? [UIImage imageWithData:data] : nil;
            if (image) [BHTMediaImageCache() setObject:image forKey:imageURL];
            dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.imageView.image = image; });
        }];
        [self.task resume];
    }

    if (self.item.videoURL) {
        self.scrollView.maximumZoomScale = 1;
        self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.playButton.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageSymbolConfiguration* configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:56
                                                            weight:UIImageSymbolWeightRegular];
        [self.playButton setImage:
             [UIImage systemImageNamed:@"play.circle.fill"
                         withConfiguration:configuration]
                         forState:UIControlStateNormal];
        self.playButton.tintColor = UIColor.whiteColor;
        self.playButton.accessibilityLabel = @"Play video";
        [self.playButton addTarget:self
                            action:@selector(playVideo:)
                  forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:self.playButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.playButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [self.playButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
        ]];
    }
}

- (void)dealloc {
    [self.task cancel];
}

- (void)playVideo:(id)sender {
    if (!self.item.videoURL) return;
    AVPlayerViewController* player = [AVPlayerViewController new];
    player.player = [AVPlayer playerWithURL:self.item.videoURL];
    [self presentViewController:player
                       animated:YES
                     completion:^{ [player.player play]; }];
}

- (UIView*)viewForZoomingInScrollView:(UIScrollView*)scrollView {
    return self.item.videoURL ? nil : self.imageView;
}

@end

@interface BHTMediaPagerController : UIViewController <UIPageViewControllerDataSource,
                                                        UIPageViewControllerDelegate>
- (instancetype)initWithItems:(NSMutableArray<BHTLikedMediaItem*>*)items
                  initialIndex:(NSUInteger)index;
@property(nonatomic, strong) NSMutableArray<BHTLikedMediaItem*>* items;
@property(nonatomic) NSUInteger currentIndex;
@property(nonatomic) NSUInteger knownItemCount;
@property(nonatomic, strong) UIPageViewController* pageController;
@property(nonatomic, strong) UIButton* postButton;
@property(nonatomic, copy) dispatch_block_t loadMoreHandler;
- (BHTMediaPageController*)pageAtIndex:(NSUInteger)index;
- (BHTLikedMediaItem*)currentItem;
- (void)updatePostButton;
- (void)requestMoreIfNeededAtIndex:(NSUInteger)index;
- (void)mediaItemsDidUpdate;
@end

@implementation BHTMediaPagerController

- (instancetype)initWithItems:(NSMutableArray<BHTLikedMediaItem*>*)items
                  initialIndex:(NSUInteger)index {
    if ((self = [super init])) {
        _items = items;
        _currentIndex = MIN(index, items.count > 0 ? items.count - 1 : 0);
        _knownItemCount = items.count;
        self.title = @"Liked media";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    self.pageController = [[UIPageViewController alloc]
        initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
          navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
                        options:nil];
    self.pageController.dataSource = self;
    self.pageController.delegate = self;
    [self addChildViewController:self.pageController];
    self.pageController.view.frame = self.view.bounds;
    self.pageController.view.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.pageController.view];
    [self.pageController didMoveToParentViewController:self];

    BHTMediaPageController* initial = [self pageAtIndex:self.currentIndex];
    if (initial) {
        [self.pageController setViewControllers:@[initial]
                                      direction:UIPageViewControllerNavigationDirectionForward
                                       animated:NO
                                     completion:nil];
    }

    self.postButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.postButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.postButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
    self.postButton.tintColor = UIColor.whiteColor;
    [self.postButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.postButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.postButton.titleLabel.numberOfLines = 4;
    self.postButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.postButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.postButton.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    self.postButton.layer.cornerRadius = 12;
    self.postButton.clipsToBounds = YES;
    [self.postButton addTarget:self
                        action:@selector(openCurrentPost:)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.postButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.postButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.postButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.postButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [self.postButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [self.postButton.heightAnchor constraintLessThanOrEqualToConstant:116]
    ]];
    [self updatePostButton];
    [self requestMoreIfNeededAtIndex:self.currentIndex];
}

- (BHTMediaPageController*)pageAtIndex:(NSUInteger)index {
    if (index >= self.items.count) return nil;
    return [[BHTMediaPageController alloc] initWithItem:self.items[index]
                                                  index:index];
}

- (BHTLikedMediaItem*)currentItem {
    return self.currentIndex < self.items.count ? self.items[self.currentIndex] : nil;
}

- (void)updatePostButton {
    BHTLikedMediaItem* item = [self currentItem];
    NSString* text = [item.statusText
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString* title = text.length > 0
                          ? [NSString stringWithFormat:@"%@\nView post and replies", text]
                          : @"View post and replies";
    [self.postButton setTitle:title forState:UIControlStateNormal];
    self.postButton.enabled = item.statusID > 0 || item.statusURL != nil;
    self.postButton.accessibilityHint = @"Opens the original liked post";
}

- (void)requestMoreIfNeededAtIndex:(NSUInteger)index {
    if (!self.loadMoreHandler || self.items.count == 0) return;
    if (self.items.count - MIN(index, self.items.count - 1) <= 8) {
        dispatch_async(dispatch_get_main_queue(), self.loadMoreHandler);
    }
}

- (void)mediaItemsDidUpdate {
    if (!self.isViewLoaded || self.items.count == 0) return;
    NSUInteger previousCount = self.knownItemCount;
    BHTMediaPageController* visible =
        (BHTMediaPageController*)self.pageController.viewControllers.firstObject;
    NSString* visibleIdentifier = visible.item.identifier;
    self.knownItemCount = self.items.count;
    if (visibleIdentifier.length > 0) {
        NSUInteger updatedIndex =
            [self.items indexOfObjectPassingTest:^BOOL(
                BHTLikedMediaItem* candidate, NSUInteger index, BOOL* stop) {
                return [candidate.identifier isEqualToString:visibleIdentifier];
            }];
        if (updatedIndex != NSNotFound) self.currentIndex = updatedIndex;
    }
    self.currentIndex = MIN(self.currentIndex, self.items.count - 1);
    if (previousCount == 0 || self.currentIndex + 1 >= previousCount) {
        BHTMediaPageController* current = [self pageAtIndex:self.currentIndex];
        [self.pageController setViewControllers:@[current]
                                          direction:UIPageViewControllerNavigationDirectionForward
                                           animated:NO
                                         completion:nil];
    }
    [self updatePostButton];
}

- (void)openCurrentPost:(id)sender {
    BHTLikedMediaItem* item = [self currentItem];
    if (!item) return;
    BHTIncrementLikesDiagnostic(@"postRouteAttempts");
    NSURL* appURL = item.statusID > 0
                        ? [NSURL URLWithString:
                              [NSString stringWithFormat:@"twitter://status?id=%lld",
                                                         item.statusID]]
                        : nil;
    UIApplication* application = UIApplication.sharedApplication;
    if (!appURL) {
        if (item.statusURL) {
            [application openURL:item.statusURL
                          options:@{}
                completionHandler:^(BOOL success) {
                    if (success) {
                        BHTIncrementLikesDiagnostic(@"postURLAcceptances");
                    }
                }];
        }
        return;
    }
    NSURL* fallback = item.statusURL;
    [application openURL:appURL
                  options:@{}
        completionHandler:^(BOOL success) {
            if (success) {
                BHTIncrementLikesDiagnostic(@"postURLAcceptances");
            }
            if (!success && fallback) {
                [application openURL:fallback
                              options:@{}
                    completionHandler:^(BOOL fallbackSuccess) {
                        if (fallbackSuccess) {
                            BHTIncrementLikesDiagnostic(
                                @"postURLAcceptances");
                        }
                    }];
            }
        }];
}

- (UIViewController*)pageViewController:(UIPageViewController*)pageViewController
      viewControllerBeforeViewController:(UIViewController*)viewController {
    NSUInteger index = ((BHTMediaPageController*)viewController).index;
    return index > 0 ? [self pageAtIndex:index - 1] : nil;
}

- (UIViewController*)pageViewController:(UIPageViewController*)pageViewController
       viewControllerAfterViewController:(UIViewController*)viewController {
    NSUInteger index = ((BHTMediaPageController*)viewController).index;
    [self requestMoreIfNeededAtIndex:index];
    return index + 1 < self.items.count ? [self pageAtIndex:index + 1] : nil;
}

- (void)pageViewController:(UIPageViewController*)pageViewController
        didFinishAnimating:(BOOL)finished
   previousViewControllers:(NSArray<UIViewController*>*)previousViewControllers
       transitionCompleted:(BOOL)completed {
    if (!completed) return;
    BHTMediaPageController* visible =
        (BHTMediaPageController*)pageViewController.viewControllers.firstObject;
    self.currentIndex = visible.index;
    [self updatePostButton];
    [self requestMoreIfNeededAtIndex:self.currentIndex];
}

@end

#pragma mark - Likes container

@interface BHTLikesViewController : UIViewController <UICollectionViewDataSource,
                                                       UICollectionViewDelegate,
                                                       BHTWaterfallLayoutDelegate>
@property(nonatomic, strong) UIViewController* postsController;
@property(nonatomic, strong) UISegmentedControl* selector;
@property(nonatomic, strong) UICollectionView* collectionView;
@property(nonatomic, strong) BHTWaterfallLayout* waterfallLayout;
@property(nonatomic, strong) NSMutableArray<BHTLikedMediaItem*>* mediaItems;
@property(nonatomic, strong) NSMutableSet<NSString*>* mediaIDs;
@property(nonatomic, weak) BHTMediaPagerController* activeMediaPager;
@property(nonatomic) BOOL requestedMore;
@property(nonatomic) BOOL needsInitialTopReset;
@property(nonatomic) BOOL hasBeenActivated;
@property(nonatomic) NSUInteger initialResetGeneration;
@property(nonatomic) NSUInteger loadRequestGeneration;
- (void)ingestSections:(NSArray*)sections;
- (void)loadMoreMedia;
- (void)resetToNewest;
- (void)activateForFirstPresentation;
- (void)configureWaterfallInterface;
@end

static void BHTFindVerticalScrollView(UIView* view, UIScrollView** best,
                                      CGFloat* bestScore) {
    if ([view isKindOfClass:UIScrollView.class]) {
        UIScrollView* scroll = (UIScrollView*)view;
        CGFloat range = scroll.contentSize.height - scroll.bounds.size.height;
        CGFloat score = MAX(0, range) + scroll.bounds.size.height / 1000.0;
        if (!*best || score > *bestScore) {
            *best = scroll;
            *bestScore = score;
        }
    }
    for (UIView* subview in view.subviews) {
        BHTFindVerticalScrollView(subview, best, bestScore);
    }
}

static UIScrollView* BHTFindScrollableView(UIView* view) {
    UIScrollView* best = nil;
    CGFloat bestScore = -1;
    BHTFindVerticalScrollView(view, &best, &bestScore);
    return best;
}

@implementation BHTLikesViewController

- (instancetype)init {
    if ((self = [super init])) {
        _postsController = BHTMakeNativeLikesController(BHTCurrentAccount());
        _mediaItems = [NSMutableArray array];
        _mediaIDs = [NSMutableSet set];
        _needsInitialTopReset = YES;
        self.title =
            [[BHTBundle sharedBundle] localizedStringForKey:@"MY_LIKES_TITLE"];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(likesNavigationSettingsChanged:)
                   name:BHTLikesNavigationSettingsDidChangeNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    if (self.postsController) {
        [self addChildViewController:self.postsController];
        self.postsController.view.frame = self.view.bounds;
        self.postsController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.postsController.view];
        [self.postsController didMoveToParentViewController:self];
    } else {
        UILabel* unavailable = [[UILabel alloc] initWithFrame:self.view.bounds];
        unavailable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        unavailable.numberOfLines = 0;
        unavailable.textAlignment = NSTextAlignmentCenter;
        unavailable.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"LIKES_UNAVAILABLE_MESSAGE"];
        [self.view addSubview:unavailable];
    }

    [self configureWaterfallInterface];
}

- (void)likesNavigationSettingsChanged:(NSNotification*)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isViewLoaded) [self configureWaterfallInterface];
        BHTRefreshLikesActivityHistoryConfiguration(
            self.postsController);
    });
}

- (void)configureWaterfallInterface {
    BOOL waterfallEnabled =
        [BHTLikesNavigationUtility waterfallEnabled];
    if (waterfallEnabled && !self.collectionView) {
        BHTBundle* bundle = [BHTBundle sharedBundle];
        self.selector = [[UISegmentedControl alloc]
            initWithItems:@[
                [bundle localizedStringForKey:@"LIKES_POSTS_SEGMENT"],
                [bundle localizedStringForKey:@"LIKES_MEDIA_SEGMENT"]
            ]];
        self.selector.selectedSegmentIndex = 0;
        [self.selector addTarget:self
                          action:@selector(selectionChanged:)
                forControlEvents:UIControlEventValueChanged];
        self.navigationItem.titleView = self.selector;

        self.waterfallLayout = [BHTWaterfallLayout new];
        self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds
                                                 collectionViewLayout:self.waterfallLayout];
        self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
        self.collectionView.dataSource = self;
        self.collectionView.delegate = self;
        self.collectionView.hidden = YES;
        [self.collectionView registerClass:BHTLikedMediaCell.class forCellWithReuseIdentifier:@"media"];
        [self.view addSubview:self.collectionView];

        UIPinchGestureRecognizer* pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)];
        [self.collectionView addGestureRecognizer:pinch];
        [self.collectionView.panGestureRecognizer
            addTarget:self
               action:@selector(cancelInitialResetFromPan:)];
    } else if (!waterfallEnabled && self.collectionView) {
        self.postsController.view.hidden = NO;
        self.postsController.view.userInteractionEnabled = YES;
        self.postsController.view.accessibilityElementsHidden = NO;
        [self.collectionView removeFromSuperview];
        self.collectionView = nil;
        self.waterfallLayout = nil;
        if (self.navigationItem.titleView == self.selector) {
            self.navigationItem.titleView = nil;
        }
        self.selector = nil;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.hasBeenActivated || !self.needsInitialTopReset) return;
    [self activateForFirstPresentation];
}

- (void)activateForFirstPresentation {
    self.hasBeenActivated = YES;
    if (!self.needsInitialTopReset) return;
    self.needsInitialTopReset = NO;
    [self resetToNewest];
}

- (void)resetToNewest {
    if (!self.isViewLoaded) {
        self.needsInitialTopReset = YES;
        return;
    }
    BHTIncrementLikesDiagnostic(@"topResets");

    // Activity History restores a private child scroll view during several
    // delayed layout passes. Retry only during the first presentation of this
    // app-session controller. A user pan cancels the remaining retries, so
    // leaving and returning to Likes preserves the exact reading position.
    NSUInteger generation = ++self.initialResetGeneration;
    __weak typeof(self) weakSelf = self;
    void (^resetOffsets)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf ||
            strongSelf.initialResetGeneration != generation) {
            return;
        }
        [strongSelf.postsController.view layoutIfNeeded];
        UIScrollView* nativeScroll =
            BHTFindScrollableView(strongSelf.postsController.view);
        BOOL userInteracting =
            nativeScroll &&
            (nativeScroll.dragging || nativeScroll.tracking ||
             nativeScroll.decelerating ||
             nativeScroll.panGestureRecognizer.state ==
                 UIGestureRecognizerStateBegan ||
             nativeScroll.panGestureRecognizer.state ==
                 UIGestureRecognizerStateChanged);
        if (userInteracting) {
            strongSelf.initialResetGeneration++;
            return;
        }
        if (nativeScroll) {
            if (![objc_getAssociatedObject(
                    nativeScroll.panGestureRecognizer,
                    &kBHTInitialResetPanMarkerKey) boolValue]) {
                [nativeScroll.panGestureRecognizer
                    addTarget:strongSelf
                       action:@selector(cancelInitialResetFromPan:)];
                objc_setAssociatedObject(
                    nativeScroll.panGestureRecognizer,
                    &kBHTInitialResetPanMarkerKey, @YES,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            CGFloat top = -nativeScroll.adjustedContentInset.top;
            [nativeScroll setContentOffset:
                CGPointMake(nativeScroll.contentOffset.x, top) animated:NO];
        }
        if (strongSelf.collectionView) {
            CGFloat top = -strongSelf.collectionView.adjustedContentInset.top;
            [strongSelf.collectionView setContentOffset:
                CGPointMake(strongSelf.collectionView.contentOffset.x, top)
                                             animated:NO];
        }
    };
    for (NSNumber* delay in @[@0, @100, @350, @800, @1500]) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          delay.longLongValue * NSEC_PER_MSEC),
            dispatch_get_main_queue(), resetOffsets);
    }
}

- (void)cancelInitialResetFromPan:(UIPanGestureRecognizer*)pan {
    if (pan.state == UIGestureRecognizerStateBegan ||
        pan.state == UIGestureRecognizerStateChanged) {
        self.initialResetGeneration++;
    }
}

- (void)selectionChanged:(UISegmentedControl*)sender {
    BOOL media = sender.selectedSegmentIndex == 1;
    // Keep the native Likes timeline alive behind the opaque media grid. X
    // pauses pagination for hidden controller views, which previously forced
    // users to return to Posts and scroll manually before more media appeared.
    self.postsController.view.hidden = NO;
    self.postsController.view.userInteractionEnabled = !media;
    self.postsController.view.accessibilityElementsHidden = media;
    self.collectionView.hidden = !media;
    if (media) {
        [self.view bringSubviewToFront:self.collectionView];
        if (self.mediaItems.count < 12) [self loadMoreMedia];
    }
}

- (void)pinched:(UIPinchGestureRecognizer*)pinch {
    if (pinch.state != UIGestureRecognizerStateEnded) return;
    NSInteger delta = pinch.scale > 1 ? -1 : 1;
    self.waterfallLayout.columns = MAX(2, MIN(5, self.waterfallLayout.columns + delta));
    [self.waterfallLayout invalidateLayout];
}

- (void)ingestSections:(NSArray*)sections {
    NSArray* incoming = BHTMediaItemsFromSections(sections);
    if (incoming.count == 0) {
        self.loadRequestGeneration++;
        self.requestedMore = NO;
        return;
    }

    NSMutableSet<NSString*>* incomingIDs = [NSMutableSet set];
    BOOL overlapsExisting = NO;
    for (BHTLikedMediaItem* item in incoming) {
        if (item.identifier.length == 0 ||
            [incomingIDs containsObject:item.identifier]) {
            continue;
        }
        [incomingIDs addObject:item.identifier];
        if ([self.mediaIDs containsObject:item.identifier]) {
            overlapsExisting = YES;
        }
    }

    // X normally sends the complete ordered section snapshot. Rebuild from
    // that order so newly liked media moves to the top. If it sends a page-only
    // delta, a pending pagination request identifies it as older content and
    // appends it instead; a refresh delta is prepended.
    NSMutableArray<BHTLikedMediaItem*>* ordered = [NSMutableArray array];
    NSMutableSet<NSString*>* orderedIDs = [NSMutableSet set];
    void (^appendUnique)(NSArray<BHTLikedMediaItem*>*) =
        ^(NSArray<BHTLikedMediaItem*>* items) {
            for (BHTLikedMediaItem* item in items) {
                if (item.identifier.length == 0 ||
                    [orderedIDs containsObject:item.identifier]) {
                    continue;
                }
                [orderedIDs addObject:item.identifier];
                [ordered addObject:item];
            }
        };

    BOOL pageOnlyPagination = self.requestedMore && !overlapsExisting;
    if (pageOnlyPagination) {
        appendUnique(self.mediaItems);
        appendUnique(incoming);
    } else {
        appendUnique(incoming);
        appendUnique(self.mediaItems);
    }

    NSArray<NSString*>* previousOrder =
        [self.mediaItems valueForKey:@"identifier"];
    NSArray<NSString*>* nextOrder = [ordered valueForKey:@"identifier"];
    BOOL changed = ![previousOrder isEqualToArray:nextOrder];
    [self.mediaItems setArray:ordered];
    [self.mediaIDs setSet:orderedIDs];
    BHTSetLikesDiagnostic(@"capturedMediaItems", @(self.mediaItems.count));
    self.loadRequestGeneration++;
    self.requestedMore = NO;
    if (changed && self.isViewLoaded) {
        [self.collectionView reloadData];
        [self.activeMediaPager mediaItemsDidUpdate];
    }
}

- (NSInteger)collectionView:(UICollectionView*)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.mediaItems.count;
}

- (UICollectionViewCell*)collectionView:(UICollectionView*)collectionView
                 cellForItemAtIndexPath:(NSIndexPath*)indexPath {
    BHTLikedMediaCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"media" forIndexPath:indexPath];
    BHTLikedMediaItem* item = self.mediaItems[indexPath.item];
    cell.videoBadge.hidden = item.videoURL == nil;
    cell.representedURL = item.previewURL;
    UIImage* cached = item.previewURL
                          ? [BHTMediaImageCache() objectForKey:item.previewURL]
                          : nil;
    if (cached) {
        cell.imageView.image = cached;
    } else if (item.previewURL) {
        __weak BHTLikedMediaCell* weakCell = cell;
        NSURL* url = item.previewURL;
        cell.task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            UIImage* image = data ? [UIImage imageWithData:data] : nil;
            if (image) [BHTMediaImageCache() setObject:image forKey:url];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([weakCell.representedURL isEqual:url]) {
                    weakCell.imageView.image = image;
                }
            });
        }];
        [cell.task resume];
    }
    return cell;
}

- (CGFloat)waterfallAspectRatioAtIndexPath:(NSIndexPath*)indexPath {
    return self.mediaItems[indexPath.item].aspectRatio;
}

- (void)collectionView:(UICollectionView*)collectionView didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    BHTMediaPagerController* viewer =
        [[BHTMediaPagerController alloc] initWithItems:self.mediaItems
                                          initialIndex:indexPath.item];
    __weak typeof(self) weakSelf = self;
    viewer.loadMoreHandler = ^{ [weakSelf loadMoreMedia]; };
    self.activeMediaPager = viewer;
    [self.navigationController pushViewController:viewer animated:YES];
}

- (void)collectionView:(UICollectionView*)collectionView
        willDisplayCell:(UICollectionViewCell*)cell
  forItemAtIndexPath:(NSIndexPath*)indexPath {
    if (self.mediaItems.count - indexPath.item <= 8) [self loadMoreMedia];
}

- (void)loadMoreMedia {
    if (self.requestedMore || !self.postsController) return;
    self.postsController.view.hidden = NO;
    UIScrollView* nativeScroll = BHTFindScrollableView(self.postsController.view);
    if (!nativeScroll) return;

    CGFloat top = -nativeScroll.adjustedContentInset.top;
    CGFloat bottom = MAX(top,
        nativeScroll.contentSize.height - nativeScroll.bounds.size.height +
            nativeScroll.adjustedContentInset.bottom);
    if (bottom <= top + 1) return;

    self.requestedMore = YES;
    NSUInteger generation = ++self.loadRequestGeneration;
    void (^scrollToBottom)(void) = ^{
        [nativeScroll setContentOffset:
            CGPointMake(nativeScroll.contentOffset.x, bottom) animated:NO];
    };
    if (fabs(nativeScroll.contentOffset.y - bottom) < 1) {
        CGFloat nudge = MAX(top, bottom - MAX(80, nativeScroll.bounds.size.height * 0.2));
        [nativeScroll setContentOffset:
            CGPointMake(nativeScroll.contentOffset.x, nudge) animated:NO];
        dispatch_async(dispatch_get_main_queue(), scrollToBottom);
    } else {
        scrollToBottom();
    }

    // A cursor can legitimately return no new posts. Release the throttle so
    // another end-of-grid/page gesture can retry instead of getting stuck.
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (weakSelf.loadRequestGeneration == generation) {
            weakSelf.requestedMore = NO;
        }
    });
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
    if (scrollView != self.collectionView || self.requestedMore || self.mediaItems.count == 0) return;
    CGFloat remaining = scrollView.contentSize.height - CGRectGetMaxY((CGRect){scrollView.contentOffset, scrollView.bounds.size});
    if (remaining <= 900) [self loadMoreMedia];
}

@end

BOOL BHTIsManagedLikesActivityHistoryController(
    UIViewController* controller) {
    UIViewController* current = controller;
    while (current) {
        if ([current isKindOfClass:BHTLikesViewController.class]) {
            return YES;
        }
        current = current.parentViewController;
    }
    return NO;
}

static Class BHTNativeBookmarksEntryClass(void) {
    return NSClassFromString(
        @"T1TwitterSwift.BookmarksAppNavigationTabEntry");
}

static Class BHTNativeBookmarksNavigationClass(void) {
    return NSClassFromString(
        @"T1TwitterSwift.BookmarksNavigationController");
}

static uintptr_t BHTT1TwitterImageBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index++) {
        const char* name = _dyld_get_image_name(index);
        if (name &&
            strstr(name, "/T1Twitter.framework/T1Twitter") != NULL) {
            return (uintptr_t)_dyld_get_image_header(index);
        }
    }
    return 0;
}

static id BHTMakeNativeBookmarksEntry(void) {
    BHTIncrementLikesDiagnostic(@"nativeEntryFactoryAttempts");
    uintptr_t imageBase = BHTT1TwitterImageBase();
    if (imageBase == 0) {
        BHTSetLikesDiagnostic(@"nativeEntryFactoryFailure",
                              @"T1TwitterImageNotFound");
        return nil;
    }

    // X 12.9 build 10's own panel-entry switch. Its case 6 allocates and
    // initializes BookmarksAppNavigationTabEntry with the current account.
    // Validate the switch prologue, panel-6 jump-table target, and invariant
    // case instructions before calling so another X build is skipped safely
    // instead of jumping into a changed private function.
    uintptr_t factoryAddress = imageBase + kBHTX129EntryFactoryOffset;
    const uint32_t* instructions = (const uint32_t*)factoryAddress;
    const uint8_t* jumpTable =
        (const uint8_t*)(imageBase +
                         kBHTX129EntryFactoryJumpTableOffset);
    const uint32_t* bookmarksCase =
        (const uint32_t*)(imageBase +
                          kBHTX129BookmarksFactoryCaseOffset);
    if (instructions[0] != 0xD10203FF ||
        instructions[6] != 0xF1005C1F ||
        jumpTable[kBHTLikesPanelID] != 0x91 ||
        bookmarksCase[0] != 0xD2800000 ||
        bookmarksCase[3] != 0xAA0003F4 ||
        bookmarksCase[4] != 0xAA1303E0 ||
        bookmarksCase[6] != 0xAA0003F3) {
        BHTSetLikesDiagnostic(@"nativeEntryFactoryFailure",
                              @"X129FactorySignatureMismatch");
        return nil;
    }

    id account = BHTCurrentAccount();
    if (!account) {
        BHTSetLikesDiagnostic(@"nativeEntryFactoryFailure",
                              @"CurrentAccountUnavailable");
        return nil;
    }

    typedef id (*BHTNativeEntryFactory)(long long, id, id);
    BHTNativeEntryFactory factory =
        (BHTNativeEntryFactory)factoryAddress;
    id entry = factory(kBHTLikesPanelID, account, nil);
    Class expectedClass = BHTNativeBookmarksEntryClass();
    T1TabView* tabView = BHTCallObject(entry, @"tabView");
    if (!entry || !expectedClass ||
        ![entry isKindOfClass:expectedClass] || !tabView) {
        BHTSetLikesDiagnostic(@"nativeEntryFactoryFailure",
                              @"NativeBookmarksEntryValidationFailed");
        return nil;
    }

    BHTIncrementLikesDiagnostic(@"nativeEntryFactorySuccesses");
    BHTSetLikesDiagnostic(@"nativeCarrierClass",
                          NSStringFromClass([entry class]));
    BHTSetLikesDiagnostic(@"nativeCarrierPanelID",
                          @(tabView.panelID));
    return entry;
}

BOOL BHTIsNativeLikesEntry(id entry) {
    return [objc_getAssociatedObject(entry,
                                     &kBHTNativeLikesEntryMarkerKey)
        boolValue];
}

static void BHTConfigureNativeLikesEntry(id entry, BOOL injected) {
    T1TabView* tabView = BHTCallObject(entry, @"tabView");
    if (!entry || !tabView) return;
    if (!objc_getAssociatedObject(tabView, &kBHTOriginalNativePageKey)) {
        objc_setAssociatedObject(
            tabView, &kBHTOriginalNativePageKey,
            tabView.scribePage.length ? tabView.scribePage : @"bookmarks",
            OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    objc_setAssociatedObject(entry, &kBHTNativeLikesEntryMarkerKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(entry, &kBHTInjectedNativeLikesEntryKey,
                             @(injected),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(tabView, &kBHTLikesEntryKey, entry,
                             OBJC_ASSOCIATION_ASSIGN);
    tabView.scribePage = kBHTLikesPage;
}

static void BHTRestoreNativeEntryPage(id entry) {
    T1TabView* tabView = BHTCallObject(entry, @"tabView");
    NSString* original =
        objc_getAssociatedObject(tabView, &kBHTOriginalNativePageKey);
    if (original.length > 0) tabView.scribePage = original;
    objc_setAssociatedObject(tabView, &kBHTLikesEntryKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(tabView, &kBHTNativeLikesNavigationKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(entry, &kBHTNativeLikesEntryMarkerKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void BHTRecordNativeLikesFactoryRequest(BOOL contentController) {
    BHTIncrementLikesDiagnostic(contentController
                                    ? @"contentControllerRequests"
                                    : @"factoryRequests");
}

BOOL BHTIsNativeLikesNavigationController(UIViewController* controller) {
    return [objc_getAssociatedObject(
        controller, &kBHTNativeLikesNavigationMarkerKey) boolValue];
}

static void BHTMarkNativeLikesNavigationController(
    UIViewController* controller) {
    if (!controller) return;
    objc_setAssociatedObject(controller,
                             &kBHTNativeLikesNavigationMarkerKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BHTSetLikesDiagnostic(@"nativeNavigationClass",
                          NSStringFromClass([controller class]));
}

void BHTConnectNativeLikesNavigationController(
    UIViewController* controller, UIView* tabView) {
    if (!controller || !tabView) return;
    BHTMarkNativeLikesNavigationController(controller);
    objc_setAssociatedObject(tabView, &kBHTNativeLikesNavigationKey,
                             controller,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void BHTConnectNativeLikesNavigationTree(UIViewController* root, id entry) {
    UIViewController* navigation =
        BHTFindController(root, BHTNativeBookmarksNavigationClass());
    UIView* tabView = BHTCallObject(entry, @"tabView");
    if (navigation && tabView) {
        BHTConnectNativeLikesNavigationController(navigation, tabView);
    }
}

static BHTLikesViewController*
BHTLikesControllerForNativeNavigation(UIViewController* navigation,
                                      BOOL create) {
    BHTLikesViewController* likes =
        objc_getAssociatedObject(navigation, &kBHTNativeLikesControllerKey);
    if (!likes && create) {
        likes = [BHTLikesViewController new];
        objc_setAssociatedObject(navigation, &kBHTNativeLikesControllerKey,
                                 likes,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BHTIncrementLikesDiagnostic(@"nativeRootCreations");
        BHTIncrementLikesDiagnostic(@"nativeSurfaceCreations");
        BHTSetLikesDiagnostic(@"standaloneRootClass",
                              NSStringFromClass([likes class]));
        BHTSetLikesDiagnostic(@"postsControllerClass",
            likes.postsController
                ? NSStringFromClass([likes.postsController class])
                : @"");
    }
    return likes;
}

void BHTInstallNativeLikesNavigationController(
    UIViewController* navigation, BOOL resetToNewest) {
    if (![CustomTabBarUtility likesTabEnabled] ||
        !BHTIsNativeLikesNavigationController(navigation)) {
        return;
    }

    BHTLikesViewController* likes =
        BHTLikesControllerForNativeNavigation(navigation, YES);
    if (!likes) return;

    if ([navigation isKindOfClass:UINavigationController.class]) {
        UINavigationController* nativeNavigation =
            (UINavigationController*)navigation;
        if (nativeNavigation.viewControllers.count != 1 ||
            nativeNavigation.viewControllers.firstObject != likes) {
            [nativeNavigation setViewControllers:@[likes] animated:NO];
            BHTIncrementLikesDiagnostic(@"nativeNavigationInstalls");
        }
    } else if (likes.parentViewController != navigation) {
        [navigation addChildViewController:likes];
        likes.view.frame = navigation.view.bounds;
        likes.view.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
        [navigation.view addSubview:likes.view];
        [likes didMoveToParentViewController:navigation];
        BHTIncrementLikesDiagnostic(@"nativeNavigationInstalls");
    }

    if (resetToNewest) [likes resetToNewest];
}

static void BHTActivateLikesTabViewNow(T1TabView* view) {
    if (![CustomTabBarUtility likesTabEnabled] || !view.isSelected ||
        ![view.scribePage isEqualToString:kBHTLikesPage]) {
        return;
    }
    UIViewController* navigation =
        objc_getAssociatedObject(view, &kBHTNativeLikesNavigationKey);
    if (!navigation) return;
    BHTIncrementLikesDiagnostic(@"tabActivations");
    // Re-selecting the bottom destination must not jump the retained Likes
    // controller back to the top. Its one-time first-presentation reset is
    // owned by BHTLikesViewController.
    BHTInstallNativeLikesNavigationController(navigation, NO);
    BHTLikesViewController* likes =
        BHTLikesControllerForNativeNavigation(navigation, NO);
    [likes activateForFirstPresentation];
}

void BHTActivateLikesTabView(UIView* view) {
    // T1TabView changes selection while the Swift navigation owner is still
    // mutating its controller arrays. Defer root access/containment until that
    // transaction finishes to avoid re-entering the private selection path.
    __weak T1TabView* weakView = (T1TabView*)view;
    dispatch_async(dispatch_get_main_queue(), ^{
        BHTActivateLikesTabViewNow(weakView);
    });
}

NSArray* BHTEntriesByInstallingLikesDestination(NSArray* entries) {
    BOOL enabled = [CustomTabBarUtility likesTabEnabled];
    NSMutableArray* result = [entries mutableCopy] ?: [NSMutableArray array];
    id likesEntry = nil;
    id anchor = nil;
    Class nativeEntryClass = BHTNativeBookmarksEntryClass();

    for (id entry in [result copy]) {
        if (BHTIsNativeLikesEntry(entry)) {
            likesEntry = entry;
            if (!enabled) {
                BOOL injected =
                    [objc_getAssociatedObject(
                        entry, &kBHTInjectedNativeLikesEntryKey) boolValue];
                BHTRestoreNativeEntryPage(entry);
                if (injected) [result removeObjectIdenticalTo:entry];
            }
            continue;
        }
        if (enabled && nativeEntryClass &&
            [entry isKindOfClass:nativeEntryClass] && !likesEntry) {
            likesEntry = entry;
            BHTConfigureNativeLikesEntry(entry, NO);
            continue;
        }
        if (!anchor) anchor = entry;
    }

    if (enabled && !likesEntry) {
        likesEntry =
            objc_getAssociatedObject(anchor,
                                     &kBHTRetainedNativeLikesEntryKey);
        if (![likesEntry isKindOfClass:nativeEntryClass]) {
            likesEntry = BHTMakeNativeBookmarksEntry();
            if (anchor && likesEntry) {
                objc_setAssociatedObject(anchor,
                                         &kBHTRetainedNativeLikesEntryKey,
                                         likesEntry,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        if (likesEntry) {
            BHTConfigureNativeLikesEntry(likesEntry, YES);
            [result addObject:likesEntry];
        }
    }

    return result;
}

BOOL BHTCaptureLikesSections(UIViewController* dataViewController, NSArray* sections) {
    UIViewController* current = dataViewController;
    while (current && ![current isKindOfClass:BHTLikesViewController.class]) {
        current = current.parentViewController;
    }
    if ([current isKindOfClass:BHTLikesViewController.class]) {
        [(BHTLikesViewController*)current ingestSections:sections];
        return YES;
    }
    return NO;
}
