//
//  MEAudioConverter.m
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

#import "MEAudioConverter.h"

#ifndef ALog
#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NSString* const kProgressMediaTypeKey = @"mediaType";
NSString* const kProgressTagKey = @"tag";
NSString* const kProgressTrackIDKey = @"trackID";
NSString* const kProgressPTSKey = @"pts";
NSString* const kProgressDTSKey = @"dts";
NSString* const kProgressPercentKey = @"percent";
NSString* const kProgressCountKey = @"count";

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEAudioConverter ()
{
    dispatch_queue_t _inputQueue;
    dispatch_queue_t _outputQueue;
    
    // Input side
    NSMutableArray<CMSampleBufferRef>* _inputBufferQueue;
    BOOL _inputFinished;
    RequestHandler _inputRequestHandler;
    dispatch_queue_t _inputRequestQueue;
    
    // Output side
    NSMutableArray<CMSampleBufferRef>* _outputBufferQueue;
    BOOL _outputFinished;
    
    // Converter
    AVAudioConverter* _audioConverter;
}

@property (assign) BOOL failed;                       // atomic override
@property (assign) AVAssetWriterStatus writerStatus;  // atomic override
@property (assign) AVAssetReaderStatus readerStatus;  // atomic override

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
        
        self.writerStatus = AVAssetWriterStatusUnknown;
        self.readerStatus = AVAssetReaderStatusUnknown;
        self.failed = NO;
        
        self.startTime = kCMTimeInvalid;
        self.endTime = kCMTimeInvalid;
    }
    return self;
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    dispatch_sync(_inputQueue, ^{
        for (NSValue* value in _inputBufferQueue) {
            CMSampleBufferRef sampleBuffer = (CMSampleBufferRef)[value pointerValue];
            if (sampleBuffer) {
                CFRelease(sampleBuffer);
            }
        }
        [_inputBufferQueue removeAllObjects];
    });
    
    dispatch_sync(_outputQueue, ^{
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
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuffer) return nil;
    
    size_t totalLength = CMBlockBufferGetDataLength(blockBuffer);
    if (totalLength == 0) return nil;
    
    // Get audio buffer list from sample buffer
    AudioBufferList audioBufferList;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer, NULL, &audioBufferList, sizeof(audioBufferList), 
        kCFAllocatorDefault, kCFAllocatorDefault, 0, NULL);
    
    if (audioBufferList.mNumberBuffers == 0) return nil;
    
    // Get frame count from sample buffer
    CMItemCount sampleCount = CMSampleBufferGetNumSamples(sampleBuffer);
    
    // Create PCM buffer with the target format
    AVAudioPCMBuffer* pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(AVAudioFrameCount)sampleCount];
    if (!pcmBuffer) return nil;
    
    pcmBuffer.frameLength = (AVAudioFrameCount)sampleCount;
    
    // Copy data based on format
    if (format.isInterleaved) {
        // Interleaved format - copy all channel data sequentially
        float* destPtr = pcmBuffer.floatChannelData[0];
        if (audioBufferList.mBuffers[0].mData) {
            if (audioBufferList.mBuffers[0].mDataByteSize >= sampleCount * format.channelCount * sizeof(float)) {
                memcpy(destPtr, audioBufferList.mBuffers[0].mData, sampleCount * format.channelCount * sizeof(float));
            }
        }
    } else {
        // Non-interleaved format - copy each channel separately
        for (UInt32 channel = 0; channel < format.channelCount && channel < audioBufferList.mNumberBuffers; channel++) {
            float* destPtr = pcmBuffer.floatChannelData[channel];
            if (audioBufferList.mBuffers[channel].mData) {
                if (audioBufferList.mBuffers[channel].mDataByteSize >= sampleCount * sizeof(float)) {
                    memcpy(destPtr, audioBufferList.mBuffers[channel].mData, sampleCount * sizeof(float));
                }
            }
        }
    }
    
    return pcmBuffer;
}

- (nullable CMSampleBufferRef) createSampleBufferFromPCMBuffer:(AVAudioPCMBuffer*)pcmBuffer withPresentationTimeStamp:(CMTime)pts format:(AVAudioFormat*)format CF_RETURNS_RETAINED
{
    if (!pcmBuffer || !format || pcmBuffer.frameLength == 0) return NULL;
    
    AVAudioFrameCount frameCount = pcmBuffer.frameLength;
    UInt32 channelCount = format.channelCount;
    UInt32 bytesPerFrame = channelCount * sizeof(float);
    UInt32 totalBytes = frameCount * bytesPerFrame;
    
    // Create audio buffer list
    AudioBufferList* audioBufferList = malloc(sizeof(AudioBufferList) + (channelCount - 1) * sizeof(AudioBuffer));
    if (!audioBufferList) return NULL;
    
    // Allocate block buffer
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault,
        NULL,  // Use allocated memory
        totalBytes,
        kCFAllocatorDefault,
        NULL,  // No custom block source
        0,     // Offset into block
        totalBytes,
        0,     // Flags
        &blockBuffer);
    
    if (status != noErr) {
        free(audioBufferList);
        return NULL;
    }
    
    // Get pointer to block buffer data
    char* dataPtr = NULL;
    status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, NULL, &dataPtr);
    if (status != noErr) {
        CFRelease(blockBuffer);
        free(audioBufferList);
        return NULL;
    }
    
    if (format.isInterleaved) {
        // Interleaved format
        audioBufferList->mNumberBuffers = 1;
        audioBufferList->mBuffers[0].mNumberChannels = channelCount;
        audioBufferList->mBuffers[0].mDataByteSize = totalBytes;
        audioBufferList->mBuffers[0].mData = dataPtr;
        
        // Copy interleaved data
        memcpy(dataPtr, pcmBuffer.floatChannelData[0], totalBytes);
    } else {
        // Non-interleaved format
        audioBufferList->mNumberBuffers = channelCount;
        UInt32 bytesPerChannel = frameCount * sizeof(float);
        
        for (UInt32 channel = 0; channel < channelCount; channel++) {
            audioBufferList->mBuffers[channel].mNumberChannels = 1;
            audioBufferList->mBuffers[channel].mDataByteSize = bytesPerChannel;
            audioBufferList->mBuffers[channel].mData = dataPtr + (channel * bytesPerChannel);
            
            // Copy channel data
            memcpy(audioBufferList->mBuffers[channel].mData, pcmBuffer.floatChannelData[channel], bytesPerChannel);
        }
    }
    
    // Create audio format description
    AudioStreamBasicDescription asbd = *format.streamDescription;
    CMAudioFormatDescriptionRef formatDesc = NULL;
    
    size_t layoutSize = 0;
    const AudioChannelLayout* layout = NULL;
    if (format.channelLayout) {
        layout = format.channelLayout.layout;
        UInt32 acDescCount = layout->mNumberChannelDescriptions;
        layoutSize = sizeof(AudioChannelLayout) + (acDescCount > 1 ? (acDescCount - 1) * sizeof(AudioChannelDescription) : 0);
    }
    
    status = CMAudioFormatDescriptionCreate(
        kCFAllocatorDefault,
        &asbd,
        layoutSize,
        layout,
        0,
        NULL,
        NULL,
        &formatDesc);
    
    if (status != noErr) {
        CFRelease(blockBuffer);
        free(audioBufferList);
        return NULL;
    }
    
    // Create sample buffer
    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreate(
        kCFAllocatorDefault,
        blockBuffer,
        TRUE,  // dataReady
        NULL,  // makeDataReadyCallback
        NULL,  // makeDataReadyRefcon
        formatDesc,
        frameCount,  // numSamples
        1,     // numSampleTimingEntries
        &(CMSampleTimingInfo){.duration = CMTimeMake(1, format.sampleRate), .presentationTimeStamp = pts, .decodeTimeStamp = kCMTimeInvalid},
        0,     // numSampleSizeEntries
        NULL,  // sampleSizeArray
        &sampleBuffer);
    
    // Cleanup
    CFRelease(blockBuffer);
    CFRelease(formatDesc);
    free(audioBufferList);
    
    return status == noErr ? sampleBuffer : NULL;
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
    __block BOOL ready;
    dispatch_sync(_inputQueue, ^{
        ready = (_inputBufferQueue.count < 10);
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
        // Mark output as finished
        dispatch_sync(_outputQueue, ^{
            _outputFinished = YES;
        });
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
                    // Rebuild CMSampleBuffer
                    CMTime pts = CMSampleBufferGetPresentationTimeStamp(inputSampleBuffer);
                    CMSampleBufferRef outputSampleBuffer = [self createSampleBufferFromPCMBuffer:outputPCMBuffer 
                                                                         withPresentationTimeStamp:pts 
                                                                                            format:self.destinationFormat];
                    if (outputSampleBuffer) {
                        // Add to output queue
                        dispatch_sync(_outputQueue, ^{
                            NSValue* outputValue = [NSValue valueWithPointer:outputSampleBuffer];
                            [_outputBufferQueue addObject:outputValue];
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
    dispatch_sync(_outputQueue, ^{
        if (_outputBufferQueue.count > 0) {
            NSValue* value = _outputBufferQueue.firstObject;
            [_outputBufferQueue removeObjectAtIndex:0];
            result = (CMSampleBufferRef)[value pointerValue];
            // Don't release here as this method should return a retained reference
        } else if (_outputFinished) {
            // No more data available
            result = NULL;
        }
    });
    
    return result;
}

@end

NS_ASSUME_NONNULL_END