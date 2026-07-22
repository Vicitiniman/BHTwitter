//
//  ModernSettingsPlaceholderViewController.h
//  NeoFreeBird
//
//  Created by nyaathea
//

#import <UIKit/UIKit.h>

@class TFNTwitterAccount;

@interface ModernSettingsPlaceholderViewController
    : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, copy) NSString* navigationTitleKey;
- (instancetype)initWithAccount:(TFNTwitterAccount*)account titleKey:(NSString*)titleKey;
@end
