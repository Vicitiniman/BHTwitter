#import "Settings/Pages/MediaDownloadsSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "MediaActions/BHTMediaActionMenuViewController.h"
#import "Settings/ModernSettingsCells.h"

@implementation MediaDownloadsSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:ModernSettingsSimpleButtonCell.class
           forCellReuseIdentifier:@"MediaSimpleButtonCell"];
}

- (NSString*)pageKey {
    return @"media_downloads";
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* setting = self.visibleToggles[indexPath.row];
    if ([setting[@"type"] isEqualToString:@"button"]) {
        ModernSettingsSimpleButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:
                           @"MediaSimpleButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [[BHTBundle sharedBundle]
            localizedStringForKey:setting[@"titleKey"]];
        [cell configureWithTitle:title];
        return cell;
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

- (void)showMediaActionMenus:(__unused NSDictionary*)sender {
    BHTMediaActionMenuViewController* menu =
        [[BHTMediaActionMenuViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:menu animated:YES];
}

@end
