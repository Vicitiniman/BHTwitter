//
//  Palette.h
//  NeoFreeBird
//
//  Created by nyaathea
//

#import <UIKit/UIKit.h>

@interface Palette : NSObject

/**
 * Twitter's current app background color, read straight from the active
 * TAEColorPalette so it always matches the app chrome.
 */
+ (UIColor*)currentBackgroundColor;

@end
