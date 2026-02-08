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

@implementation METranscoder (prepareChannels)

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

// MARK: -

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
        size_t acLayoutSize = sizeof(AudioChannelLayout) + MIN(acDescCount - 1, 0) * acDescSize;
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
        MEAdjustAudioBitrateIfNeeded(awInputSetting, avacSrcLayout, sampleRate, self.audioBitRate);
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

// MARK: -

- (BOOL) hasFieldModeSupportOf:(AVMovieTrack*)track
{
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
            CFRelease(dict);
        }
    }

end:
    if (decompSession) {
        VTDecompressionSessionInvalidate(decompSession);
        CFRelease(decompSession);
    }
    return result;
}

- (void) addDecommpressionPropertiesOf:(AVMovieTrack*)track setting:(NSMutableDictionary*)arOutputSetting
{
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

- (NSMutableDictionary<NSString*,id>*)videoCompressionSettingFor:(AVMovieTrack *)track
{
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

- (void) prepareVideoChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    if (self.videoEncode == FALSE) {
        [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeVideo];
        return;
    }
    
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeVideo]) {
        // source
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        [self addDecommpressionPropertiesOf:track setting:arOutputSetting];
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
        CMFormatDescriptionRef desc =  (__bridge CMFormatDescriptionRef)track.formatDescriptions[0];
        CFDictionaryRef extensions =  CMFormatDescriptionGetExtensions(desc);
        mgr.sourceExtensions = extensions;
        
        int32_t ts = track.naturalTimeScale;
        mgr.mediaTimeScale = ts;
        
        // source from
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        [self addDecommpressionPropertiesOf:track setting:arOutputSetting];
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
