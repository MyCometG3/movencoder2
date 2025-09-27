//
//  METypes.h
//  movencoder2
//
//  Introduced for type-safe configuration layering.
//
//  This file is part of movencoder2 (GPLv2 or later).
//

#ifndef METypes_h
#define METypes_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MEVideoCodecKind) {
    MEVideoCodecKindX264 = 0,
    MEVideoCodecKindX265 = 1,
    MEVideoCodecKindOther = 100
};

static inline MEVideoCodecKind MEVideoCodecKindFromName(NSString *name) {
    if ([name isEqualToString:@"libx264"]) return MEVideoCodecKindX264;
    if ([name isEqualToString:@"libx265"]) return MEVideoCodecKindX265;
    return MEVideoCodecKindOther;
}

NS_ASSUME_NONNULL_END

#endif /* METypes_h */
