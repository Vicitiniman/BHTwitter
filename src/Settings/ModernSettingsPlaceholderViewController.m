//
//  ModernSettingsPlaceholderViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/ModernSettingsPlaceholderViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/Palette.h"

@implementation ModernSettingsPlaceholderViewController

- (instancetype)initWithAccount:(TFNTwitterAccount*)account titleKey:(NSString*)titleKey {
    if ((self = [super init])) {
        self.account = account;
        self.navigationTitleKey = [titleKey copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString* titleKey =
        self.navigationTitleKey.length > 0 ? self.navigationTitleKey : @"NFB_SETTINGS_TITLE";

    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:titleKey];

    if (self.account) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                     subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [Palette currentBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;

    [self.view addSubview:self.tableView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return 0;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

#pragma mark - UITableViewDelegate

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];

    UILabel* titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.numberOfLines = 0;
    titleLabel.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PLACEHOLDER_TEXT"];

    UILabel* detailLabel = [[UILabel alloc] init];
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    detailLabel.numberOfLines = 0;
    detailLabel.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PLACEHOLDER_DETAIL_TEXT"];

    id fontGroup = [BHTManager sharedFontGroup];
    if (fontGroup) {
        if ([fontGroup respondsToSelector:@selector(bodyBoldFont)]) {
            titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
        }
        if ([fontGroup respondsToSelector:@selector(subtext2Font)]) {
            detailLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
        }
    }

    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor* titleColor = [colorPalette performSelector:@selector(textColor)];
    UIColor* subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];

    titleLabel.textColor = titleColor;
    detailLabel.textColor = subtitleColor;

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, detailLabel]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 4.0;

    [header addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor
                                            constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor
                                             constant:-20],
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor
                                        constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor
                                           constant:-16]
    ]];

    return header;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

@end
