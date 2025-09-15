//
//  MEAudioConverter.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
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
#import "MEAudioConverter.h"
#include <unistd.h>

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEAudioConverter ()
{
    dispatch_queue_t _inputQueue;
    dispatch_queue_t _outputQueue;
    
    // Input side
    NSMutableArray* _inputBufferQueue;
    BOOL _inputFinished;
    RequestHandler _inputRequestHandler;
    dispatch_queue_t _inputRequestQueue;
    
    // Output side
    NSMutableArray* _outputBufferQueue;
    BOOL _outputFinished;
    dispatch_semaphore_t _outputDataSemaphore;
    
    // Converter
    AVAudioConverter* _audioConverter;
}

/**
 * Apply volume/gain to an AVAudioPCMBuffer based on volumeDb property
 */
- (void)applyVolumeToBuffer:(AVAudioPCMBuffer*)buffer;

@property (assign) BOOL failed;                       // atomic override
@property (assign) AVAssetWriterStatus writerStatus;  // atomic override
@property (assign) AVAssetReaderStatus readerStatus;  // atomic override
@property (strong, nonatomic) NSMutableData *audioBufferListPool;

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation MEAudioConverter

@synthesize mediaTimeScale;

- (instancetype)init
{
    if (self = [super init]) {
        _inputQueue = dispatch_queue_create("MEAudioConverter.input", DISPATCH_QUEUE_SERIAL);
        _outputQueue = dispatch_queue_create("MEAudioConverter.output", DISPATCH_QUEUE_SERIAL);
        
        _inputBufferQueue = [NSMutableArray array];
        _outputBufferQueue = [NSMutableArray array];
        
        _inputFinished = NO;
        _outputFinished = NO;
        
        // Initialize semaphore for output data availability signaling
        _outputDataSemaphore = dispatch_semaphore_create(0);
        
        self.writerStatus = AVAssetWriterStatusUnknown;
        self.readerStatus = AVAssetReaderStatusUnknown;
        self.failed = NO;
        
        self.startTime = kCMTimeInvalid;
        self.endTime = kCMTimeInvalid;
        
        self.maxInputBufferCount = 10;
        
        self.audioBufferListPool = [NSMutableData data];
    }
    return self;
}

- (void)dealloc
{
    [self cleanup];
    
    // Release semaphore if it exists
    if (_outputDataSemaphore) {
        // Signal any waiting threads before release to prevent deadlock
        dispatch_semaphore_signal(_outputDataSemaphore);
        _outputDataSemaphore = nil;
    }
}

- (void)cleanup
{
    // Use dispatch_async for cleanup to prevent deadlock between input and output queues
    dispatch_async(_inputQueue, ^{
        for (NSValue* value in _inputBufferQueue) {
            CMSampleBufferRef sampleBuffer = (CMSampleBufferRef)[value pointerValue];
            if (sampleBuffer) {
                CFRelease(sampleBuffer);
            }
        }
        [_inputBufferQueue removeAllObjects];
    });
    
    dispatch_async(_outputQueue, ^{
        for (NSValue* value in _outputBufferQueue) {
            CMSampleBufferRef sampleBuffer = (CMSampleBufferRef)[value pointerValue];
            if (sampleBuffer) {
                CFRelease(sampleBuffer);
            }
        }
        [_outputBufferQueue removeAllObjects];
    });
}

- (AVMediaType)mediaType
{
    return AVMediaTypeAudio;
}

/* =================================================================================== */
// MARK: - Helper methods for PCM buffer conversion
/* =================================================================================== */

- (nullable AVAudioPCMBuffer*) createPCMBufferFromSampleBuffer:(CMSampleBufferRef)sampleBuffer withFormat:(AVAudioFormat*)format
{
    AVAudioPCMBuffer *pcm = nil;
    AudioBufferList *abl = NULL;
    CMBlockBufferRef retainedBB = NULL;

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

    if (format.isInterleaved) {
        const AudioBuffer src = abl->mBuffers[0];
        switch (cf) {
            case AVAudioPCMFormatFloat32: {
                float *dst = pcm.floatChannelData[0];
                size_t dstBytes = (size_t)sampleCount * ch * sizeof(float);
                size_t copyBytes = MIN(dstBytes, (size_t)src.mDataByteSize);
                if (dst && src.mData && copyBytes) memcpy(dst, src.mData, copyBytes);
            } break;
            case AVAudioPCMFormatInt16: {
                SInt16 *dst = pcm.int16ChannelData[0];
                size_t dstBytes = (size_t)sampleCount * ch * sizeof(SInt16);
                size_t copyBytes = MIN(dstBytes, (size_t)src.mDataByteSize);
                if (dst && src.mData && copyBytes) memcpy(dst, src.mData, copyBytes);
            } break;
            case AVAudioPCMFormatInt32: {
                SInt32 *dst = pcm.int32ChannelData[0];
                size_t dstBytes = (size_t)sampleCount * ch * sizeof(SInt32);
                size_t copyBytes = MIN(dstBytes, (size_t)src.mDataByteSize);
                if (dst && src.mData && copyBytes) memcpy(dst, src.mData, copyBytes);
            } break;
            default:
                pcm = nil; goto cleanup;
        }
    } else {
        UInt32 buffersToCopy = MIN(ch, abl->mNumberBuffers);
        switch (cf) {
            case AVAudioPCMFormatFloat32: {
                size_t bytesPerCh = (size_t)sampleCount * sizeof(float);
                for (UInt32 i = 0; i < buffersToCopy; i++) {
                    float *dst = pcm.floatChannelData[i];
                    const AudioBuffer src = abl->mBuffers[i];
                    size_t copyBytes = MIN(bytesPerCh, (size_t)src.mDataByteSize);
                    if (dst && src.mData && copyBytes) memcpy(dst, src.mData, copyBytes);
                }
            } break;
            case AVAudioPCMFormatInt16: {
                size_t bytesPerCh = (size_t)sampleCount * sizeof(SInt16);
                for (UInt32 i = 0; i < buffersToCopy; i++) {
                    SInt16 *dst = pcm.int16ChannelData[i];
                    const AudioBuffer src = abl->mBuffers[i];
                    size_t copyBytes = MIN(bytesPerCh, (size_t)src.mDataByteSize);
                    if (dst && src.mData && copyBytes) memcpy(dst, src.mData, copyBytes);
                }
            } break;
            case AVAudioPCMFormatInt32: {
                size_t bytesPerCh = (size_t)sampleCount * sizeof(SInt32);
                for (UInt32 i = 0; i < buffersToCopy; i++) {
                    SInt32 *dst = pcm.int32ChannelData[i];
                    const AudioBuffer src = abl->mBuffers[i];
                    size_t copyBytes = MIN(bytesPerCh, (size_t)src.mDataByteSize);
                    if (dst && src.mData && copyBytes) memcpy(dst, src.mData, copyBytes);
                }
            } break;
            default:
                pcm = nil; goto cleanup;
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
        if (srcFmt.commonFormat != format.commonFormat) break;

        UInt32 bytesPerSample = 0;
        switch (format.commonFormat) {
            case AVAudioPCMFormatFloat32: bytesPerSample = sizeof(float); break;
            case AVAudioPCMFormatInt16:   bytesPerSample = sizeof(SInt16); break;
            case AVAudioPCMFormatInt32:   bytesPerSample = sizeof(SInt32); break;
            default: break;
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

        if (format.isInterleaved) {
            size_t copyBytes = (size_t)frames * bytesPerSample * channels;
            switch (format.commonFormat) {
                case AVAudioPCMFormatFloat32:
                    if (pcmBuffer.floatChannelData && pcmBuffer.floatChannelData[0]) {
                        memcpy(dstBase, pcmBuffer.floatChannelData[0], copyBytes);
                    }
                    break;
                case AVAudioPCMFormatInt16:
                    if (pcmBuffer.int16ChannelData && pcmBuffer.int16ChannelData[0]) {
                        memcpy(dstBase, pcmBuffer.int16ChannelData[0], copyBytes);
                    }
                    break;
                case AVAudioPCMFormatInt32:
                    if (pcmBuffer.int32ChannelData && pcmBuffer.int32ChannelData[0]) {
                        memcpy(dstBase, pcmBuffer.int32ChannelData[0], copyBytes);
                    }
                    break;
                default:
                    break;
            }
        } else {
            size_t bytesPerChannel = (size_t)frames * bytesPerSample;
            for (UInt32 ch = 0; ch < channels; ch++) {
                char *dstCh = dstBase + ch * bytesPerChannel;
                switch (format.commonFormat) {
                    case AVAudioPCMFormatFloat32:
                        if (pcmBuffer.floatChannelData && pcmBuffer.floatChannelData[ch]) {
                            memcpy(dstCh, pcmBuffer.floatChannelData[ch], bytesPerChannel);
                        }
                        break;
                    case AVAudioPCMFormatInt16:
                        if (pcmBuffer.int16ChannelData && pcmBuffer.int16ChannelData[ch]) {
                            memcpy(dstCh, pcmBuffer.int16ChannelData[ch], bytesPerChannel);
                        }
                        break;
                    case AVAudioPCMFormatInt32:
                        if (pcmBuffer.int32ChannelData && pcmBuffer.int32ChannelData[ch]) {
                            memcpy(dstCh, pcmBuffer.int32ChannelData[ch], bytesPerChannel);
                        }
                        break;
                    default:
                        break;
                }
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

/* =================================================================================== */
// MARK: - MEInput interface (consumer side)
/* =================================================================================== */

- (BOOL)appendSampleBuffer:(CMSampleBufferRef)sb
{
    if (_inputFinished || self.failed) {
        return NO;
    }
    
    __block BOOL success = YES;
    dispatch_sync(_inputQueue, ^{
        // Store the sample buffer for processing
        CFRetain(sb);
        NSValue* value = [NSValue valueWithPointer:sb];
        [_inputBufferQueue addObject:value];
        
        // Trigger processing if converter is available
        if (_audioConverter && self.sourceFormat && self.destinationFormat) {
            [self processNextBuffer];
        }
    });
    
    return success;
}

- (BOOL)isReadyForMoreMediaData
{
    if (_inputFinished || self.failed) {
        return NO;
    }
    
    // Limit queue size to prevent memory issues
    NSUInteger limit = self.maxInputBufferCount;
    __block BOOL ready;
    dispatch_sync(_inputQueue, ^{
        ready = (limit > 0) ? (_inputBufferQueue.count < limit) : NO;
    });
    return ready;
}

- (void)markAsFinished
{
    dispatch_sync(_inputQueue, ^{
        _inputFinished = YES;
        // Process any remaining buffers
        while (_inputBufferQueue.count > 0 && _audioConverter) {
            [self processNextBuffer];
        }
        
        // Signal semaphore to unblock any waiting threads
        dispatch_semaphore_signal(_outputDataSemaphore);
    });
    
    // Mark output as finished separately to avoid nested dispatch_sync deadlock
    dispatch_async(_outputQueue, ^{
        _outputFinished = YES;
    });
}

- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block
{
    dispatch_sync(_inputQueue, ^{
        _inputRequestQueue = queue;
        _inputRequestHandler = [block copy];
        
        // Initialize the audio converter if not already done
        if (!_audioConverter && self.sourceFormat && self.destinationFormat) {
            _audioConverter = [[AVAudioConverter alloc] initFromFormat:self.sourceFormat toFormat:self.destinationFormat];
            if (!_audioConverter) {
                self.failed = YES;
                if (self.verbose) {
                    NSLog(@"[MEAudioConverter] Failed to create AVAudioConverter");
                }
                return;
            }
        }
        
        // Start the processing loop
        if (_inputRequestQueue && _inputRequestHandler) {
            dispatch_async(_inputRequestQueue, _inputRequestHandler);
        }
    });
}

- (void)processNextBuffer
{
    if (_inputBufferQueue.count == 0 || !_audioConverter) {
        return;
    }
    
    NSValue* value = _inputBufferQueue.firstObject;
    [_inputBufferQueue removeObjectAtIndex:0];
    
    CMSampleBufferRef inputSampleBuffer = (CMSampleBufferRef)[value pointerValue];
    
    @autoreleasepool {
        // Convert to AVAudioPCMBuffer
        AVAudioPCMBuffer* inputPCMBuffer = [self createPCMBufferFromSampleBuffer:inputSampleBuffer withFormat:self.sourceFormat];
        if (inputPCMBuffer) {
            // Convert using AVAudioConverter
            AVAudioPCMBuffer* outputPCMBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self.destinationFormat frameCapacity:inputPCMBuffer.frameLength];
            if (outputPCMBuffer) {
                NSError* convertError = nil;
                outputPCMBuffer.frameLength = outputPCMBuffer.frameCapacity;
                
                __block BOOL inputBufferProvided = NO;
                AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus * _Nonnull outStatus) {
                    if (!inputBufferProvided) {
                        inputBufferProvided = YES;
                        *outStatus = AVAudioConverterInputStatus_HaveData;
                        return inputPCMBuffer;
                    } else {
                        *outStatus = AVAudioConverterInputStatus_NoDataNow;
                        return nil;
                    }
                };
                
                AVAudioConverterOutputStatus convertStatus = [_audioConverter convertToBuffer:outputPCMBuffer
                                                                                         error:&convertError
                                                                            withInputFromBlock:inputBlock];
                
                if (convertStatus == AVAudioConverterOutputStatus_HaveData) {
                    // Apply volume/gain adjustment if specified
                    [self applyVolumeToBuffer:outputPCMBuffer];
                    
                    // Rebuild CMSampleBuffer
                    CMTime pts = CMSampleBufferGetPresentationTimeStamp(inputSampleBuffer);
                    CMSampleBufferRef outputSampleBuffer = [self createSampleBufferFromPCMBuffer:outputPCMBuffer
                                                                       withPresentationTimeStamp:pts
                                                                                          format:self.destinationFormat];
                    if (outputSampleBuffer) {
                        // Add to output queue using async to prevent deadlock
                        dispatch_async(_outputQueue, ^{
                            NSValue* outputValue = [NSValue valueWithPointer:outputSampleBuffer];
                            [_outputBufferQueue addObject:outputValue];
                            
                            // Signal that new data is available
                            dispatch_semaphore_signal(_outputDataSemaphore);
                        });
                    }
                } else if (convertError) {
                    if (self.verbose) {
                        NSLog(@"[MEAudioConverter] Audio conversion error: %@", convertError);
                    }
                    self.failed = YES;
                }
            }
        }
    }
    
    CFRelease(inputSampleBuffer);
    
    // Continue processing if there are more buffers and request handler is available
    if (_inputBufferQueue.count > 0 && _inputRequestQueue && _inputRequestHandler) {
        dispatch_async(_inputRequestQueue, _inputRequestHandler);
    }
}

/* =================================================================================== */
// MARK: - MEOutput interface (producer side)
/* =================================================================================== */

- (nullable CMSampleBufferRef)copyNextSampleBuffer
{
    if (self.failed) {
        return NULL;
    }
    
    __block CMSampleBufferRef result = NULL;
    
    // Wait for data to become available or input to finish
    while (!self.failed) {
        // Check if data is immediately available
        dispatch_sync(_outputQueue, ^{
            if (_outputBufferQueue.count > 0) {
                NSValue* value = _outputBufferQueue.firstObject;
                [_outputBufferQueue removeObjectAtIndex:0];
                result = (CMSampleBufferRef)[value pointerValue];
                // Don't release here as this method should return a retained reference
            } else if (_inputFinished) {
                // Only return NULL when input is finished and no more buffers available
                result = NULL;
            }
        });
        
        // If we have a result (either data or NULL indicating end), return it
        if (result != NULL || _inputFinished) {
            break;
        }
        
        // Wait for semaphore signal indicating new data is available
        // Use a timeout to periodically check for failure state
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC); // 50ms timeout
        dispatch_semaphore_wait(_outputDataSemaphore, timeout);
        
        // Continue the loop to check for data availability and failure state
    }
    
    return result;
}

/* =================================================================================== */
// MARK: - Volume/Gain Control
/* =================================================================================== */

- (void)applyVolumeToBuffer:(AVAudioPCMBuffer*)buffer
{
    if (!buffer || self.volumeDb == 0.0) {
        return; // No volume adjustment needed
    }
    
    // Convert dB to linear multiplier: multiplier = 10^(dB/20)
    double volumeMultiplier = pow(10.0, self.volumeDb / 20.0);
    
    AVAudioFrameCount frameCount = buffer.frameLength;
    UInt32 channelCount = buffer.format.channelCount;
    
    switch (buffer.format.commonFormat) {
        case AVAudioPCMFormatFloat32: {
            if (buffer.format.isInterleaved) {
                // Interleaved format
                float* data = buffer.floatChannelData[0];
                for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                    for (UInt32 ch = 0; ch < channelCount; ch++) {
                        data[frame * channelCount + ch] *= volumeMultiplier;
                    }
                }
            } else {
                // Non-interleaved format
                for (UInt32 ch = 0; ch < channelCount; ch++) {
                    float* channelData = buffer.floatChannelData[ch];
                    if (channelData) {
                        for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                            channelData[frame] *= volumeMultiplier;
                        }
                    }
                }
            }
            break;
        }
        case AVAudioPCMFormatInt16: {
            if (buffer.format.isInterleaved) {
                // Interleaved format
                SInt16* data = buffer.int16ChannelData[0];
                for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                    for (UInt32 ch = 0; ch < channelCount; ch++) {
                        double sample = data[frame * channelCount + ch];
                        sample *= volumeMultiplier;
                        // Clamp to prevent overflow
                        if (sample > 32767.0) sample = 32767.0;
                        if (sample < -32768.0) sample = -32768.0;
                        data[frame * channelCount + ch] = (SInt16)sample;
                    }
                }
            } else {
                // Non-interleaved format
                for (UInt32 ch = 0; ch < channelCount; ch++) {
                    SInt16* channelData = buffer.int16ChannelData[ch];
                    if (channelData) {
                        for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                            double sample = channelData[frame];
                            sample *= volumeMultiplier;
                            // Clamp to prevent overflow
                            if (sample > 32767.0) sample = 32767.0;
                            if (sample < -32768.0) sample = -32768.0;
                            channelData[frame] = (SInt16)sample;
                        }
                    }
                }
            }
            break;
        }
        case AVAudioPCMFormatInt32: {
            if (buffer.format.isInterleaved) {
                // Interleaved format
                SInt32* data = buffer.int32ChannelData[0];
                for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                    for (UInt32 ch = 0; ch < channelCount; ch++) {
                        double sample = data[frame * channelCount + ch];
                        sample *= volumeMultiplier;
                        // Clamp to prevent overflow
                        if (sample > 2147483647.0) sample = 2147483647.0;
                        if (sample < -2147483648.0) sample = -2147483648.0;
                        data[frame * channelCount + ch] = (SInt32)sample;
                    }
                }
            } else {
                // Non-interleaved format
                for (UInt32 ch = 0; ch < channelCount; ch++) {
                    SInt32* channelData = buffer.int32ChannelData[ch];
                    if (channelData) {
                        for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                            double sample = channelData[frame];
                            sample *= volumeMultiplier;
                            // Clamp to prevent overflow
                            if (sample > 2147483647.0) sample = 2147483647.0;
                            if (sample < -2147483648.0) sample = -2147483648.0;
                            channelData[frame] = (SInt32)sample;
                        }
                    }
                }
            }
            break;
        }
        default:
            // Unsupported format, log warning
            if (self.verbose) {
                NSLog(@"[MEAudioConverter] Volume adjustment not supported for format: %d", (int)buffer.format.commonFormat);
            }
            break;
    }
}

@end

NS_ASSUME_NONNULL_END
