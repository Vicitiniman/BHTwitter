#import "MediaActions/BHTMediaActionMenuViewController.h"
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import "CustomTabBar/CustomTabBarNativeColors.h"
#import "Headers/TFNHeaders.h"
#import "MediaActions/BHTMediaActionEditorViewController.h"

@interface BHTMediaActionMenuViewController ()
@property(nonatomic, strong, nullable) TFNTwitterAccount* account;
@property(nonatomic, copy) NSArray<NSDictionary*>* mediaKinds;
@end

@implementation BHTMediaActionMenuViewController

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.account = account;
        self.mediaKinds = @[
            @{
                @"kind": @(BHTMediaActionKindPhoto),
                @"titleKey": @"MEDIA_ACTION_PHOTOS_TITLE",
                @"detailKey": @"MEDIA_ACTION_PHOTOS_DETAIL",
                @"image": @"photo"
            },
            @{
                @"kind": @(BHTMediaActionKindVideo),
                @"titleKey": @"MEDIA_ACTION_VIDEOS_TITLE",
                @"detailKey": @"MEDIA_ACTION_VIDEOS_DETAIL",
                @"image": @"video"
            },
            @{
                @"kind": @(BHTMediaActionKindGIF),
                @"titleKey": @"MEDIA_ACTION_GIFS_TITLE",
                @"detailKey": @"MEDIA_ACTION_GIFS_DETAIL",
                @"image": @"photo.on.rectangle.angled"
            }
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSString* title =
        [bundle localizedStringForKey:@"MEDIA_ACTION_MENU_SETTINGS_TITLE"];
    if (self.account && objc_getClass("TFNTitleView")) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView")
                titleViewWithTitle:title
                          subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
    self.tableView.backgroundColor = CustomTabBarScreenBackgroundColor();
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
}

- (NSInteger)tableView:(UITableView*)tableView
 numberOfRowsInSection:(NSInteger)section {
    return self.mediaKinds.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    static NSString* const reuseIdentifier = @"mediaKindCell";
    UITableViewCell* cell =
        [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc]
              initWithStyle:UITableViewCellStyleSubtitle
            reuseIdentifier:reuseIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font =
            [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:16];
        cell.detailTextLabel.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
        cell.detailTextLabel.numberOfLines = 0;
    }

    NSDictionary* mediaKind = self.mediaKinds[indexPath.row];
    BHTBundle* bundle = [BHTBundle sharedBundle];
    cell.textLabel.text =
        [bundle localizedStringForKey:mediaKind[@"titleKey"]];
    cell.detailTextLabel.text =
        [bundle localizedStringForKey:mediaKind[@"detailKey"]];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.backgroundColor = CustomTabBarCardBackgroundColor();
    UIImageSymbolConfiguration* configuration =
        [UIImageSymbolConfiguration
            configurationWithPointSize:19
                                weight:UIImageSymbolWeightRegular];
    cell.imageView.image =
        [[UIImage systemImageNamed:mediaKind[@"image"]
                 withConfiguration:configuration]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.tintColor = CustomTabBarIconColor();
    return cell;
}

- (NSString*)tableView:(UITableView*)tableView
    titleForHeaderInSection:(NSInteger)section {
    return [[BHTBundle sharedBundle]
        localizedStringForKey:@"MEDIA_ACTION_MENU_SETTINGS_DETAIL"];
}

- (void)tableView:(UITableView*)tableView
    didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BHTMediaActionKind kind =
        [self.mediaKinds[indexPath.row][@"kind"] integerValue];
    BHTMediaActionEditorViewController* editor =
        [[BHTMediaActionEditorViewController alloc] initWithKind:kind
                                                         account:self.account];
    [self.navigationController pushViewController:editor animated:YES];
}

@end
