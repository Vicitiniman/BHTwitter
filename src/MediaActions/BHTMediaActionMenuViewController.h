#import <UIKit/UIKit.h>

@class TFNTwitterAccount;

NS_ASSUME_NONNULL_BEGIN

@interface BHTMediaActionMenuViewController : UITableViewController

- (instancetype)initWithAccount:(nullable TFNTwitterAccount*)account;

@end

NS_ASSUME_NONNULL_END
