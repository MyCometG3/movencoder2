//  MEEncoderPipelineFlagsTests.m
//  movencoder2Tests
//
//  Validates MEEncoderPipeline state flags transitions under flush-only path.
//
@import XCTest;
@import Foundation;
@import CoreMedia;

#include <libavcodec/avcodec.h>

#import "MEEncoderPipeline.h"

@interface MEEncoderPipelineFlagsTests : XCTestCase
@end

@implementation MEEncoderPipelineFlagsTests

- (void)testFlagsTransitionFlushOnly {
    MEEncoderPipeline *enc = [[MEEncoderPipeline alloc] init];
    enc.verbose = NO;
    enc.logLevel = AV_LOG_ERROR;
    enc.timeBase = 30000;

    // Minimal encoder settings: choose x264 for wider availability
    enc.videoEncoderSetting = [@{ kMEVECodecNameKey: @"libx264" } mutableCopy];

    // Prepare via filtered-frame path with a minimal AVFrame
    AVFrame *frame = av_frame_alloc();
    XCTAssertNotNil(frame);
    frame->format = AV_PIX_FMT_YUV420P;
    frame->width = 16;
    frame->height = 16;
    frame->sample_aspect_ratio = av_make_q(1, 1);

    BOOL ok = [enc prepareVideoEncoderWith:NULL filteredFrame:(void *)frame hasValidFilteredFrame:YES];
    // Ownership note: prepare does not take ownership of the AVFrame pointer
    av_frame_free(&frame);
    XCTAssertTrue(ok, @"Encoder should prepare successfully with minimal frame");

    // Initially, flags
    XCTAssertTrue(enc.isReady);
    XCTAssertFalse(enc.isEOF);
    XCTAssertFalse(enc.isFlushed);

    // Flush without sending frames
    int sendRet = 0;
    XCTAssertTrue([enc flushEncoderWithResult:&sendRet]);
    XCTAssertTrue(enc.isFlushed);

    // Receive until EOF observed
    int recvRet = 0;
    BOOL recvOK = [enc receivePacketFromEncoderWithResult:&recvRet];
    XCTAssertTrue(recvOK);

    // After flushing out, either we need more input (EAGAIN) or reach EOF; loop a few times
    for (int i = 0; i < 8 && !enc.isEOF; i++) {
        recvOK = [enc receivePacketFromEncoderWithResult:&recvRet];
        XCTAssertTrue(recvOK);
    }

    XCTAssertTrue(enc.isEOF, @"Encoder should eventually reach EOF after flush-only path");
}

@end
