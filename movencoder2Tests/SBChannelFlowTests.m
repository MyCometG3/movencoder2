//  SBChannelFlowTests.m
//  movencoder2Tests
//
//  Tests for SBChannel producer→consumer flow and progress info correctness.
//
@import XCTest;
@import AVFoundation;
@import CoreMedia;

#import "SBChannel.h"
#import "MEInput.h"
#import "MEOutput.h"
#import "MEManager.h"
#import "MECommon.h"

@interface DummyManager : MEManager
@property (nonatomic) BOOL ready;
@property (nonatomic) BOOL produced;
@property (nonatomic) int appendedCount;
@property (nonatomic, copy) RequestHandler requestHandler;
@end

@implementation DummyManager
- (instancetype)init { self = [super init]; if (self) { _ready = YES; _produced = NO; } return self; }
- (BOOL)appendSampleBufferInternal:(CMSampleBufferRef)sb { _appendedCount++; return YES; }
- (BOOL)isReadyForMoreMediaDataInternal { return _ready; }
- (void)markAsFinishedInternal { _ready = NO; }
- (void)requestMediaDataWhenReadyOnQueueInternal:(dispatch_queue_t)queue usingBlock:(RequestHandler)block { self.requestHandler = [block copy]; }
- (CMTimeScale)mediaTimeScaleInternal { return 30000; }
- (void)setMediaTimeScaleInternal:(CMTimeScale)mediaTimeScale { /* no-op */ }
- (AVMediaType)mediaTypeInternal { return AVMediaTypeAudio; }
// Override to use internal proxy for SBChannel meOutput access
- (CMSampleBufferRef)copyNextSampleBufferInternal {
    // Create a trivial audio sample buffer to feed once then EOF
    if (_produced) {
        return NULL;
    }
    _produced = YES;
    CMSampleBufferRef sb = NULL;
    CMBlockBufferRef bb = NULL;
    OSStatus st = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, 4, kCFAllocatorDefault, NULL, 0, 4, 0, &bb);
    if (st != noErr) return NULL;
    CMSampleTimingInfo timing = { .duration = CMTimeMake(1, 30000), .presentationTimeStamp = CMTimeMake(0, 30000), .decodeTimeStamp = kCMTimeInvalid };
    CMAudioFormatDescriptionRef desc = NULL;
    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = 48000.0;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    asbd.mChannelsPerFrame = 2;
    asbd.mFramesPerPacket = 1;
    asbd.mBitsPerChannel = 16;
    asbd.mBytesPerFrame = 4;
    asbd.mBytesPerPacket = 4;
    st = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, NULL, 0, NULL, NULL, &desc);
    if (st != noErr) { if (bb) CFRelease(bb); return NULL; }
    st = CMSampleBufferCreate(kCFAllocatorDefault, bb, true, NULL, NULL, desc, 1, 1, &timing, 0, NULL, &sb);
    if (bb) CFRelease(bb);
    if (desc) CFRelease(desc);
    return (st == noErr) ? sb : NULL;
}

- (nullable CMSampleBufferRef)copyNextSampleBuffer {
    return [self copyNextSampleBufferInternal];
}
@end

@interface SBChannelFlowTests : XCTestCase <SBChannelDelegate>
@property (nonatomic) int didReadCount;
@property (nonatomic, strong) SBChannel *channel;
@end

@implementation SBChannelFlowTests

- (void)didReadBuffer:(CMSampleBufferRef)buffer from:(SBChannel *)channel { self.didReadCount++; }

- (void)testSBChannelProducesAndCompletesWithProgressInfo {
    DummyManager *manager = [[DummyManager alloc] init];
    MEOutput *out = [MEOutput outputWithManager:manager];
    MEInput *in = [MEInput inputWithManager:manager];
    SBChannel *ch = [SBChannel sbChannelWithProducerME:out consumerME:in TrackID:123];
    self.channel = ch;
    ch.showProgress = NO;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [ch startWithDelegate:self completionHandler:^{ [done fulfill]; }];
    if (manager.requestHandler) {
        manager.requestHandler();
    }
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    // Validate that at least one buffer passed and finished flag set
    XCTAssertTrue(ch.isFinished);
    XCTAssertGreaterThanOrEqual(self.didReadCount, 1);

    NSDictionary *info = ch.info;
    XCTAssertNotNil(info);
    XCTAssertEqualObjects(info[kProgressMediaTypeKey], AVMediaTypeAudio);
    XCTAssertEqualObjects(info[kProgressTagKey], @"audio");
    XCTAssertEqualObjects(info[kProgressTrackIDKey], @(123));
}

@end
