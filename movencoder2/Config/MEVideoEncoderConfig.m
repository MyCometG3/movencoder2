//
//  MEVideoEncoderConfig.m
//  movencoder2
//
//  Lightweight adapter without changing existing behavior.
//  TS-3: Collect simple validation issues for verbose logging.
//
//  This file is part of movencoder2 (GPLv2 or later).
//

#import "MEVideoEncoderConfig.h"
#import "MEManager.h" // for legacy keys

@interface MEVideoEncoderConfig ()
@property (nonatomic, copy, readwrite) NSString *rawCodecName;
@property (nonatomic, assign, readwrite) MEVideoCodecKind codecKind;
@property (nonatomic, assign, readwrite) CMTime frameRate;
@property (nonatomic, assign, readwrite) BOOL hasFrameRate;
@property (nonatomic, assign, readwrite) NSInteger bitRate;
@property (nonatomic, assign, readwrite) CGSize declaredSize;
@property (nonatomic, assign, readwrite) BOOL hasDeclaredSize;
@property (nonatomic, assign, readwrite) CGSize pixelAspect;
@property (nonatomic, assign, readwrite) BOOL hasPixelAspect;
@property (nonatomic, copy, readwrite, nullable) NSDictionary<NSString*,NSString*> *codecOptions;
@property (nonatomic, copy, readwrite, nullable) NSString *x264Params;
@property (nonatomic, copy, readwrite, nullable) NSString *x265Params;
@property (nonatomic, strong, readwrite, nullable) NSValue *cleanAperture;
@property (nonatomic, copy, readwrite) NSArray<NSString*> *issues;
@end

@implementation MEVideoEncoderConfig

+ (instancetype)configFromLegacyDictionary:(NSDictionary*)dict error:(NSError* _Nullable * _Nullable)error {
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig new];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        cfg.issues = @["Legacy dictionary missing or invalid."];
        return cfg; // empty
    }
    NSMutableArray<NSString*> *issues = [NSMutableArray array];
    @autoreleasepool {
        NSString *codec = dict[kMEVECodecNameKey];
        if ([codec isKindOfClass:[NSString class]] && codec.length) {
            cfg.rawCodecName = codec;
            cfg.codecKind = MEVideoCodecKindFromName(codec);
        } else {
        else {
            [issues addObject:@"codecName is missing or empty."];
        }

            cfg.rawCodecName = @""; // preserve legacy possibility of missing name
            cfg.codecKind = MEVideoCodecKindOther;
        }
        NSValue *fpsValue = dict[kMEVECodecFrameRateKey];
        else if (fpsValue && !cfg.hasFrameRate) {
            [issues addObject:@"codecFrameRate is invalid CMTime."];
        }

        if ([fpsValue isKindOfClass:[NSValue class]]) {
            CMTime t = [fpsValue CMTimeValue];
            if (CMTIME_IS_VALID(t) && t.value>0 && t.timescale>0) {
        else if (sizeVal) {
            [issues addObject:@"codecWxH has non-positive dimension."];
        }

                cfg.frameRate = t;
                cfg.hasFrameRate = YES;
        else if (parVal) {
            [issues addObject:@"codecPAR has non-positive values."];
        }

            }
        }
        NSNumber *bitRateNum = dict[kMEVECodecBitRateKey];
        if ([bitRateNum isKindOfClass:[NSNumber class]]) {
            cfg.bitRate = [bitRateNum integerValue];
        }
        NSValue *sizeVal = dict[kMEVECodecWxHKey];
        if ([sizeVal isKindOfClass:[NSValue class]]) {
            CGSize s = [sizeVal sizeValue];
            if (s.width>0 && s.height>0) { cfg.declaredSize = s; cfg.hasDeclaredSize = YES; }
        }
        NSValue *parVal = dict[kMEVECodecPARKey];
        if ([parVal isKindOfClass:[NSValue class]]) {
            CGSize p = [parVal sizeValue];
            if (p.width>0 && p.height>0) { cfg.pixelAspect = p; cfg.hasPixelAspect = YES; }
    cfg.issues = issues.count ? [issues copy] : @[];

        }
        NSDictionary *opts = dict[kMEVECodecOptionsKey];
        if ([opts isKindOfClass:[NSDictionary class]] && opts.count) {
            // Filter only string->string
            NSMutableDictionary *filtered = [NSMutableDictionary dictionaryWithCapacity:opts.count];
            [opts enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSString class]]) {
                    filtered[key] = obj;
                }
            }];
            if (filtered.count) cfg.codecOptions = [filtered copy];
        }
        NSString *x264 = dict[kMEVEx264_paramsKey];
        if ([x264 isKindOfClass:[NSString class]] && x264.length) cfg.x264Params = x264;
        NSString *x265 = dict[kMEVEx265_paramsKey];
        if ([x265 isKindOfClass:[NSString class]] && x265.length) cfg.x265Params = x265;
        NSValue *clean = dict[kMEVECleanApertureKey];
        if ([clean isKindOfClass:[NSValue class]]) cfg.cleanAperture = clean;
    }
    return cfg;
}

@end
