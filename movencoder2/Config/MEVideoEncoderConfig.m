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
        cfg.issues = @[@"Legacy dictionary missing or invalid."];
        return cfg; // empty
    }
    NSMutableArray<NSString*> *issues = [NSMutableArray array];
    @autoreleasepool {
        NSString *codec = dict[kMEVECodecNameKey];
        if ([codec isKindOfClass:[NSString class]] && codec.length) {
            cfg.rawCodecName = codec;
            cfg.codecKind = MEVideoCodecKindFromName(codec);
        } else {
            [issues addObject:@"codecName is missing or empty."];
            cfg.rawCodecName = @""; // preserve legacy possibility of missing name
            cfg.codecKind = MEVideoCodecKindOther;
        }
        NSValue *fpsValue = dict[kMEVECodecFrameRateKey];
        if ([fpsValue isKindOfClass:[NSValue class]]) {
            CMTime t = [fpsValue CMTimeValue];
            if (CMTIME_IS_VALID(t) && t.value>0 && t.timescale>0) {
                cfg.frameRate = t;
                cfg.hasFrameRate = YES;
            } else {
                [issues addObject:@"codecFrameRate is invalid CMTime."];
            }
        }
        id bitRateRaw = dict[kMEVECodecBitRateKey];
        if ([bitRateRaw isKindOfClass:[NSNumber class]]) {
            cfg.bitRate = [bitRateRaw integerValue];
        } else if ([bitRateRaw isKindOfClass:[NSString class]]) {
            NSString *s = (NSString*)bitRateRaw;
            // Accept forms like 2500000, 2.5M, 5M, 800k, 192K (case-insensitive)
            NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
            s = [[s stringByTrimmingCharactersInSet:ws] lowercaseString];
            double multiplier = 1.0;
            if ([s hasSuffix:@"m"]) { multiplier = 1000000.0; s = [s substringToIndex:s.length-1]; }
            else if ([s hasSuffix:@"k"]) { multiplier = 1000.0; s = [s substringToIndex:s.length-1]; }
            double val = [s doubleValue];
            if (val > 0.0) {
                double bits = val * multiplier;
                if (bits > 0 && bits < (double)NSIntegerMax) {
                    cfg.bitRate = (NSInteger)llround(bits);
                } else {
                    [issues addObject:@"codecBitRate numeric overflow or invalid magnitude."];
                }
            } else {
                [issues addObject:@"codecBitRate string could not be parsed."];
            }
        }
        NSValue *sizeVal = dict[kMEVECodecWxHKey];
        if ([sizeVal isKindOfClass:[NSValue class]]) {
            CGSize s = [sizeVal sizeValue];
            if (s.width>0 && s.height>0) {
                cfg.declaredSize = s; cfg.hasDeclaredSize = YES;
            } else {
                [issues addObject:@"codecWxH has non-positive dimension."];
            }
        }
        NSValue *parVal = dict[kMEVECodecPARKey];
        if ([parVal isKindOfClass:[NSValue class]]) {
            CGSize p = [parVal sizeValue];
            if (p.width>0 && p.height>0) {
                cfg.pixelAspect = p; cfg.hasPixelAspect = YES;
            } else {
                [issues addObject:@"codecPAR has non-positive values."];
            }
        }
        if (cfg.bitRate == 0 && dict[kMEVECodecBitRateKey]) {
            [issues addObject:@"codecBitRate resolved to 0 (check input)."];
        }

        cfg.issues = issues.count ? [[NSOrderedSet orderedSetWithArray:issues] array] : @[];

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
