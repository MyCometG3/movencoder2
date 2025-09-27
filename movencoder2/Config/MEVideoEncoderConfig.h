//
//  MEVideoEncoderConfig.h
//  movencoder2
//
//  Type-safe view over legacy videoEncoderSetting dictionary.
//
//  This file is part of movencoder2 (GPLv2 or later).
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import "METypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface MEVideoEncoderConfig : NSObject

@property (nonatomic, copy, readonly) NSArray<NSString*> *issues; // collected soft validation messages
@property (nonatomic, copy, readonly) NSString *rawCodecName;
@property (nonatomic, assign, readonly) MEVideoCodecKind codecKind;
@property (nonatomic, assign, readonly) CMTime frameRate;          // invalid if not provided
@property (nonatomic, assign, readonly) BOOL hasFrameRate;
@property (nonatomic, assign, readonly) NSInteger bitRate;         // 0 if not provided
@property (nonatomic, assign, readonly) CGSize declaredSize;       // {0,0} if not provided
@property (nonatomic, assign, readonly) BOOL hasDeclaredSize;
@property (nonatomic, assign, readonly) CGSize pixelAspect;        // {0,0} if not provided
@property (nonatomic, assign, readonly) BOOL hasPixelAspect;
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString*,NSString*> *codecOptions;
@property (nonatomic, copy, readonly, nullable) NSString *x264Params;
@property (nonatomic, copy, readonly, nullable) NSString *x265Params;
@property (nonatomic, strong, readonly, nullable) NSValue *cleanAperture; // Keep raw NSValue (NSRect)

+ (instancetype)configFromLegacyDictionary:(NSDictionary*)dict error:(NSError* _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
