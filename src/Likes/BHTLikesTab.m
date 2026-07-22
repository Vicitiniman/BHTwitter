#import "Likes/BHTLikesTab.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "Hooks/HookHelpers.h"

static NSString* const kBHTLikesPage = @"likes";
static char kBHTOriginalTabPageKey;

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
            NSInteger likesTab = 1;
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
                model.previewURL =
                    mediaURL.length ? [NSURL URLWithString:mediaURL]
                                    : originalURL;
                model.originalURL = originalURL ?: model.previewURL;
                model.videoURL = videoURL;
                model.aspectRatio = (width > 0 && height > 0) ? width / height : 1.0;
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

@interface BHTPhotoViewerController : UIViewController <UIScrollViewDelegate>
- (instancetype)initWithItem:(BHTLikedMediaItem*)item;
@property(nonatomic, strong) BHTLikedMediaItem* item;
@property(nonatomic, strong) UIScrollView* scrollView;
@property(nonatomic, strong) UIImageView* imageView;
@end

@implementation BHTPhotoViewerController

- (instancetype)initWithItem:(BHTLikedMediaItem*)item {
    if ((self = [super init])) _item = item;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.minimumZoomScale = 1;
    self.scrollView.maximumZoomScale = 6;
    self.scrollView.delegate = self;
    [self.view addSubview:self.scrollView];
    self.imageView = [[UIImageView alloc] initWithFrame:self.scrollView.bounds];
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.scrollView addSubview:self.imageView];

    UIImage* cached = [BHTMediaImageCache() objectForKey:self.item.originalURL];
    if (cached) {
        self.imageView.image = cached;
    } else {
        __weak typeof(self) weakSelf = self;
        NSURL* imageURL = self.item.originalURL;
        [[[NSURLSession sharedSession] dataTaskWithURL:imageURL
                                    completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            UIImage* image = data ? [UIImage imageWithData:data] : nil;
            if (image) [BHTMediaImageCache() setObject:image forKey:imageURL];
            dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.imageView.image = image; });
        }] resume];
    }
}

- (UIView*)viewForZoomingInScrollView:(UIScrollView*)scrollView {
    return self.imageView;
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
@property(nonatomic) BOOL requestedMore;
- (void)ingestSections:(NSArray*)sections;
@end

static UIScrollView* BHTFindScrollableView(UIView* view) {
    if ([view isKindOfClass:UIScrollView.class]) return (UIScrollView*)view;
    for (UIView* subview in view.subviews) {
        UIScrollView* result = BHTFindScrollableView(subview);
        if (result) return result;
    }
    return nil;
}

@implementation BHTLikesViewController

- (instancetype)init {
    if ((self = [super init])) {
        _postsController = BHTMakeNativeLikesController(BHTCurrentAccount());
        _mediaItems = [NSMutableArray array];
        _mediaIDs = [NSMutableSet set];
        self.title =
            [[BHTBundle sharedBundle] localizedStringForKey:@"MY_LIKES_TITLE"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    BOOL waterfallEnabled = [BHTSettings boolForKey:@"likes_media_waterfall"];
    if (waterfallEnabled) {
        BHTBundle* bundle = [BHTBundle sharedBundle];
        self.selector = [[UISegmentedControl alloc]
            initWithItems:@[
                [bundle localizedStringForKey:@"LIKES_POSTS_SEGMENT"],
                [bundle localizedStringForKey:@"LIKES_MEDIA_SEGMENT"]
            ]];
        self.selector.selectedSegmentIndex = 0;
        [self.selector addTarget:self action:@selector(selectionChanged:) forControlEvents:UIControlEventValueChanged];
        self.navigationItem.titleView = self.selector;
    }

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

    if (waterfallEnabled) {
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
    }
}

- (void)selectionChanged:(UISegmentedControl*)sender {
    BOOL media = sender.selectedSegmentIndex == 1;
    self.postsController.view.hidden = media;
    self.collectionView.hidden = !media;
}

- (void)pinched:(UIPinchGestureRecognizer*)pinch {
    if (pinch.state != UIGestureRecognizerStateEnded) return;
    NSInteger delta = pinch.scale > 1 ? -1 : 1;
    self.waterfallLayout.columns = MAX(2, MIN(5, self.waterfallLayout.columns + delta));
    [self.waterfallLayout invalidateLayout];
}

- (void)ingestSections:(NSArray*)sections {
    NSArray* incoming = BHTMediaItemsFromSections(sections);
    BOOL changed = NO;
    for (BHTLikedMediaItem* item in incoming) {
        if ([self.mediaIDs containsObject:item.identifier]) continue;
        [self.mediaIDs addObject:item.identifier];
        [self.mediaItems addObject:item];
        changed = YES;
    }
    self.requestedMore = NO;
    if (changed && self.isViewLoaded) [self.collectionView reloadData];
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
    BHTLikedMediaItem* item = self.mediaItems[indexPath.item];
    if (item.videoURL) {
        AVPlayerViewController* player = [AVPlayerViewController new];
        player.player = [AVPlayer playerWithURL:item.videoURL];
        [self presentViewController:player animated:YES completion:^{ [player.player play]; }];
    } else {
        BHTPhotoViewerController* viewer = [[BHTPhotoViewerController alloc] initWithItem:item];
        [self.navigationController pushViewController:viewer animated:YES];
    }
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
    if (scrollView != self.collectionView || self.requestedMore || self.mediaItems.count == 0) return;
    CGFloat remaining = scrollView.contentSize.height - CGRectGetMaxY((CGRect){scrollView.contentOffset, scrollView.bounds.size});
    if (remaining > 600) return;
    UIScrollView* nativeScroll = BHTFindScrollableView(self.postsController.view);
    if (nativeScroll.contentSize.height > nativeScroll.bounds.size.height) {
        self.requestedMore = YES;
        CGFloat y = MAX(-nativeScroll.adjustedContentInset.top,
                        nativeScroll.contentSize.height - nativeScroll.bounds.size.height + nativeScroll.adjustedContentInset.bottom);
        [nativeScroll setContentOffset:CGPointMake(nativeScroll.contentOffset.x, y) animated:NO];
    }
}

@end

static UIViewController* BHTTopViewController(void) {
    UIWindow* keyWindow = nil;
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    UIViewController* top = keyWindow.rootViewController ?: UIApplication.sharedApplication.windows.firstObject.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:UINavigationController.class]) {
        top = ((UINavigationController*)top).visibleViewController ?: top;
    }
    if ([top isKindOfClass:UITabBarController.class]) {
        top = ((UITabBarController*)top).selectedViewController ?: top;
    }
    return top;
}

void BHTPresentLikesFromView(UIView* sourceView) {
    if (![BHTSettings boolForKey:@"enable_likes_tab"]) return;
    UIViewController* host = BHTTopViewController();
    if (!host || [host isKindOfClass:BHTLikesViewController.class]) return;

    BHTLikesViewController* likes = [BHTLikesViewController new];
    likes.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                     target:likes
                                                     action:@selector(bht_closeLikes)];
    UINavigationController* navigation =
        [[UINavigationController alloc] initWithRootViewController:likes];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:navigation animated:YES completion:nil];
}

@interface BHTLikesViewController (Presentation)
- (void)bht_closeLikes;
@end

@implementation BHTLikesViewController (Presentation)

- (void)bht_closeLikes {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NSArray* BHTEntriesByInstallingLikesDestination(NSArray* entries) {
    BOOL enabled = [BHTSettings boolForKey:@"enable_likes_tab"];
    NSMutableArray* result = [entries mutableCopy] ?: [NSMutableArray array];

    for (id entry in result) {
        T1TabView* tabView = [entry respondsToSelector:@selector(tabView)] ? [entry tabView] : nil;
        if (!tabView) continue;
        NSString* originalPage = objc_getAssociatedObject(tabView, &kBHTOriginalTabPageKey);
        if (!enabled && [tabView.scribePage isEqualToString:kBHTLikesPage]) {
            tabView.scribePage = originalPage.length ? originalPage : @"grok";
        }
        if (enabled && ([tabView.scribePage isEqualToString:@"grok"] ||
                        [originalPage isEqualToString:@"grok"])) {
            if (originalPage.length == 0) {
                objc_setAssociatedObject(tabView, &kBHTOriginalTabPageKey,
                                         tabView.scribePage ?: @"grok",
                                         OBJC_ASSOCIATION_COPY_NONATOMIC);
            }
            tabView.scribePage = kBHTLikesPage;
        }
    }
    return result;
}

void BHTCaptureLikesSections(UIViewController* dataViewController, NSArray* sections) {
    UIViewController* current = dataViewController;
    while (current && ![current isKindOfClass:BHTLikesViewController.class]) {
        current = current.parentViewController;
    }
    if ([current isKindOfClass:BHTLikesViewController.class]) {
        [(BHTLikesViewController*)current ingestSections:sections];
    }
}
