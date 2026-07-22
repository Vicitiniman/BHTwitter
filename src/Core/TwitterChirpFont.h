//
//  TwitterChirpFont.h
//  NeoFreeBird
//
//  Created by nyaathea
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Headers/TAEHeaders.h"

typedef NS_ENUM(NSInteger, TwitterFontStyle) {
    TwitterFontStyleRegular,
    TwitterFontStyleSemibold,
    TwitterFontStyleBold
};

// Use Twitter's own font group (TFNUIDefaultFontGroup in 12.3) rather than
// fragile variable-font instance names; falls back to system fonts.
static inline UIFont* TwitterChirpFont(TwitterFontStyle style) {
    Class fontGroupClass = objc_getClass("TFNUIDefaultFontGroup");
    if (!fontGroupClass) {
        fontGroupClass = objc_getClass("TAEStandardFontGroup");
    }
    id group = [fontGroupClass sharedFontGroup];

    switch (style) {
        case TwitterFontStyleBold:
            return [group heavyFontOfSize:17]
                       ?: [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        case TwitterFontStyleSemibold:
            return [group boldFontOfSize:14]
                       ?: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        case TwitterFontStyleRegular:
        default:
            return [group fontOfSize:12]
                       ?: [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    }
}
