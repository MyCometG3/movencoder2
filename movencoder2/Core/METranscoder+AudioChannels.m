//
//  METranscoder+AudioChannels.m
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

@implementation METranscoder (AudioChannels)

// MARK: - Shared Audio Helper (minimal extraction)
static void MEAdjustAudioBitrateIfNeeded(NSMutableDictionary<NSString*,id>* awInputSetting,
                                         AVAudioChannelLayout* avacSrcLayout,
                                         int sampleRate,
                                         int requestedBitrate)
{
    NSNumber* bitrateNum = awInputSetting[AVEncoderBitRateKey];
    if (bitrateNum == nil) return; // No bitrate key -> nothing to adjust (e.g. LPCM)

    AVAudioFormat* inFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(double)sampleRate
                                                                         channelLayout:avacSrcLayout];
    AVAudioFormat* outFormat = [[AVAudioFormat alloc] initWithSettings:awInputSetting];
    if (!inFormat || !outFormat) return;

    AVAudioConverter* converter = [[AVAudioConverter alloc] initFromFormat:inFormat toFormat:outFormat];
    if (!converter) return;
    NSArray<NSNumber*>* bitrateArray = converter.applicableEncodeBitRates;
    if (!bitrateArray || [bitrateArray containsObject:@(requestedBitrate)]) {
        return; // Requested bitrate supported
    }
    // Keep the maximum supported bitrate (mirrors existing logic)
    NSNumber* prev = bitrateArray.firstObject;
    for (NSNumber* item in bitrateArray) {
        if ([item compare:prev] == NSOrderedDescending) {
            prev = item;
        }
    }
    if (prev != nil) {
        awInputSetting[AVEncoderBitRateKey] = prev;
        SecureLogf(@"Bitrate adjustment to %@ from %@", prev, @(requestedBitrate));
    }
}


- (void) prepareAudioMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    if (self.audioEncode == FALSE) {
        [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeAudio];
        return;
    }
    
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeAudio]) {
        // Check if we have a registered MEAudioConverter for this track
        NSString* key = keyForTrackID(track.trackID);
        MEAudioConverter* audioConverter = self.managers[key];
        if (![audioConverter isKindOfClass:[MEAudioConverter class]]) {
            // Fall back to regular audio processing if no MEAudioConverter registered
            [self prepareAudioMediaChannelWith:movie from:ar to:aw];
            return;
        }
        
        // Get source audio parameters
        NSArray* descArray = track.formatDescriptions;
        CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef) descArray[0];
        const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc);
        if (!asbd) {
            SecureErrorLogf(@"Skipping audio track(%d) - no audio format description", track.trackID);
            continue;
        }
        
        int sampleRate = (int)asbd->mSampleRate;
        int numChannel = (int)asbd->mChannelsPerFrame;
        
        /* ========================================================================================== */
        
        // Get source AudioChannelLayout and determine target layout
        AVAudioChannelLayout* avacSrcLayout = nil;
        AVAudioChannelLayout* avacDstLayout = nil;
        
        size_t srcAclSize = 0;
        const AudioChannelLayout* srcAclPtr = CMAudioFormatDescriptionGetChannelLayout(desc, &srcAclSize);
        if (srcAclPtr != NULL && srcAclSize > 0) {
            // Use existing layout parsing logic from the original method
            AudioChannelLayoutTag srcTag = srcAclPtr->mChannelLayoutTag;
            AudioChannelLayoutTag dstTag = 0;
            
            if (self.audioChannelLayoutTag != 0) {
                dstTag = self.audioChannelLayoutTag;
            } else {
                // Channel layout analysis and mapping (basic implementation)
                UInt32 ioPropertyDataSize = 4;
                UInt32 outPropertyData = 0;
                OSStatus err = AudioFormatGetProperty(kAudioFormatProperty_NumberOfChannelsForLayout,
                                                      (UInt32)srcAclSize,
                                                      srcAclPtr,
                                                      &ioPropertyDataSize,
                                                      &outPropertyData);
                if (!err && outPropertyData > 0) {
                    numChannel = (int)outPropertyData;
                }
                
                if (AudioChannelLayoutTag_GetNumberOfChannels(srcTag)) {
                    dstTag = srcTag;
                } else {
                    // Fallback to channel count based mapping
                    if (numChannel >= 1 && numChannel <= 8) {
                        dstTag = kMEAACDestinationLayouts[numChannel - 1];
                    }
                }
            }
            
            avacSrcLayout = [AVAudioChannelLayout layoutWithLayout:srcAclPtr];
            if (dstTag != 0) {
                avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:dstTag];
            }
        } else {
            // Default layouts when source has no channel layout
            if (numChannel >= 1 && numChannel <= 8) {
                AudioChannelLayoutTag srcTag = kMEMPEGSourceLayouts[numChannel - 1];
                AudioChannelLayoutTag dstTag = kMEAACDestinationLayouts[numChannel - 1];
                avacSrcLayout = [AVAudioChannelLayout layoutWithLayoutTag:srcTag];
                avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:dstTag];
            } else {
                SecureErrorLogf(@"Skipping audio track(%d) - unsupported channel count %d", track.trackID, numChannel);
                continue;
            }
        }
        
        if (!avacSrcLayout || !avacDstLayout) {
            // Fallback: try to create layouts based on channel count only
            if (numChannel >= 1 && numChannel <= 8) {
                AudioChannelLayoutTag fallbackTag = kMEAACDestinationLayouts[numChannel - 1];
                if (!avacSrcLayout) {
                    avacSrcLayout = [AVAudioChannelLayout layoutWithLayoutTag:fallbackTag];
                }
                if (!avacDstLayout) {
                    avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:fallbackTag];
                }
            }
        }
        
        if (!avacSrcLayout || !avacDstLayout) {
            SecureErrorLogf(@"Skipping audio track(%d) - channel layout creation failed", track.trackID);
            continue;
        }
        
        /* ========================================================================================== */
        
        // Prepare destination AudioChannelLayout data with proper size calculation
        UInt32 acDescCount = avacDstLayout.layout->mNumberChannelDescriptions;
        size_t acDescSize = sizeof(AudioChannelDescription);
        size_t acLayoutSize = sizeof(AudioChannelLayout) + (acDescCount > 1 ? (acDescCount - 1) * acDescSize : 0);
        NSData* aclData = [NSData dataWithBytes:avacDstLayout.layout length:acLayoutSize];

        // Destination writer settings
        NSMutableDictionary<NSString*,id>* awInputSetting = [NSMutableDictionary dictionary];
        awInputSetting[AVFormatIDKey] = @(self.audioFormatID);
        awInputSetting[AVSampleRateKey] = @(sampleRate);
        awInputSetting[AVNumberOfChannelsKey] = @(avacDstLayout.channelCount);
        awInputSetting[AVChannelLayoutKey] = aclData;
        awInputSetting[AVSampleRateConverterAlgorithmKey] = AVSampleRateConverterAlgorithm_Normal;
        if ([self.audioFourcc isEqualToString:@"lpcm"]) {
            awInputSetting[AVLinearPCMIsBigEndianKey] = @NO;
            awInputSetting[AVLinearPCMIsFloatKey] = @NO;
            awInputSetting[AVLinearPCMBitDepthKey] = @(self.lpcmDepth);
            awInputSetting[AVLinearPCMIsNonInterleavedKey] = @NO;
        } else {
            awInputSetting[AVEncoderBitRateKey] = @(self.audioBitRate);
            awInputSetting[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_LongTermAverage;
        }

        // Source reader settings (Float32 deinterleaved PCM as unified intermediate)
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        arOutputSetting[AVFormatIDKey] = @(kAudioFormatLinearPCM);
        arOutputSetting[AVLinearPCMIsFloatKey] = @YES;
        arOutputSetting[AVLinearPCMBitDepthKey] = @32;
        arOutputSetting[AVLinearPCMIsNonInterleavedKey] = @YES; // deinterleaved
        arOutputSetting[AVLinearPCMIsBigEndianKey] = @NO;

        // Unified bitrate adjustment (only when encoding)
        MEAdjustAudioBitrateIfNeeded(awInputSetting, avacDstLayout, sampleRate, self.audioBitRate); // unified bitrate adjustment

        // NOTE: Three formats involved:
        //   Reader Output: (src layout) Float32 deinterleaved
        //   Converter    : (dst layout) Float32 deinterleaved
        //   Writer Input : (dst layout) encoded / PCM

        AVAudioFormat* srcFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(double)sampleRate
                                                                             channelLayout:avacSrcLayout];
        AVAudioFormat* intermediateFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(double)sampleRate
                                                                                      channelLayout:avacDstLayout];
        AVAudioFormat* dstFormat = [[AVAudioFormat alloc] initWithSettings:awInputSetting];
        if (!srcFormat || !intermediateFormat || !dstFormat) {
            SecureErrorLogf(@"Skipping audio track(%d) - unsupported audio format detected", track.trackID);
            continue;
        }

        // Assign to converter

        
        // Configure the MEAudioConverter
        audioConverter.sourceFormat = srcFormat;
        audioConverter.destinationFormat = intermediateFormat;
        audioConverter.startTime = self.startTime;
        audioConverter.endTime = self.endTime;
        audioConverter.verbose = self.verbose;
        audioConverter.sourceExtensions = CMFormatDescriptionGetExtensions(desc);
        audioConverter.mediaTimeScale = track.naturalTimeScale;
        
        /* ========================================================================================== */
        
        // Create AVAssetReaderTrackOutput
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                   outputSettings:arOutputSetting];
        __block BOOL arOK = FALSE;
        dispatch_sync(self.processQueue, ^{
            arOK = [ar canAddOutput:arOutput];
        });
        if (!arOK) {
            SecureErrorLogf(@"Skipping audio track(%d) - reader output not supported", track.trackID);
            continue;
        }
        dispatch_sync(self.processQueue, ^{
            [ar addOutput:arOutput];
        });
        
        // Source channel: AVAssetReaderOutput -> MEAudioConverter (acting as MEInput)
        SBChannel* sbcMEInput = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                        consumerME:(MEInput*)audioConverter
                                                           TrackID:track.trackID];
        [self.sbChannels addObject:sbcMEInput];
        
        /* ========================================================================================== */
        
        // Create AVAssetWriterInput
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                         outputSettings:awInputSetting];
        __block BOOL awOK = FALSE;
        dispatch_sync(self.processQueue, ^{
            awOK = [aw canAddInput:awInput];
        });
        if (!awOK) {
            SecureErrorLogf(@"Skipping audio track(%d) - writer input not supported", track.trackID);
            continue;
        }
        dispatch_sync(self.processQueue, ^{
            [aw addInput:awInput];
        });
        
        // Destination channel: MEAudioConverter (acting as MEOutput) -> AVAssetWriterInput
        SBChannel* sbcMEOutput = [SBChannel sbChannelWithProducerME:(MEOutput*)audioConverter
                                                         consumerME:(MEInput*)awInput
                                                            TrackID:track.trackID];
        [self.sbChannels addObject:sbcMEOutput];
    }
}

- (void) prepareAudioMediaChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    if (self.audioEncode == FALSE) {
        [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeAudio];
        return;
    }
    
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeAudio]) {
        // source
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        arOutputSetting[AVFormatIDKey] = @(kAudioFormatLinearPCM);
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                   outputSettings:arOutputSetting];
        __block BOOL arOK = FALSE;
        dispatch_sync(self.processQueue, ^{
            arOK = [ar canAddOutput:arOutput];
        });
        if (!arOK) {
            SecureLogf(@"Skipping audio track(%d) - unsupported", track.trackID);
            continue;
        }
        dispatch_sync(self.processQueue, ^{
            [ar addOutput:arOutput];
        });
        
        // preserve original sampleRate, numChannel, and audioChannelLayout(best effort)
        int sampleRate = 0;
        int numChannel = 0;
        AVAudioChannelLayout* avacSrcLayout = nil;
        AVAudioChannelLayout* avacDstLayout = nil;
        NSData* aclData = nil;
        
        NSArray* descArray = track.formatDescriptions;
        CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef) descArray[0];
        
        const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc);
        if (!asbd) {
            SecureErrorLogf(@"Skipping audio track(%d) - no audio format description", track.trackID);
            continue;
        }
        
        sampleRate = (int)asbd->mSampleRate;
        numChannel = (int)asbd->mChannelsPerFrame;
        
        size_t srcAclSize = 0;
        const AudioChannelLayout* srcAclPtr = CMAudioFormatDescriptionGetChannelLayout(desc, &srcAclSize);
        if (srcAclPtr != NULL && srcAclSize > 0) {
            // Validate AudioChannelLayout
            AudioChannelLayoutTag srcTag = srcAclPtr->mChannelLayoutTag;
            AudioChannelLayoutTag dstTag = 0;
            if (self.audioChannelLayoutTag != 0) {
                dstTag = self.audioChannelLayoutTag;
            } else {
                UInt32 ioPropertyDataSize = 4;
                UInt32 outPropertyData = 0;
                OSStatus err = AudioFormatGetProperty(kAudioFormatProperty_NumberOfChannelsForLayout,
                                                      (UInt32)srcAclSize,
                                                      srcAclPtr,
                                                      &ioPropertyDataSize,
                                                      &outPropertyData);
                assert (!err && outPropertyData > 0);
                numChannel = (int)outPropertyData;
                
                if (AudioChannelLayoutTag_GetNumberOfChannels(srcTag)) {
                    // Request to respect LayoutTag for destination
                    dstTag = srcTag;
                } else {
                    // set of AudioChannelLabel(s), based on kAudioChannelLayoutTag_MPEG_*
                    NSSet* setCh1    = [NSSet setWithObjects:@(3), nil]; // C
                    NSSet* setCh2    = [NSSet setWithObjects:@(1),@(2), nil]; // L R
                    NSSet* setCh3    = [NSSet setWithObjects:@(1),@(2),@(3), nil]; // L R C
                    NSSet* setCh4    = [NSSet setWithObjects:@(1),@(2),@(3),@(9), nil]; // L R C Cs
                    NSSet* setCh5    = [NSSet setWithObjects:@(1),@(2),@(3),@(5),@(6), nil]; // L R C Ls Rs
                    NSSet* setCh51   = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6), nil]; // L R C LFE Ls Rs
                    NSSet* setCh61   = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6),@(9), nil]; // L R C LFE Ls Rs Cs
                    NSSet* setCh71AB = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6),@(7),@(8), nil]; // L R C LFE Ls Rs Lc Rc
                    NSSet* setCh71C  = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6),@(33),@(34), nil]; // L R C LFE Ls Rs Rls Rrs
                    
                    // set of AudioChannelLabel(s), based on kAudioChannelLayoutTag_AAC_*
                    NSSet* setAACQ   = [NSSet setWithObjects:@(1),@(2),@(5),@(6), nil]; // L R Ls Rs
                    NSSet* setAAC60  = [NSSet setWithObjects:@(1),@(2),@(3),@(5),@(6),@(9), nil]; // L R C Ls Rs Cs
                    NSSet* setAAC70  = [NSSet setWithObjects:@(1),@(2),@(3),@(5),@(6),@(33),@(34), nil]; // L R C Ls Rs Rls Rrs
                    NSSet* setAAC71C = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6),@(13),@(15), nil]; // L R C LFE Ls Rs Vhl Vhr
                    NSSet* setAACOct = [NSSet setWithObjects:@(1),@(2),@(3),@(5),@(6),@(9),@(33),@(34), nil]; // L R C Ls Rs Cs Rls Rrs
                    
                    if (srcTag == kAudioChannelLayoutTag_UseChannelBitmap) {
                        // prepare dictionaries for translation
                        NSDictionary<NSString*,NSNumber*>* bitmaps = @{
                            @"Left"                 : @(1U<<0 ), // L
                            @"Right"                : @(1U<<1 ), // R
                            @"Center"               : @(1U<<2 ), // C
                            @"LFEScreen"            : @(1U<<3 ), // LFE
                            @"LeftSurround"         : @(1U<<4 ), // Ls
                            @"RightSurround"        : @(1U<<5 ), // Rs
                            @"LeftCenter"           : @(1U<<6 ), // Lc
                            @"RightCenter"          : @(1U<<7 ), // Rc
                            @"CenterSurround"       : @(1U<<8 ), // Cs
                            @"LeftSurroundDirect"   : @(1U<<9 ), // Lsd
                            @"RightSurroundDirect"  : @(1U<<10), // Rsd
                            @"TopCenterSurround"    : @(1U<<11), // Ts
                            @"VerticalHeightLeft"   : @(1U<<12), // Vhl
                            @"VerticalHeightCenter" : @(1U<<13), // Vhc
                            @"VerticalHeightRight"  : @(1U<<14), // Vhr
                            @"TopBackLeft"          : @(1U<<15), //
                            @"TopBackCenter"        : @(1U<<16), //
                            @"TopBackRight"         : @(1U<<17), //
                        //  @"LeftTopFront"         : @(1U<<12), //
                        //  @"CenterTopFront"       : @(1U<<13), //
                        //  @"RightTopFront"        : @(1U<<14), //
                            @"LeftTopMiddle"        : @(1U<<21), // Ltm
                        //  @"CenterTopMiddle"      : @(1U<<11), //
                            @"RightTopMiddle"       : @(1U<<23), // Rtm
                            @"LeftTopRear"          : @(1U<<24), // Ltr
                            @"CenterTopRear"        : @(1U<<25), // Ctr
                            @"RightTopRear"         : @(1U<<26), // Rtr
                        };
                        NSDictionary<NSString*,NSNumber*>* labelsForBitmap = @{
                            @"Left"                 : @(1 ), // L
                            @"Right"                : @(2 ), // R
                            @"Center"               : @(3 ), // C
                            @"LFEScreen"            : @(4 ), // LFE
                            @"LeftSurround"         : @(5 ), // Ls
                            @"RightSurround"        : @(6 ), // Rs
                            @"LeftCenter"           : @(7 ), // Lc
                            @"RightCenter"          : @(8 ), // Rc
                            @"CenterSurround"       : @(9 ), // Cs
                            @"LeftSurroundDirect"   : @(10), // Lsd
                            @"RightSurroundDirect"  : @(11), // Rsd
                            @"TopCenterSurround"    : @(12), // Ts
                            @"VerticalHeightLeft"   : @(13), // Vhl
                            @"VerticalHeightCenter" : @(14), // Vhc
                            @"VerticalHeightRight"  : @(15), // Vhr
                            @"TopBackLeft"          : @(16), //
                            @"TopBackCenter"        : @(17), //
                            @"TopBackRight"         : @(18), //
                        //  @"LeftTopFront"         : @(13), //
                        //  @"CenterTopFront"       : @(14), //
                        //  @"RightTopFront"        : @(15), //
                            @"LeftTopMiddle"        : @(49), // Ltm
                        //  @"CenterTopMiddle"      : @(12), //
                            @"RightTopMiddle"       : @(51), // Rtm
                            @"LeftTopRear"          : @(52), // Ltr
                            @"CenterTopRear"        : @(53), // Ctr
                            @"RightTopRear"         : @(54), // Rtr
                        };
                        
                        // parse AudioChannelBitmap(s)
                        NSMutableSet* srcSet = [NSMutableSet new];
                        
                        AudioChannelBitmap map = srcAclPtr->mChannelBitmap;
                        for (NSString* name in bitmaps.allKeys) {
                            NSNumber* numBitmap = bitmaps[name];
                            if (numBitmap != nil) {
                                UInt32 testBit = numBitmap.unsignedIntValue;
                                if (map & testBit) {
                                    NSNumber* numLabel = labelsForBitmap[name];
                                    if (numLabel != nil) {
                                        [srcSet addObject: numLabel];
                                    }
                                }
                            }
                        }
                        
                        // Update numChannel w/ valid channel count
                        assert(srcSet.count); // No support for Lsd, Rsd, Rls, Rrs and any Top positions
                        numChannel = (int)srcSet.count;
                        
                        // get destination tag for AAC Transcode
                        if ([srcSet isEqualToSet:setCh1]) {
                            dstTag = kAudioChannelLayoutTag_Mono;       // kAudioChannelLayoutTag_MPEG_1_0
                        }
                        else if ([srcSet isEqualToSet:setCh2]) {
                            dstTag = kAudioChannelLayoutTag_Stereo;     // kAudioChannelLayoutTag_MPEG_2_0
                        }
                        else if ([srcSet isEqualToSet:setCh3]) {
                            dstTag = kAudioChannelLayoutTag_AAC_3_0;    // kAudioChannelLayoutTag_MPEG_3_0_B, 3_0_A
                        }
                        else if ([srcSet isEqualToSet:setCh4]) {
                            dstTag = kAudioChannelLayoutTag_AAC_4_0;    // kAudioChannelLayoutTag_MPEG_4_0_B, 4_0_A
                        }
                        else if ([srcSet isEqualToSet:setCh5]) {
                            dstTag = kAudioChannelLayoutTag_AAC_5_0;    // kAudioChannelLayoutTag_MPEG_5_0_D, 5_0_C/B/A
                        }
                        else if ([srcSet isEqualToSet:setCh51]) {
                            dstTag = kAudioChannelLayoutTag_AAC_5_1;    // kAudioChannelLayoutTag_MPEG_5_1_D, 5_1_C/B/A
                        }
                        else if ([srcSet isEqualToSet:setCh61]) {
                            dstTag = kAudioChannelLayoutTag_AAC_6_1;    // kAudioChannelLayoutTag_MPEG_6_1_A
                        }
                        else if ([srcSet isEqualToSet:setCh71AB]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1;    // kAudioChannelLayoutTag_MPEG_7_1_B, 7_1_A
                        }
                        else if ([srcSet isEqualToSet:setCh71C]) {
                            // No equivalent available: AudioChannelBitmap does not offer Rls/Rrs layout support.
                        }
                        else if ([srcSet isEqualToSet:setAACQ]) {
                            dstTag = kAudioChannelLayoutTag_AAC_Quadraphonic;
                        }
                        else if ([srcSet isEqualToSet:setAAC60]) {
                            dstTag = kAudioChannelLayoutTag_AAC_6_0;
                        }
                        else if ([srcSet isEqualToSet:setAAC70]) {
                            // No equivalent available: AudioChannelBitmap does not offer Rls/Rrs layout support.
                        }
                        else if ([srcSet isEqualToSet:setAAC71C]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1_C;
                        }
                        else if ([srcSet isEqualToSet:setAACOct]) {
                            // No equivalent available: AudioChannelBitmap does not offer Rls/Rrs layout support.
                        }
                        assert(dstTag);
                    }
                    
                    if (srcTag == kAudioChannelLayoutTag_UseChannelDescriptions) {
                        // parse AudioChannelDescription(s)
                        NSMutableSet* srcSet = [NSMutableSet new];
                        
                        UInt32 srcDescCount = srcAclPtr->mNumberChannelDescriptions;
                        size_t offset = offsetof(struct AudioChannelLayout, mChannelDescriptions);
                        AudioChannelDescription* descPtr = (AudioChannelDescription*)((char*)srcAclPtr + offset);
                        for (size_t desc = 0; desc < srcDescCount; desc++) {
                            AudioChannelLabel label = descPtr[desc].mChannelLabel;
                            if (label != kAudioChannelLabel_Unused && label != kAudioChannelLabel_UseCoordinates) {
                                [srcSet addObject: @(label)];
                            }
                        }
                        
                        // Update numChannel w/ valid channel count
                        assert(srcSet.count); // kAudioChannelLabel_UseCoordinates is not supported
                        numChannel = (int)srcSet.count;
                        
                        // get destination tag for AAC Transcode
                        if ([srcSet isEqualToSet:setCh1]) {
                            dstTag = kAudioChannelLayoutTag_Mono;       // kAudioChannelLayoutTag_MPEG_1_0
                        }
                        else if ([srcSet isEqualToSet:setCh2]) {
                            dstTag = kAudioChannelLayoutTag_Stereo;     // kAudioChannelLayoutTag_MPEG_2_0
                        }
                        else if ([srcSet isEqualToSet:setCh3]) {
                            dstTag = kAudioChannelLayoutTag_AAC_3_0;    // kAudioChannelLayoutTag_MPEG_3_0_B, 3_0_A
                        }
                        else if ([srcSet isEqualToSet:setCh4]) {
                            dstTag = kAudioChannelLayoutTag_AAC_4_0;    // kAudioChannelLayoutTag_MPEG_4_0_B, 4_0_A
                        }
                        else if ([srcSet isEqualToSet:setCh5]) {
                            dstTag = kAudioChannelLayoutTag_AAC_5_0;    // kAudioChannelLayoutTag_MPEG_5_0_D, 5_0_C/B/A
                        }
                        else if ([srcSet isEqualToSet:setCh51]) {
                            dstTag = kAudioChannelLayoutTag_AAC_5_1;    // kAudioChannelLayoutTag_MPEG_5_1_D, 5_1_C/B/A
                        }
                        else if ([srcSet isEqualToSet:setCh61]) {
                            dstTag = kAudioChannelLayoutTag_AAC_6_1;    // kAudioChannelLayoutTag_MPEG_6_1_A
                        }
                        else if ([srcSet isEqualToSet:setCh71AB]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1;    // kAudioChannelLayoutTag_MPEG_7_1_B, 7_1_A
                        }
                        else if ([srcSet isEqualToSet:setCh71C]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1_B;  // kAudioChannelLayoutTag_MPEG_7_1_C
                        }
                        else if ([srcSet isEqualToSet:setAACQ]) {
                            dstTag = kAudioChannelLayoutTag_AAC_Quadraphonic;
                        }
                        else if ([srcSet isEqualToSet:setAAC60]) {
                            dstTag = kAudioChannelLayoutTag_AAC_6_0;
                        }
                        else if ([srcSet isEqualToSet:setAAC70]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_0;
                        }
                        else if ([srcSet isEqualToSet:setAAC71C]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1_C;
                        }
                        else if ([srcSet isEqualToSet:setAACOct]) {
                            dstTag = kAudioChannelLayoutTag_AAC_Octagonal;
                        }
                        assert(dstTag);
                    }
                }
            }
            
            // For Source, use AudioChannelLayout* inside CMAudioFormatDescription
            avacSrcLayout = [AVAudioChannelLayout layoutWithLayout:srcAclPtr];
            // For Destination, use AudioChannelLayoutTag_AAC_*
            avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:dstTag];
        } else {
            // If acl is not available, use dummy layout (best effort)
        // BEGIN shared audio preparation (extracted)

            assert(0 < numChannel && numChannel <=8);
            
            // For Source (suppose MPEG layout)
            AudioChannelLayoutTag srcTag = kMEMPEGSourceLayouts[numChannel - 1];
            avacSrcLayout = [AVAudioChannelLayout layoutWithLayoutTag:srcTag];
            
            // For Destination (suppose AAC layout)
            AudioChannelLayoutTag dstTag = kMEAACDestinationLayouts[numChannel - 1];
            avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:dstTag];
        }
        
        // Prepare NSData* of destination layout
        UInt32 acDescCount = avacDstLayout.layout->mNumberChannelDescriptions;
        size_t acDescSize = sizeof(AudioChannelDescription);
        size_t acLayoutSize = sizeof(AudioChannelLayout)
                            + (acDescCount > 1 ? (acDescCount - 1) * acDescSize : 0);
        aclData = [NSData dataWithBytes:avacDstLayout.layout length:acLayoutSize];
        
        // destination settings
        NSMutableDictionary<NSString*,id>* awInputSetting = [NSMutableDictionary dictionary];
        awInputSetting[AVFormatIDKey] = @(self.audioFormatID);
        awInputSetting[AVSampleRateKey] = @(sampleRate);
        awInputSetting[AVNumberOfChannelsKey] = @(numChannel);
        awInputSetting[AVChannelLayoutKey] = aclData;
        awInputSetting[AVSampleRateConverterAlgorithmKey] = AVSampleRateConverterAlgorithm_Normal;
        if ([self.audioFourcc isEqualToString:@"lpcm"]) {
            awInputSetting[AVLinearPCMIsBigEndianKey] = @NO;
            awInputSetting[AVLinearPCMIsFloatKey] = @NO;
            awInputSetting[AVLinearPCMBitDepthKey] = @(self.lpcmDepth);
            awInputSetting[AVLinearPCMIsNonInterleavedKey] = @NO;
        } else {
            awInputSetting[AVEncoderBitRateKey] = @(self.audioBitRate);
            awInputSetting[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_LongTermAverage;
        }
        MEAdjustAudioBitrateIfNeeded(awInputSetting, avacDstLayout, sampleRate, self.audioBitRate);
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                         outputSettings:awInputSetting];
        // awInput.mediaTimeScale = track.naturalTimeScale; // Audio track is unable to change
        __block BOOL awOK = FALSE;
        dispatch_sync(self.processQueue, ^{
            awOK = [aw canAddInput:awInput];
        });
        if (!awOK) {
            SecureLogf(@"Skipping audio track(%d) - unsupported", track.trackID);
            continue;
        }
        dispatch_sync(self.processQueue, ^{
            [aw addInput:awInput];
        });
        
        // channel
        SBChannel* sbcAudio = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                      consumerME:(MEInput*)awInput
                                                         TrackID:track.trackID];
        [self.sbChannels addObject:sbcAudio];
    }
}

@end

NS_ASSUME_NONNULL_END
