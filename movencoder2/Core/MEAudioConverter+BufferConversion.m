//
//  MEAudioConverter+BufferConversion.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MECommon.h"
#import "MEAudioConverter+BufferConversion.h"
#import "MESecureLogging.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation MEAudioConverter (BufferConversion)

- (nullable AVAudioPCMBuffer*) createPCMBufferFromSampleBuffer:(CMSampleBufferRef)sampleBuffer withFormat:(AVAudioFormat*)format
{
    AVAudioPCMBuffer *pcm = nil;
    AudioBufferList *abl = NULL;
    CMBlockBufferRef retainedBB = NULL;
    UInt32 bytesPerSample = 0;

    if (!sampleBuffer || !format) goto cleanup;
    if (format.streamDescription->mFormatID != kAudioFormatLinearPCM) goto cleanup;

    CMItemCount sampleCount = CMSampleBufferGetNumSamples(sampleBuffer);
    if (sampleCount <= 0) goto cleanup;

    // Basic consistency check with source ASBD (requires matching channel count and interleaving)
    CMAudioFormatDescriptionRef fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (!fmtDesc) goto cleanup;
    const AudioStreamBasicDescription *srcASBD = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc);
    if (!srcASBD) goto cleanup;

    BOOL srcIsInterleaved = ((srcASBD->mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0);
    if (srcASBD->mChannelsPerFrame != format.channelCount || srcIsInterleaved != format.isInterleaved) {
        goto cleanup; // Layout conversion is not handled in this function
    }

    // Query required size for AudioBufferList
    size_t ablSize = 0;
    OSStatus st = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer, &ablSize, NULL, 0, kCFAllocatorDefault, kCFAllocatorDefault, 0, NULL);
    if (st != noErr || ablSize == 0) goto cleanup;

    if (self.audioBufferListPool.length < ablSize) {
        [self.audioBufferListPool setLength:ablSize];
    }
    abl = (AudioBufferList*)[self.audioBufferListPool mutableBytes];
    memset(abl, 0, ablSize);
    st = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer,
                                                                 NULL,
                                                                 abl,
                                                                 ablSize,
                                                                 kCFAllocatorDefault,
                                                                 kCFAllocatorDefault,
                                                                 0,
                                                                 &retainedBB);
    if (st != noErr || abl->mNumberBuffers == 0) goto cleanup;

    // Create destination PCM buffer
    pcm = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                        frameCapacity:(AVAudioFrameCount)sampleCount];
    if (!pcm) goto cleanup;
    pcm.frameLength = (AVAudioFrameCount)sampleCount;

    const UInt32 ch = format.channelCount;
    AVAudioCommonFormat cf = format.commonFormat;

    switch (cf) {
        case AVAudioPCMFormatFloat32: bytesPerSample = sizeof(float); break;
        case AVAudioPCMFormatInt16:   bytesPerSample = sizeof(SInt16); break;
        case AVAudioPCMFormatInt32:   bytesPerSample = sizeof(SInt32); break;
        default: break;
    }
    if (bytesPerSample == 0 && format.streamDescription) {
        bytesPerSample = (UInt32)(format.streamDescription->mBitsPerChannel / 8);
    }
    if (bytesPerSample == 0) goto cleanup;

    if (format.isInterleaved) {
        const AudioBuffer src = abl->mBuffers[0];
        const AudioBufferList *dstABL = pcm.audioBufferList;
        if (!dstABL || dstABL->mNumberBuffers == 0) goto cleanup;
        AudioBuffer dst = dstABL->mBuffers[0];
        size_t dstBytes = (size_t)sampleCount * ch * bytesPerSample;
        size_t copyBytes = MIN(dstBytes, (size_t)src.mDataByteSize);
        copyBytes = MIN(copyBytes, (size_t)dst.mDataByteSize);
        if (dst.mData && src.mData && copyBytes) memcpy(dst.mData, src.mData, copyBytes);
    } else {
        UInt32 buffersToCopy = MIN(ch, abl->mNumberBuffers);
        const AudioBufferList *dstABL = pcm.audioBufferList;
        if (!dstABL || dstABL->mNumberBuffers == 0) goto cleanup;
        UInt32 dstBuffersToCopy = MIN(buffersToCopy, dstABL->mNumberBuffers);
        size_t bytesPerCh = (size_t)sampleCount * bytesPerSample;
        for (UInt32 i = 0; i < dstBuffersToCopy; i++) {
            const AudioBuffer src = abl->mBuffers[i];
            AudioBuffer dst = dstABL->mBuffers[i];
            size_t copyBytes = MIN(bytesPerCh, (size_t)src.mDataByteSize);
            copyBytes = MIN(copyBytes, (size_t)dst.mDataByteSize);
            if (dst.mData && src.mData && copyBytes) memcpy(dst.mData, src.mData, copyBytes);
        }
    }

cleanup:
    if (retainedBB) CFRelease(retainedBB);
    return pcm;
}

- (nullable CMSampleBufferRef) createSampleBufferFromPCMBuffer:(AVAudioPCMBuffer*)pcmBuffer
                                   withPresentationTimeStamp:(CMTime)pts
                                                      format:(AVAudioFormat*)format
                                             CF_RETURNS_RETAINED
{
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    CMAudioFormatDescriptionRef formatDesc = NULL;

    do {
        if (!pcmBuffer || !format) break;
        if (pcmBuffer.frameLength == 0) break;

        if (format.streamDescription->mFormatID != kAudioFormatLinearPCM) break;

        AVAudioFormat *srcFmt = pcmBuffer.format;
        if (srcFmt.channelCount != format.channelCount) break;
        if (srcFmt.isInterleaved != format.isInterleaved) break;
        if ((format.commonFormat == AVAudioPCMFormatFloat32 ||
             format.commonFormat == AVAudioPCMFormatInt16 ||
             format.commonFormat == AVAudioPCMFormatInt32) &&
            srcFmt.commonFormat != format.commonFormat) {
            break;
        }

        UInt32 bytesPerSample = 0;
        switch (format.commonFormat) {
            case AVAudioPCMFormatFloat32: bytesPerSample = sizeof(float); break;
            case AVAudioPCMFormatInt16:   bytesPerSample = sizeof(SInt16); break;
            case AVAudioPCMFormatInt32:   bytesPerSample = sizeof(SInt32); break;
            default: break;
        }
        if (bytesPerSample == 0 && format.streamDescription) {
            bytesPerSample = (UInt32)(format.streamDescription->mBitsPerChannel / 8);
        }
        if (bytesPerSample == 0) break;

        const AVAudioFrameCount frames = pcmBuffer.frameLength;
        const UInt32 channels = format.channelCount;
        const size_t totalBytes = (size_t)frames * bytesPerSample * channels;

        OSStatus st = CMBlockBufferCreateWithMemoryBlock(
            kCFAllocatorDefault, NULL, totalBytes, kCFAllocatorDefault, NULL, 0, totalBytes,
            kCMBlockBufferAssureMemoryNowFlag,
            &blockBuffer);
        if (st != noErr || !blockBuffer) break;

        char *dstBase = NULL;
        st = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, NULL, &dstBase);
        if (st != noErr || !dstBase) break;

        const AudioBufferList *srcABL = pcmBuffer.audioBufferList;
        if (!srcABL || srcABL->mNumberBuffers == 0) break;
        if (format.isInterleaved) {
            size_t copyBytes = (size_t)frames * bytesPerSample * channels;
            const AudioBuffer src = srcABL->mBuffers[0];
            if (src.mData && copyBytes) memcpy(dstBase, src.mData, MIN(copyBytes, (size_t)src.mDataByteSize));
        } else {
            size_t bytesPerChannel = (size_t)frames * bytesPerSample;
            UInt32 buffersToCopy = MIN(channels, srcABL->mNumberBuffers);
            for (UInt32 ch = 0; ch < buffersToCopy; ch++) {
                char *dstCh = dstBase + ch * bytesPerChannel;
                const AudioBuffer src = srcABL->mBuffers[ch];
                size_t copyBytes = MIN(bytesPerChannel, (size_t)src.mDataByteSize);
                if (src.mData && copyBytes) memcpy(dstCh, src.mData, copyBytes);
            }
        }

        AudioStreamBasicDescription asbd = *format.streamDescription;
        const AudioChannelLayout *layout = NULL;
        size_t layoutSize = 0;
        if (format.channelLayout) {
            layout = format.channelLayout.layout;
            if (layout) {
                layoutSize = sizeof(AudioChannelLayout);
                if (layout->mNumberChannelDescriptions > 1) {
                    layoutSize += (layout->mNumberChannelDescriptions - 1) * sizeof(AudioChannelDescription);
                }
            }
        }

        st = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, layoutSize, layout, 0, NULL, NULL, &formatDesc);
        if (st != noErr || !formatDesc) break;

        double sr = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000.0;
        int32_t timeScale = (int32_t)llround(sr);
        if (timeScale <= 0) timeScale = 48000;
        CMSampleTimingInfo timing = {
            .duration = CMTimeMake(1, timeScale),
            .presentationTimeStamp = pts,
            .decodeTimeStamp = kCMTimeInvalid
        };

        st = CMSampleBufferCreate(kCFAllocatorDefault,
                                  blockBuffer,
                                  true,
                                  NULL,
                                  NULL,
                                  formatDesc,
                                  frames,
                                  1,
                                  &timing,
                                  0,
                                  NULL,
                                  &sampleBuffer);
        if (st != noErr) {
            sampleBuffer = NULL;
        } else {
            blockBuffer = NULL;
        }
    } while (0);

    if (blockBuffer) CFRelease(blockBuffer);
    if (formatDesc) CFRelease(formatDesc);
    return sampleBuffer;
}

@end

NS_ASSUME_NONNULL_END
