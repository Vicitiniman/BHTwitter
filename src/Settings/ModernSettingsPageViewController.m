//
//  ModernSettingsPageViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/ModernSettingsPageViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "Settings/ModernSettingsCells.h"
#import "ThemeColor/Palette.h"

@interface ModernSettingsPageViewController ()
@property (nonatomic, copy) NSString* registryPageKey;
@end

@implementation ModernSettingsPageViewController

#pragma mark - Lifecycle

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    return [self initWithAccount:account pageKey:nil];
}

- (instancetype)initWithAccount:(TFNTwitterAccount*)account pageKey:(NSString*)pageKey {
    if ((self = [super init])) {
        self.account = account;
        self.registryPageKey = pageKey;
        [self buildSettingsList];
        [self updateVisibleToggles];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

#pragma mark - Page Registry

- (NSString*)pageKey {
    return self.registryPageKey;
}

- (NSString*)pageTitleKey {
    return [BHTSettings titleKeyForPage:[self pageKey]];
}

- (NSString*)pageSubtitleKey {
    return [BHTSettings subtitleKeyForPage:[self pageKey]];
}

- (void)buildSettingsList {
    self.toggles = [BHTSettings settingsForPage:[self pageKey]];
}

#pragma mark - Setup

- (void)setupNav {
    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:[self pageTitleKey]];
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
    [self.tableView registerClass:[ModernSettingsToggleCell class]
           forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[ModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[ModernSettingsCompactButtonCell class]
           forCellReuseIdentifier:@"CompactButtonCell"];
    [self.view addSubview:self.tableView];
}

#pragma mark - Visible Toggles

- (void)updateVisibleToggles {
    NSMutableArray* visible = [NSMutableArray array];
    for (NSDictionary* toggleData in self.toggles) {
        NSString* parentKey = toggleData[@"parentKey"];
        if (parentKey) {
            BOOL parentEnabled = [BHTSettings boolForKey:parentKey];
            if (parentEnabled) {
                [visible addObject:toggleData];
            }
        } else {
            [visible addObject:toggleData];
        }
    }
    self.visibleToggles = [visible copy];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleToggles.count;
}

// Title key defaults to KEY_TITLE; an explicit titleKey takes precedence.
- (NSString*)localizedTitleForEntry:(NSDictionary*)entry {
    NSString* titleKey = entry[@"titleKey"];
    if (!titleKey) {
        titleKey = [NSString stringWithFormat:@"%@_TITLE", [entry[@"key"] uppercaseString]];
    }
    return [[BHTBundle sharedBundle] localizedStringForKey:titleKey];
}

// The bundle returns the key itself when no string exists, which counts as no detail.
- (NSString*)localizedDetailForKey:(NSString*)key {
    NSString* detailKey = [NSString stringWithFormat:@"%@_DETAIL", [key uppercaseString]];
    NSString* detail = [[BHTBundle sharedBundle] localizedStringForKey:detailKey];
    return [detail isEqualToString:detailKey] ? @"" : detail;
}

// Localized at render time; the registry can't call localizedStringForKey
// without re-entering the settings lookup.
- (NSString*)defaultSubtitleForEntry:(NSDictionary*)entry {
    NSString* subtitleDefaultKey = entry[@"subtitleDefaultKey"];
    if (subtitleDefaultKey) {
        return [[BHTBundle sharedBundle] localizedStringForKey:subtitleDefaultKey];
    }
    return entry[@"subtitleDefault"];
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* toggleData = self.visibleToggles[indexPath.row];
    NSString* type = toggleData[@"type"];
    if ([type isEqualToString:@"compactButton"]) {
        ModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 &&
                ![subtitle isEqualToString:defaultSubtitle]) {
                subtitle = @"••••••••••••••••";
            }
        }
        [cell configureWithTitle:title subtitle:subtitle];
        return cell;
    } else if ([type isEqualToString:@"button"]) {
        ModernSettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ButtonCell"
                                                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 &&
                ![subtitle isEqualToString:defaultSubtitle]) {
                subtitle = @"••••••••••••••••";
            }
        }
        NSString* iconName = toggleData[@"icon"];
        [cell configureWithTitle:title subtitle:subtitle iconName:iconName];
        return cell;
    } else {
        ModernSettingsToggleCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell"
                                                                         forIndexPath:indexPath];
        NSString* key = toggleData[@"key"];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = [self localizedDetailForKey:key];
        [cell configureWithTitle:title subtitle:subtitle];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key]
                              ?: toggleData[@"default"] boolValue];
        cell.toggleSwitch.on = isEnabled;
        objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell addTarget:self
                      action:@selector(switchChanged:)
            forControlEvents:UIControlEventValueChanged];
        return cell;
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary* data = self.visibleToggles[indexPath.row];
    if ([data[@"type"] isEqualToString:@"button"] ||
        [data[@"type"] isEqualToString:@"compactButton"]) {
        NSString* actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action
                           withObject:data];
#pragma clang diagnostic pop
            }
        }
    }
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:[self pageSubtitleKey]];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor* subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor
                                            constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor
                                             constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor
                                        constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor
                                           constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

#pragma mark - Switch Handling

- (void)switchChanged:(UISwitch*)sender {
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
        [self updateAndAnimateChangesForKey:key];
    }
}

- (void)updateAndAnimateChangesForKey:(NSString*)key {
    NSArray* oldVisibleToggles = self.visibleToggles;
    [self updateVisibleToggles];
    NSArray* newVisibleToggles = self.visibleToggles;
    [self.tableView beginUpdates];
    __block NSInteger toggleIndex = -1;
    [oldVisibleToggles enumerateObjectsUsingBlock:^(NSDictionary* _Nonnull obj, NSUInteger idx,
                                                    BOOL* _Nonnull stop) {
        if ([obj[@"key"] isEqualToString:key]) {
            toggleIndex = idx;
            *stop = YES;
        }
    }];
    if (toggleIndex == -1) {
        [self.tableView endUpdates];
        [self.tableView reloadData];
        return;
    }
    NSMutableArray* children = [NSMutableArray array];
    for (NSDictionary* toggleData in self.toggles) {
        if ([toggleData[@"parentKey"] isEqualToString:key]) {
            [children addObject:toggleData];
        }
    }
    if (children.count == 0) {
        [self.tableView endUpdates];
        return;
    }
    BOOL isAdding = newVisibleToggles.count > oldVisibleToggles.count;
    // Children are registered directly after their parent, so their rows are contiguous below it.
    NSMutableArray* indexPaths = [NSMutableArray array];
    for (int i = 0; i < children.count; i++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:toggleIndex + 1 + i inSection:0]];
    }
    if (isAdding) {
        [self.tableView insertRowsAtIndexPaths:indexPaths
                              withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [self.tableView deleteRowsAtIndexPaths:indexPaths
                              withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [self.tableView endUpdates];
}

@end
