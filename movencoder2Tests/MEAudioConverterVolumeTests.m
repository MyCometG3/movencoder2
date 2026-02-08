//  MEAudioConverterVolumeTests.m
//  movencoder2Tests
//
//  Tests for MEAudioConverter volumeDb boundaries and behavior.
//
//  Focus: ensure gain application respects -10..+10 dB and 0 dB no-op.
//
@import XCTest;
@import AVFoundation;
@import CoreMedia;

#import <math.h>

#import "MEAudioConverter.h"

@interface MEAudioConverterVolumeTests : XCTestCase
@end

@implementation MEAudioConverterVolumeTests

- (AVAudioFormat *)pcmFormatInt16Stereo48k {
    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = 48000.0;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    asbd.mBytesPerPacket = 4; // 2ch * 2bytes
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame = 4;
    asbd.mChannelsPerFrame = 2;
    asbd.mBitsPerChannel = 16;
    AVAudioFormat *fmt = [[AVAudioFormat alloc] initWithStreamDescription:&asbd];
    return fmt;
}

- (AVAudioPCMBuffer *)makeSinePCM:(AVAudioFormat *)fmt frames:(AVAudioFrameCount)frames amplitude:(double)amp {
    AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fmt frameCapacity:frames];
    buf.frameLength = frames;
    // Generate simple int16 sine in interleaved layout
    const AudioBufferList *abl = buf.audioBufferList;
    SInt16 *data = (SInt16 *)(abl && abl->mNumberBuffers > 0 ? abl->mBuffers[0].mData : NULL);
    if (!data) {
        return buf;
    }
    UInt32 ch = fmt.channelCount;
    double freq = 440.0, sr = fmt.sampleRate;
    for (AVAudioFrameCount i = 0; i < frames; i++) {
        double s = sin(2.0 * M_PI * freq * (double)i / sr) * amp;
        SInt16 sample = (SInt16)llround(s);
        for (UInt32 c = 0; c < ch; c++) {
            data[i * ch + c] = sample;
        }
    }
    return buf;
}

- (void)testVolumeDbZeroNoChangeInt16 {
    MEAudioConverter *conv = [[MEAudioConverter alloc] init];
    conv.verbose = NO;
    conv.sourceFormat = [self pcmFormatInt16Stereo48k];
    conv.destinationFormat = conv.sourceFormat;
    conv.volumeDb = 0.0; // no-op

    // Build a sample buffer from generated PCM
    AVAudioPCMBuffer *pcm = [self makeSinePCM:conv.sourceFormat frames:480 amplitude:2000.0];
    CMTime pts = CMTimeMake(0, 48000);
    CMSampleBufferRef sb = [conv createSampleBufferFromPCMBuffer:pcm withPresentationTimeStamp:pts format:conv.destinationFormat];
    if (!sb) {
        XCTFail(@"Failed to create input sample buffer");
        return;
    }

    // Append and process
    XCTAssertTrue([conv appendSampleBufferInternal:sb]);
    CFRelease(sb);

    // Pull converted buffer
    CMSampleBufferRef out = [conv copyNextSampleBufferInternal];
    if (!out) {
        XCTFail(@"No output sample buffer produced");
        return;
    }

    // Verify samples unchanged by measuring first few samples
    // Convert back to PCM for inspection
    AVAudioPCMBuffer *outPCM = [conv createPCMBufferFromSampleBuffer:out withFormat:conv.destinationFormat];
    CFRelease(out);
    XCTAssertNotNil(outPCM);

    SInt16 *inData = pcm.int16ChannelData[0];
    SInt16 *outData = outPCM.int16ChannelData[0];
    for (int i = 0; i < 16; i++) {
        XCTAssertEqual(outData[i], inData[i], @"0 dB should not change samples");
    }
}

- (void)testVolumeDbClampAtPlus10dBInt16 {
    MEAudioConverter *conv = [[MEAudioConverter alloc] init];
    conv.verbose = NO;
    conv.sourceFormat = [self pcmFormatInt16Stereo48k];
    conv.destinationFormat = conv.sourceFormat;
    conv.volumeDb = +10.0; // max boost

    AVAudioPCMBuffer *pcm = [self makeSinePCM:conv.sourceFormat frames:480 amplitude:30000.0]; // near max
    CMTime pts = CMTimeMake(0, 48000);
    CMSampleBufferRef sb = [conv createSampleBufferFromPCMBuffer:pcm withPresentationTimeStamp:pts format:conv.destinationFormat];
    if (!sb) {
        XCTFail(@"Failed to create input sample buffer");
        return;
    }
    XCTAssertTrue([conv appendSampleBufferInternal:sb]);
    CFRelease(sb);

    CMSampleBufferRef out = [conv copyNextSampleBufferInternal];
    if (!out) {
        XCTFail(@"No output sample buffer produced");
        return;
    }
    AVAudioPCMBuffer *outPCM = [conv createPCMBufferFromSampleBuffer:out withFormat:conv.destinationFormat];
    CFRelease(out);
    XCTAssertNotNil(outPCM);

    // After +10dB boost, expect at least one sample to grow or saturate
    const AudioBufferList *inABL = pcm.audioBufferList;
    const AudioBufferList *outABL = outPCM.audioBufferList;
    const SInt16 *inData = (const SInt16 *)(inABL && inABL->mNumberBuffers > 0 ? inABL->mBuffers[0].mData : NULL);
    const SInt16 *outData = (const SInt16 *)(outABL && outABL->mNumberBuffers > 0 ? outABL->mBuffers[0].mData : NULL);
    XCTAssertTrue(inData != NULL);
    XCTAssertTrue(outData != NULL);
    BOOL sawIncrease = NO;
    BOOL sawSaturation = NO;
    for (int i = 0; i < 64; i++) {
        if (labs(outData[i]) > labs(inData[i])) {
            sawIncrease = YES;
        }
        if (outData[i] == 32767 || outData[i] == -32768) {
            sawSaturation = YES;
        }
    }
    XCTAssertTrue(sawIncrease || sawSaturation, @"Expected gain or saturation after +10 dB");
}

- (void)testVolumeDbClampAtMinus10dBInt16 {
    MEAudioConverter *conv = [[MEAudioConverter alloc] init];
    conv.verbose = NO;
    conv.sourceFormat = [self pcmFormatInt16Stereo48k];
    conv.destinationFormat = conv.sourceFormat;
    conv.volumeDb = -10.0; // max attenuation

    AVAudioPCMBuffer *pcm = [self makeSinePCM:conv.sourceFormat frames:480 amplitude:20000.0];
    CMTime pts = CMTimeMake(0, 48000);
    CMSampleBufferRef sb = [conv createSampleBufferFromPCMBuffer:pcm withPresentationTimeStamp:pts format:conv.destinationFormat];
    if (!sb) {
        XCTFail(@"Failed to create input sample buffer");
        return;
    }
    XCTAssertTrue([conv appendSampleBufferInternal:sb]);
    CFRelease(sb);

    CMSampleBufferRef out = [conv copyNextSampleBufferInternal];
    if (!out) {
        XCTFail(@"No output sample buffer produced");
        return;
    }
    AVAudioPCMBuffer *outPCM = [conv createPCMBufferFromSampleBuffer:out withFormat:conv.destinationFormat];
    CFRelease(out);
    XCTAssertNotNil(outPCM);

    // After -10dB attenuation, expect at least one non-zero sample to reduce in magnitude
    const AudioBufferList *inABL = pcm.audioBufferList;
    const AudioBufferList *outABL = outPCM.audioBufferList;
    const SInt16 *inData = (const SInt16 *)(inABL && inABL->mNumberBuffers > 0 ? inABL->mBuffers[0].mData : NULL);
    const SInt16 *outData = (const SInt16 *)(outABL && outABL->mNumberBuffers > 0 ? outABL->mBuffers[0].mData : NULL);
    XCTAssertTrue(inData != NULL);
    XCTAssertTrue(outData != NULL);
    BOOL sawDecrease = NO;
    for (int i = 0; i < 64; i++) {
        if (inData[i] != 0 && labs(outData[i]) < labs(inData[i])) {
            sawDecrease = YES;
            break;
        }
    }
    XCTAssertTrue(sawDecrease, @"Expected attenuation after -10 dB");
}

@end
