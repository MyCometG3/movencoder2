//
//  METranscoder.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "METranscoder+Internal.h"
#import "MESecureLogging.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation METranscoder (CodecHelpers)

uint32_t formatIDFor(NSString* fourCC)
{
    uint32_t result = 0;
    if (!fourCC || [fourCC length] < 4) return 0;
    const char* str = [fourCC UTF8String];
    if (!str) return 0;
    NSUInteger length = [fourCC length];
    if (length >= 4) {
        for (NSUInteger i = 0; i < 4; i++) {
            unichar ch = [fourCC characterAtIndex:i];
            if (ch < 32 || ch > 126) return 0;
        }
        uint32_t c0 = (unsigned char)str[0];
        uint32_t c1 = (unsigned char)str[1];
        uint32_t c2 = (unsigned char)str[2];
        uint32_t c3 = (unsigned char)str[3];
        result = (c0<<24) + (c1<<16) + (c2<<8) + (c3);
    }
    return result;
}

- (uint32_t) audioFormatID
{
    return formatIDFor(self.audioFourcc);
}

- (uint32_t) videoFormatID
{
    return formatIDFor(self.videoFourcc);
}

- (void) prepareCopyChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw of:(AVMediaType)type
{
    for (AVAssetTrack* track in [movie tracksWithMediaType:type]) {
        // source
        NSDictionary<NSString*,id>* arOutputSetting = nil;
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:arOutputSetting];
        
        // destination
        NSDictionary<NSString*,id>* awInputSetting = nil;
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:type outputSettings:awInputSetting];
        if (type != AVMediaTypeAudio) {
            awInput.mediaTimeScale = track.naturalTimeScale;
        }
        
        __block BOOL arOK = FALSE;
        __block BOOL awOK = FALSE;
        dispatch_sync(self.processQueue, ^{
            arOK = [ar canAddOutput:arOutput];
            awOK = [aw canAddInput:awInput];
        });
        if (!(arOK && awOK)) {
            SecureLogf(@"Skipping track(%d) - unsupported", track.trackID);
            continue;
        }
        dispatch_sync(self.processQueue, ^{
            [ar addOutput:arOutput];
            [aw addInput:awInput];
        });
        
        // channel
        SBChannel* sbcCopy = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                     consumerME:(MEInput*)awInput
                                                        TrackID:track.trackID];
        [self.sbChannels addObject:sbcCopy];
    }
}

- (void) prepareOtherMediaChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    if (!self.copyOtherMedia) return;
    
    // copy non-av media type (excludes muxed media)
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeText];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeClosedCaption];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeSubtitle];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeTimecode];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeMetadata];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeDepthData];
}

@end

NS_ASSUME_NONNULL_END
