//
//  DownloadInlineButton.h
//  NeoFreeBird
//
//  Original author: BandarHelal at 09/04/2022
//  Modified by: actuallyaridan at 27/04/2025
//

@import UIKit;
#import "Core/BHTManager.h"

NS_ASSUME_NONNULL_BEGIN

// Presents the download quality/options sheet for a tweet's media. Formerly an
// inline action-bar button; now driven from the tweet overflow (3-dot) menu.
@interface DownloadInlineButton : NSObject

- (void)presentDownloadOptionsForMediaEntities:(NSArray*)mediaEntities;

// Downloads the highest-quality representation to a temporary file and opens
// Apple's share sheet. This never writes to the Photos library on its own.
- (void)shareHighestQualityMediaEntities:(NSArray*)mediaEntities;

// Photo counterparts used by X's native media action sheet. Download writes
// the original-quality image to Photos; Share only exposes a temporary file.
- (void)downloadOriginalPhotoMediaEntities:(NSArray*)mediaEntities;
- (void)shareOriginalPhotoMediaEntities:(NSArray*)mediaEntities;

@end

NS_ASSUME_NONNULL_END
