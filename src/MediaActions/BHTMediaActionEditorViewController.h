#import <UIKit/UIKit.h>
#import "MediaActions/BHTMediaActionUtility.h"

@class TFNTwitterAccount;

NS_ASSUME_NONNULL_BEGIN

@interface BHTMediaActionEditorViewController : UIViewController

- (instancetype)initWithKind:(BHTMediaActionKind)kind
                      account:(nullable TFNTwitterAccount*)account;

@end

NS_ASSUME_NONNULL_END
