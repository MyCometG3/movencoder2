//
//  MEVideoProcessor.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//  Copyright © 2018-2023 MyCometG3. All rights reserved.
//

/*
 * This file is part of movencoder2.
 *
 * movencoder2 is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * movencoder2 is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with movencoder2; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#import "MECommon.h"
#import "MEVideoProcessor.h"
#import "MEManager.h"
#import "MEInput.h"
#import "MEOutput.h"
#import "SBChannel.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

// Helper function for creating track ID keys
static inline NSString* keyForTrackID(CMPersistentTrackID trackID) {
    return [NSString stringWithFormat:@"%d", trackID];
}

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

@interface MEVideoProcessor ()

@property (strong, nonatomic) NSMutableDictionary* managers;
@property (strong, nonatomic) NSMutableArray<SBChannel*>* sbChannels;
@property (nonatomic, copy) void (^prepareCopyChannelBlock)(AVMovie* movie, AVAssetReader* ar, AVAssetWriter* aw, AVMediaType type);

@end

@implementation MEVideoProcessor

- (instancetype)initWithParameters:(NSMutableDictionary*)param {
    self = [super init];
    if (self) {
        _param = param;
    }
    return self;
}

- (instancetype)initWithParameters:(NSMutableDictionary*)param 
                          managers:(NSMutableDictionary*)managers 
                        sbChannels:(NSMutableArray<SBChannel*>*)sbChannels
               prepareCopyChannelBlock:(void (^)(AVMovie*, AVAssetReader*, AVAssetWriter*, AVMediaType))prepareCopyChannelBlock {
    self = [super init];
    if (self) {
        _param = param;
        _managers = managers;
        _sbChannels = sbChannels;
        _prepareCopyChannelBlock = prepareCopyChannelBlock;
    }
    return self;
}

#pragma mark - Property Accessors

- (BOOL)copyField {
    NSNumber* value = self.param[@"copyField"];
    return value ? value.boolValue : NO;
}

- (BOOL)copyNCLC {
    NSNumber* value = self.param[@"copyNCLC"];
    return value ? value.boolValue : NO;
}

- (BOOL)videoEncode {
    NSNumber* value = self.param[@"videoEncode"];
    return value ? value.boolValue : YES;
}

- (NSString*)videoFourcc {
    return self.param[@"videoCodec"] ?: @"avc1";
}

- (int)videoBitRate {
    NSNumber* value = self.param[@"videoKbps"];
    return value ? (value.floatValue * 1000) : 5000000;
}

#pragma mark - Video Processing Methods

- (BOOL)hasFieldModeSupportOf:(AVMovieTrack*)track {
    BOOL result = FALSE;
    NSArray* descArray = track.formatDescriptions;
    
    CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef) descArray[0];
    CFDictionaryRef dict = NULL;
    VTDecompressionSessionRef decompSession = NULL;
    {
        OSStatus status = noErr;
        CFDictionaryRef spec = NULL;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              desc,
                                              spec,
                                              NULL,
                                              NULL,
                                              &decompSession);
        if (status != noErr) return FALSE;
        
        status = VTSessionCopySupportedPropertyDictionary(decompSession, &dict);
        
        if (status != noErr) goto end;
    }
    
    if (dict) {
        CFDictionaryRef propFieldMode = CFDictionaryGetValue(dict, kVTDecompressionPropertyKey_FieldMode);
        if (propFieldMode) {
            CFArrayRef propList = CFDictionaryGetValue(propFieldMode, kVTPropertySupportedValueListKey);
            if (propList) {
                result = CFArrayContainsValue(propList,
                                              CFRangeMake(0, CFArrayGetCount(propList)),
                                              kVTDecompressionProperty_FieldMode_BothFields);
            }
        }
    }
    
end:
    if (dict) CFRelease(dict);
    if (decompSession) {
        VTDecompressionSessionInvalidate(decompSession);
        CFRelease(decompSession);
    }
    return result;
}

- (void)addDecompressionPropertiesOf:(AVMovieTrack*)track setting:(NSMutableDictionary*)arOutputSetting {
    if ([self hasFieldModeSupportOf:track]) {
        NSDictionary* decompressionProperties = nil;
        
        // Keep both fields
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        dict[(__bridge NSString*)kVTDecompressionPropertyKey_FieldMode] = (__bridge NSString*)kVTDecompressionProperty_FieldMode_BothFields;
        decompressionProperties = [dict copy];
        
        // TODO: kVTDecompressionPropertyKey_PixelTransferProperties

        arOutputSetting[AVVideoDecompressionPropertiesKey] = decompressionProperties;
    }
}

- (NSMutableDictionary<NSString*,id>*)videoCompressionSettingFor:(AVMovieTrack*)track {
    //
    NSDictionary* compressionProperties = nil;
    NSArray* proresFamily = @[@"ap4h", @"apch", @"apcn", @"apcs", @"apco"];
    if ([proresFamily containsObject:self.videoFourcc]) {
        // ProRes family
    } else {
        compressionProperties = @{AVVideoAverageBitRateKey:@(self.videoBitRate)};
    }
    
    NSDictionary* cleanAperture = nil;
    NSDictionary* pixelAspectRatio = nil;
    NSDictionary* nclc = nil;
    
    CGSize trackDimensions = track.naturalSize;
    NSArray* descArray = track.formatDescriptions;
    if (descArray.count > 0) {
        CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)(descArray[0]);
        trackDimensions = CMVideoFormatDescriptionGetPresentationDimensions(desc, FALSE, FALSE);
        
        NSNumber* fieldCount = nil;
        NSString* fieldDetail = nil;
        
        CFPropertyListRef cfExtCA = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_CleanAperture);
        if (cfExtCA != NULL) {
            NSDictionary* extCA = (__bridge NSDictionary*)cfExtCA;
            NSNumber* width = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureWidth];
            NSNumber* height = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureHeight];
            NSNumber* hOffset = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureHorizontalOffset];
            NSNumber* vOffset = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureVerticalOffset];
            
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            dict[AVVideoCleanApertureWidthKey] = width;
            dict[AVVideoCleanApertureHeightKey] = height;
            dict[AVVideoCleanApertureHorizontalOffsetKey] = hOffset;
            dict[AVVideoCleanApertureVerticalOffsetKey] = vOffset;
            
            cleanAperture = dict;
        }
        
        CFPropertyListRef cfExtPA = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_PixelAspectRatio);
        if (cfExtPA != NULL) {
            NSDictionary* extPA = (__bridge NSDictionary*)cfExtPA;
            NSNumber* hSpacing = (NSNumber*)extPA[(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing];
            NSNumber* vSpacing = (NSNumber*)extPA[(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing];
            
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            dict[AVVideoPixelAspectRatioHorizontalSpacingKey] = hSpacing;
            dict[AVVideoPixelAspectRatioVerticalSpacingKey] = vSpacing;
            
            pixelAspectRatio = dict;
        }
        
        if (self.copyNCLC) {
            CFPropertyListRef cfExtCP = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_ColorPrimaries);
            CFPropertyListRef cfExtTF = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_TransferFunction);
            CFPropertyListRef cfExtMX = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_YCbCrMatrix);
            if (cfExtCP && cfExtTF && cfExtMX) {
                NSString* colorPrimaries = (__bridge NSString*) cfExtCP;
                NSString* transferFunction = (__bridge NSString*) cfExtTF;
                NSString* ycbcrMatrix = (__bridge NSString*) cfExtMX;
                
                NSMutableDictionary* dict = [NSMutableDictionary dictionary];
                dict[AVVideoColorPrimariesKey] = colorPrimaries;
                dict[AVVideoTransferFunctionKey] = transferFunction;
                dict[AVVideoYCbCrMatrixKey] = ycbcrMatrix;
                
                nclc = dict;
            }
        }
        
        if (self.copyField) {
            CFPropertyListRef cfExtFC = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldCount);
            CFPropertyListRef cfExtFD = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldDetail);
            if (cfExtFC && cfExtFD) {
                fieldCount = (__bridge NSNumber*)cfExtFC;
                fieldDetail = (__bridge NSString*)cfExtFD;
            }
        }
        
        if (fieldCount || fieldDetail) {
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            
            if (self.copyField && fieldCount && fieldDetail) {
                dict[(__bridge NSString*)kVTCompressionPropertyKey_FieldCount] = fieldCount;
                dict[(__bridge NSString*)kVTCompressionPropertyKey_FieldDetail] = fieldDetail;
            }
            
            if (compressionProperties) {
                [dict addEntriesFromDictionary:compressionProperties];
            }
            compressionProperties = dict;
        }
    }
    
    // destination
    NSMutableDictionary* awInputSetting = [NSMutableDictionary dictionary];
    awInputSetting[AVVideoCodecKey] = self.videoFourcc;
    awInputSetting[AVVideoWidthKey] = @(trackDimensions.width);
    awInputSetting[AVVideoHeightKey] = @(trackDimensions.height);
    if (compressionProperties) {
        awInputSetting[AVVideoCompressionPropertiesKey] = compressionProperties;
    }
    
    if (cleanAperture) {
        awInputSetting[AVVideoCleanApertureKey] = cleanAperture;
    }
    if (pixelAspectRatio) {
        awInputSetting[AVVideoPixelAspectRatioKey] = pixelAspectRatio;
    }
    if (nclc) {
        awInputSetting[AVVideoColorPropertiesKey] = nclc;
    }
    return awInputSetting;
}

- (void)prepareVideoChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw {
    if (self.videoEncode == FALSE) {
        if (self.prepareCopyChannelBlock) {
            self.prepareCopyChannelBlock(movie, ar, aw, AVMediaTypeVideo);
        }
        return;
    }
    
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeVideo]) {
        // source
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        [self addDecompressionPropertiesOf:track setting:arOutputSetting];
        arOutputSetting[(__bridge NSString*)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_422YpCbCr8);
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                   outputSettings:arOutputSetting];
        [ar addOutput:arOutput];
        
        //
        NSMutableDictionary<NSString*,id> * awInputSetting = [self videoCompressionSettingFor:track];
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                         outputSettings:awInputSetting];
        awInput.mediaTimeScale = track.naturalTimeScale;
        [aw addInput:awInput];
        
        // channel
        SBChannel* sbcVideo = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                      consumerME:(MEInput*)awInput
                                                         TrackID:track.trackID];
        [self.sbChannels addObject:sbcVideo];
    }
}

- (void)prepareVideoMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw {
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeVideo]) {
        //
        NSString* key = keyForTrackID(track.trackID);
        //NSDictionary* managers = self.managers[key];
        MEManager* mgr = self.managers[key];
        if (!mgr) continue;

        // Capture source track's format description extensions
        CMFormatDescriptionRef desc =  (__bridge CMFormatDescriptionRef)track.formatDescriptions[0];
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
        [ar addOutput:arOutput];
        
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
        [aw addInput:awInput];
        
        // destination channel
        SBChannel* sbcMEOutput = [SBChannel sbChannelWithProducerME:(MEOutput*)meOutput
                                                         consumerME:(MEInput*)awInput
                                                            TrackID:track.trackID];
        [self.sbChannels addObject:sbcMEOutput];
    }
}

@end