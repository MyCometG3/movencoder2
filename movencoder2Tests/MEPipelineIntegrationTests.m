//
//  MEPipelineIntegrationTests.m
//  movencoder2Tests
//
//  Created by Copilot on 2025-09-29.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

@import XCTest;
@import Foundation;
@import CoreMedia;

#include <libavcodec/avcodec.h>

#import "MEFilterPipeline.h"
#import "MEEncoderPipeline.h" 
#import "MEManager.h"
#import "MESampleBufferFactory.h"

#ifndef AV_LOG_DEBUG
#define AV_LOG_DEBUG 48
#endif

static BOOL MEGetNotSyncForPacketBytes(const uint8_t *bytes,
                                       size_t length,
                                       enum AVCodecID codecId,
                                       CMVideoCodecType codecType,
                                       int flags,
                                       BOOL *outNotSync)
{
    if (!bytes || length == 0 || !outNotSync) {
        return NO;
    }
    
    MESampleBufferFactory *factory = [[MESampleBufferFactory alloc] init];
    factory.timeBase = 30000;
    NSString *codecName = (codecId == AV_CODEC_ID_HEVC) ? @"libx265" : @"libx264";
    factory.videoEncoderSetting = [@{kMEVECodecNameKey: codecName} mutableCopy];
    
    CMVideoFormatDescriptionRef desc = NULL;
    OSStatus err = CMVideoFormatDescriptionCreate(kCFAllocatorDefault,
                                                  codecType,
                                                  16,
                                                  16,
                                                  NULL,
                                                  &desc);
    if (err != noErr || !desc) {
        if (desc) CFRelease(desc);
        return NO;
    }
    factory.formatDescription = desc;
    CFRelease(desc);
    
    AVCodecContext *avctx = avcodec_alloc_context3(NULL);
    if (!avctx) {
        return NO;
    }
    avctx->codec_id = codecId;
    
    AVPacket packet = {0};
    packet.data = av_malloc((int)length);
    if (!packet.data) {
        avcodec_free_context(&avctx);
        return NO;
    }
    memcpy(packet.data, bytes, length);
    packet.size = (int)length;
    packet.flags = flags;
    
    CMSampleBufferRef sb = [factory createCompressedSampleBufferFromPacket:&packet
                                                              codecContext:avctx
                                                        videoEncoderConfig:nil];
    av_free(packet.data);
    avcodec_free_context(&avctx);
    if (!sb) {
        return NO;
    }
    
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sb, false);
    if (!attachments || CFArrayGetCount(attachments) == 0) {
        CFRelease(sb);
        return NO;
    }
    CFDictionaryRef dict = CFArrayGetValueAtIndex(attachments, 0);
    CFBooleanRef value = dict ? CFDictionaryGetValue(dict, kCMSampleAttachmentKey_NotSync) : NULL;
    if (!value) {
        CFRelease(sb);
        return NO;
    }
    
    *outNotSync = CFBooleanGetValue(value);
    CFRelease(sb);
    return YES;
}

@interface MEPipelineIntegrationTests : XCTestCase
@property (strong, nonatomic) MEFilterPipeline *filterPipeline;
@property (strong, nonatomic) MEEncoderPipeline *encoderPipeline;
@property (strong, nonatomic) MESampleBufferFactory *sampleBufferFactory;
@end

@implementation MEPipelineIntegrationTests

- (void)setUp {
    [super setUp];
    self.filterPipeline = [[MEFilterPipeline alloc] init];
    self.encoderPipeline = [[MEEncoderPipeline alloc] init];
    self.sampleBufferFactory = [[MESampleBufferFactory alloc] init];
}

- (void)tearDown {
    [self.filterPipeline cleanup];
    [self.encoderPipeline cleanup];  
    [self.sampleBufferFactory cleanup];
    
    self.filterPipeline = nil;
    self.encoderPipeline = nil;
    self.sampleBufferFactory = nil;
    
    [super tearDown];
}

- (void)testPipelineComponentInitialization {
    // Test that pipeline components are properly initialized
    XCTAssertNotNil(self.filterPipeline);
    XCTAssertNotNil(self.encoderPipeline);
    XCTAssertNotNil(self.sampleBufferFactory);
    
    // Test initial states
    XCTAssertFalse(self.filterPipeline.isReady);
    XCTAssertFalse(self.filterPipeline.isEOF);
    XCTAssertFalse(self.filterPipeline.hasValidFilteredFrame);
    
    XCTAssertFalse(self.encoderPipeline.isReady);
    XCTAssertFalse(self.encoderPipeline.isEOF);
    XCTAssertFalse(self.encoderPipeline.isFlushed);
}

- (void)testPipelineComponentProperties {
    // Test property setting and synchronization
    self.filterPipeline.verbose = YES;
    self.filterPipeline.logLevel = AV_LOG_DEBUG;
    self.filterPipeline.timeBase = 30000;
    self.filterPipeline.filterString = @"scale=640:480";
    
    XCTAssertTrue(self.filterPipeline.verbose);
    XCTAssertEqual(self.filterPipeline.logLevel, AV_LOG_DEBUG);
    XCTAssertEqual(self.filterPipeline.timeBase, 30000);
    XCTAssertEqualObjects(self.filterPipeline.filterString, @"scale=640:480");
    
    // Test encoder pipeline properties
    NSMutableDictionary *encoderSettings = [@{kMEVECodecNameKey: @"libx264"} mutableCopy];
    self.encoderPipeline.videoEncoderSetting = encoderSettings;
    self.encoderPipeline.verbose = YES;
    self.encoderPipeline.logLevel = AV_LOG_DEBUG;
    self.encoderPipeline.timeBase = 30000;
    
    XCTAssertEqualObjects(self.encoderPipeline.videoEncoderSetting, encoderSettings);
    XCTAssertTrue(self.encoderPipeline.verbose);
    XCTAssertEqual(self.encoderPipeline.logLevel, AV_LOG_DEBUG);
    XCTAssertEqual(self.encoderPipeline.timeBase, 30000);
    
    // Test sample buffer factory properties
    self.sampleBufferFactory.verbose = YES;
    self.sampleBufferFactory.timeBase = 30000;
    self.sampleBufferFactory.videoEncoderSetting = encoderSettings;
    
    XCTAssertTrue(self.sampleBufferFactory.verbose);
    XCTAssertEqual(self.sampleBufferFactory.timeBase, 30000);
    XCTAssertEqualObjects(self.sampleBufferFactory.videoEncoderSetting, encoderSettings);
}

- (void)testPipelineComponentCleanup {
    // Test cleanup functionality
    self.filterPipeline.filterString = @"scale=640:480";
    self.encoderPipeline.videoEncoderSetting = [@{kMEVECodecNameKey: @"libx264"} mutableCopy];
    
    [self.filterPipeline cleanup];
    [self.encoderPipeline cleanup];
    [self.sampleBufferFactory cleanup];
    
    // After cleanup, components should be in initial state
    XCTAssertFalse(self.filterPipeline.isReady);
    XCTAssertFalse(self.filterPipeline.isEOF);
    XCTAssertFalse(self.encoderPipeline.isReady);
    XCTAssertFalse(self.encoderPipeline.isEOF);
}

- (void)testUtilityMethods {
    // Test utility methods in sample buffer factory
    XCTAssertFalse([self.sampleBufferFactory isUsingVideoFilter]);
    XCTAssertFalse([self.sampleBufferFactory isUsingVideoEncoder]);
    
    // After setting encoder settings, should detect encoder usage
    self.sampleBufferFactory.videoEncoderSetting = [@{kMEVECodecNameKey: @"libx264"} mutableCopy];
    XCTAssertTrue([self.sampleBufferFactory isUsingVideoEncoder]);
}

- (void)testH264SyncSampleAttachment {
    static const uint8_t idrNAL[] = {0x00, 0x00, 0x00, 0x01, 0x65, 0x00};
    BOOL notSync = YES;
    BOOL ok = MEGetNotSyncForPacketBytes(idrNAL,
                                         sizeof(idrNAL),
                                         AV_CODEC_ID_H264,
                                         kCMVideoCodecType_H264,
                                         0,
                                         &notSync);
    XCTAssertTrue(ok);
    XCTAssertFalse(notSync);
}

- (void)testH264NonSyncSampleAttachment {
    static const uint8_t nonIdrNAL[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x00};
    BOOL notSync = NO;
    BOOL ok = MEGetNotSyncForPacketBytes(nonIdrNAL,
                                         sizeof(nonIdrNAL),
                                         AV_CODEC_ID_H264,
                                         kCMVideoCodecType_H264,
                                         0,
                                         &notSync);
    XCTAssertTrue(ok);
    XCTAssertTrue(notSync);
}

- (void)testHEVCSyncSampleAttachment {
    static const uint8_t blaNAL[] = {0x00, 0x00, 0x00, 0x01, 0x20, 0x01};
    BOOL notSync = YES;
    BOOL ok = MEGetNotSyncForPacketBytes(blaNAL,
                                         sizeof(blaNAL),
                                         AV_CODEC_ID_HEVC,
                                         kCMVideoCodecType_HEVC,
                                         0,
                                         &notSync);
    XCTAssertTrue(ok);
    XCTAssertFalse(notSync);
}

- (void)testHEVCNonSyncSampleAttachment {
    static const uint8_t trailNAL[] = {0x00, 0x00, 0x00, 0x01, 0x02, 0x01};
    BOOL notSync = NO;
    BOOL ok = MEGetNotSyncForPacketBytes(trailNAL,
                                         sizeof(trailNAL),
                                         AV_CODEC_ID_HEVC,
                                         kCMVideoCodecType_HEVC,
                                         0,
                                         &notSync);
    XCTAssertTrue(ok);
    XCTAssertTrue(notSync);
}

@end
