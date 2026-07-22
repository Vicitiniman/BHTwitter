//
//  WebSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/WebSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"

@implementation WebSettingsViewController

- (NSString*)pageKey {
    return @"web";
}

// Mirrors the base implementation, but includes the indexPath in the payload so
// the row can be reloaded after saving.
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary* data = self.visibleToggles[indexPath.row];

    if ([data[@"type"] isEqualToString:@"button"] ||
        [data[@"type"] isEqualToString:@"compactButton"]) {
        NSString* actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
                NSMutableDictionary* payload = [data mutableCopy];
                payload[@"indexPath"] = indexPath;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action
                           withObject:payload];
#pragma clang diagnostic pop
            }
        }
    }
}

// Reduces user input like "https://fxtwitter.com/" to a bare host, so the
// value can be assigned straight to NSURLComponents.host when rewriting.
- (NSString*)sharingDomainFromInput:(NSString*)input {
    NSString* domain =
        [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSRange schemeRange = [domain rangeOfString:@"://"];
    if (schemeRange.location != NSNotFound) {
        domain = [domain substringFromIndex:NSMaxRange(schemeRange)];
    }

    NSRange pathRange = [domain rangeOfString:@"/"];
    if (pathRange.location != NSNotFound) {
        domain = [domain substringToIndex:pathRange.location];
    }

    return domain;
}

- (void)showSharingDomainPrompt:(NSDictionary*)data {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* currentHost = [defaults objectForKey:@"sharing_domain"];

    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle]
                                                        localizedStringForKey:@"SHARING_DOMAIN_TITLE"]
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
        textField.text = currentHost;
        textField.placeholder = @"x.com";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [alert
        addAction:[UIAlertAction
                      actionWithTitle:[[BHTBundle sharedBundle]
                                          localizedTwitterStringForKey:@"SAVE_ACTION_LABEL"]
                                style:UIAlertActionStyleDefault
                              handler:^(UIAlertAction* action) {
                                  NSString* domain =
                                      [self sharingDomainFromInput:alert.textFields.firstObject.text];

                                  if (domain.length > 0) {
                                      [defaults setObject:domain forKey:@"sharing_domain"];
                                  } else {
                                      [defaults removeObjectForKey:@"sharing_domain"];
                                  }
                                  [defaults synchronize];

                                  NSIndexPath* indexPath = data[@"indexPath"];
                                  if (indexPath) {
                                      [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                                            withRowAnimation:UITableViewRowAnimationNone];
                                  }
                              }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
