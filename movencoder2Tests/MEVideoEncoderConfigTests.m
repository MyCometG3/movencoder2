//  MEVideoEncoderConfigTests.m
//  movencoder2Tests
//
//  Basic unit tests for MEVideoEncoderConfig parsing & normalization.
//
//  NOTE: These tests focus on pure dictionary -> config transformation logic.
//
#import <XCTest/XCTest.h>
#import "MEVideoEncoderConfig.h"
#import "MEManager.h"

@interface MEVideoEncoderConfigTests : XCTestCase
@end

@implementation MEVideoEncoderConfigTests

- (void)testBitRateNumeric { // plain number via NSNumber
    NSDictionary *d = @{ kMEVECodecBitRateKey : @(2500000), kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertEqual(cfg.bitRate, 2500000);
    XCTAssertEqual(cfg.issues.count, 0);
}

- (void)testBitRateWithKSuffixLower { // 800k
    NSDictionary *d = @{ kMEVECodecBitRateKey : @"800k", kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertEqual(cfg.bitRate, 800000);
    XCTAssertEqual(cfg.issues.count, 0);
}

- (void)testBitRateWithMSuffixDecimal { // 2.5M => 2500000
    NSDictionary *d = @{ kMEVECodecBitRateKey : @"2.5M", kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertEqual(cfg.bitRate, 2500000);
    XCTAssertEqual(cfg.issues.count, 0);
}

- (void)testBitRateInvalidStringGeneratesIssues { // "abc" -> parse fail + zero warning
    NSDictionary *d = @{ kMEVECodecBitRateKey : @"abc", kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertEqual(cfg.bitRate, 0);
    // Expect 2 distinct issues: parse failure + resolved to 0
    XCTAssertEqual(cfg.issues.count, 2);
    XCTAssertTrue([cfg.issues[0] containsString:@"codecBitRate"]);
}

- (void)testBitRateZeroStringGeneratesZeroIssue { // "0" -> parse fail + zero warning
    NSDictionary *d = @{ kMEVECodecBitRateKey : @"0", kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertEqual(cfg.bitRate, 0);
    XCTAssertEqual(cfg.issues.count, 2);
}

- (void)testFrameRateValid { // 30000/1001
    CMTime fr = CMTimeMake(30000, 1001);
    NSDictionary *d = @{ kMEVECodecFrameRateKey : [NSValue valueWithCMTime:fr], kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertTrue(cfg.hasFrameRate);
    XCTAssertEqual(cfg.frameRate.value, fr.value);
    XCTAssertEqual(cfg.frameRate.timescale, fr.timescale);
}

- (void)testDeclaredSizeAndPAR { // WxH + PAR
    CGSize sz = CGSizeMake(1920, 1080);
    CGSize par = CGSizeMake(1, 1);
    NSDictionary *d = @{ kMEVECodecWxHKey : [NSValue valueWithSize:sz],
                         kMEVECodecPARKey : [NSValue valueWithSize:par],
                         kMEVECodecNameKey: @"libx265" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertTrue(cfg.hasDeclaredSize);
    XCTAssertEqual(cfg.declaredSize.width, sz.width);
    XCTAssertEqual(cfg.declaredSize.height, sz.height);
    XCTAssertTrue(cfg.hasPixelAspect);
    XCTAssertEqual(cfg.pixelAspect.width, par.width);
    XCTAssertEqual(cfg.pixelAspect.height, par.height);
}

- (void)testX264ParamsTrimming { // leading/trailing colons & whitespace trimmed
    NSDictionary *d = @{ kMEVEx264_paramsKey : @"  :preset=slow:profile=main:  ", kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertEqualObjects(cfg.x264Params, @"preset=slow:profile=main");
    XCTAssertEqual(cfg.issues.count, 0);
}

- (void)testEmptyX265ParamsIssue { // becomes issue after trimming
    NSDictionary *d = @{ kMEVEx265_paramsKey : @"   ", kMEVECodecNameKey: @"libx265" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertNil(cfg.x265Params);
    XCTAssertEqual(cfg.issues.count, 1);
    XCTAssertTrue([cfg.issues[0] containsString:@"x265_params"]);
}

- (void)testEmptyX264ParamsIssue { // x264 empty -> issue
    NSDictionary *d = @{ kMEVEx264_paramsKey : @"   ", kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertNil(cfg.x264Params);
    XCTAssertEqual(cfg.issues.count, 1);
    XCTAssertTrue([[cfg.issues firstObject] containsString:@"x264_params"]);
}

- (void)testDuplicateIssueDeduplication { // two different issues accepted
    NSDictionary *d = @{ kMEVEx264_paramsKey : @"   : ",
                          kMEVEx265_paramsKey : @"  :  ",
                          kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    // Expect 2 distinct issues (x264 empty, x265 empty)
    XCTAssertEqual(cfg.issues.count, 2);
}

- (void)testBitRateOverflowIssue { // extremely large value triggers overflow issue
    NSDictionary *d = @{ kMEVECodecBitRateKey : @"9999999999999M", kMEVECodecNameKey: @"libx264" };
    MEVideoEncoderConfig *cfg = [MEVideoEncoderConfig configFromLegacyDictionary:d error:NULL];
    XCTAssertEqual(cfg.bitRate, 0); // overflow prevents assignment
    BOOL hasOverflow = NO;
    for (NSString *issue in cfg.issues) {
        if ([issue containsString:@"overflow"]) { hasOverflow = YES; break; }
    }
    XCTAssertTrue(hasOverflow);
}

@end
