//
//  TFSHeaders.h
//  BHTwitter
//
//  Created by BandarHelal
//

#import <Foundation/Foundation.h>

@interface TFSTwitterEntityMediaVideoVariant : NSObject
@property (readonly, copy, nonatomic) NSString* contentType;
@property (readonly, copy, nonatomic) NSString* url;
@end

@interface TFSTwitterEntityMediaVideoInfo : NSObject
@property (readonly, copy, nonatomic) NSArray* variants;
@property (readonly, copy, nonatomic) NSString* primaryUrl;
@end

@interface TFSTwitterEntityMedia : NSObject
@property (readonly, nonatomic) TFSTwitterEntityMediaVideoInfo* videoInfo;
@property (readonly, copy, nonatomic) NSString* mediaURL;
@property (nonatomic, assign, readonly)
    NSInteger mediaType; // 1 = photo, 2 = GIF, 3 = video
@end

@interface TFSTwitterMediaInfo : NSObject
@property (readonly, nonatomic) TFSTwitterEntityMedia* mediaEntity;
@property (readonly, nonatomic) TFSTwitterEntityMediaVideoInfo* videoInfo;
@end

@interface TFSTwitterEntitySet : NSObject
@property (readonly, copy, nonatomic) NSArray* media;
@end

@interface TFSTwitterEntityURL : NSObject
@property (readonly, copy, nonatomic) NSString* expandedURL;
@end

@interface TFSTwitterSspMetadata : NSObject
- (BOOL)isPrerollEligible;
- (id)adTagURL;
@end

// Relationship states are 1 = yes, 2 = no.
@interface TFSTwitterRelationship : NSObject
@property (readonly, nonatomic) NSInteger superFollowingState;
@end

@interface NSNumber (TFSTwitter)
- (NSString*)tfs_twitterAbbreviated;
@end
