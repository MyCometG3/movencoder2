//
//  METranscoder+VideoChannels.m
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

@implementation METranscoder (VideoChannels)

- (void) prepareVideoChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    if (self.videoEncode == FALSE) {
        [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeVideo];
        return;
    }
    
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeVideo]) {
        // source
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        [self addDecompressionPropertiesOf:track setting:arOutputSetting];
        arOutputSetting[(__bridge NSString*)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_422YpCbCr8);
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                   outputSettings:arOutputSetting];
        __block BOOL arOK = FALSE;
        dispatch_sync(self.processQueue, ^{
            arOK = [ar canAddOutput:arOutput];
        });
        if (!arOK) {
            SecureErrorLogf(@"Skipping video track(%d) - reader output not supported", track.trackID);
            continue;
        }
        dispatch_sync(self.processQueue, ^{
            [ar addOutput:arOutput];
        });
        
        //
        NSMutableDictionary<NSString*,id> * awInputSetting = [self videoCompressionSettingFor:track];
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                         outputSettings:awInputSetting];
        awInput.mediaTimeScale = track.naturalTimeScale;
        __block BOOL awOK = FALSE;
        dispatch_sync(self.processQueue, ^{
            awOK = [aw canAddInput:awInput];
        });
        if (!awOK) {
            SecureErrorLogf(@"Skipping video track(%d) - writer input not supported", track.trackID);
            continue;
        }
        dispatch_sync(self.processQueue, ^{
            [aw addInput:awInput];
        });
        
        // channel
        SBChannel* sbcVideo = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                      consumerME:(MEInput*)awInput
                                                         TrackID:track.trackID];
        [self.sbChannels addObject:sbcVideo];
    }
}

- (void) prepareVideoMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeVideo]) {
        //
        NSString* key = keyForTrackID(track.trackID);
        //NSDictionary* managers = self.managers[key];
        MEManager* mgr = self.managers[key];
        if (!mgr) continue;

        // Capture source track's format description extensions
        NSArray* descArray = track.formatDescriptions;
        if (descArray.count == 0) {
            SecureErrorLogf(@"Skipping video track(%d) - no format descriptions", track.trackID);
            continue;
        }
        CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)descArray[0];
        CFDictionaryRef extensions =  CMFormatDescriptionGetExtensions(desc);
        mgr.sourceExtensions = extensions;
        
        int32_t ts = track.naturalTimeScale;
        mgr.mediaTimeScale = ts;
        
        // source from
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        [self addDecompressionPropertiesOf:track setting:arOutputSetting];
        arOutputSetting[(__bridge NSString*)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_422YpCbCr8);
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                   outputSettings:arOutputSetting];
        __block BOOL arOK = FALSE;
        dispatch_sync(self.processQueue, ^{
            arOK = [ar canAddOutput:arOutput];
        });
        if (!arOK) {
            SecureErrorLogf(@"Skipping video track(%d) - reader output not supported", track.trackID);
            continue;
        }
        dispatch_sync(self.processQueue, ^{
            [ar addOutput:arOutput];
        });
        
        // source to
        MEInput* meInput = [MEInput inputWithManager:mgr];
        
        // source channel
        SBChannel* sbcMEInput = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                        consumerME:meInput
                                                           TrackID:track.trackID];
        [self.sbChannels addObject:sbcMEInput];
        
        /* ========================================================================================== */
        
        // destination from
        MEOutput* meOutput = [MEOutput outputWithManager:mgr];
        
        // destination to
        NSMutableDictionary<NSString*,id>* awInputSetting;
        if (self.videoEncode == FALSE) {
            awInputSetting = nil; // passthru writing
        } else {
            awInputSetting = [self videoCompressionSettingFor:track]; // transcode using AVFoundation
        }
        
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                         outputSettings:awInputSetting];
        awInput.mediaTimeScale = track.naturalTimeScale;
        __block BOOL awOK = FALSE;
        dispatch_sync(self.processQueue, ^{
            awOK = [aw canAddInput:awInput];
        });
        if (!awOK) {
            SecureErrorLogf(@"Skipping video track(%d) - writer input not supported", track.trackID);
            continue;
        }
        dispatch_sync(self.processQueue, ^{
            [aw addInput:awInput];
        });
        
        // destination channel
        SBChannel* sbcMEOutput = [SBChannel sbChannelWithProducerME:(MEOutput*)meOutput
                                                         consumerME:(MEInput*)awInput
                                                            TrackID:track.trackID];
        [self.sbChannels addObject:sbcMEOutput];
    }
}

@end

NS_ASSUME_NONNULL_END
