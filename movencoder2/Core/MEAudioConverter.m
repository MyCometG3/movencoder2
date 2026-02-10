//
//  MEAudioConverter.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MECommon.h"
#import "MEAudioConverter.h"
#import "MEAudioConverter+Internal.h"
#import "MEAudioConverter+BufferConversion.h"
#import "MEAudioConverter+VolumeControl.h"
#import "MESecureLogging.h"
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
        for (NSValue* value in self->_inputBufferQueue) {
            CMSampleBufferRef sampleBuffer = (CMSampleBufferRef)[value pointerValue];
            if (sampleBuffer) {
                CFRelease(sampleBuffer);
            }
        }
        [self->_inputBufferQueue removeAllObjects];
    });
    
    dispatch_async(_outputQueue, ^{
        for (NSValue* value in self->_outputBufferQueue) {
            CMSampleBufferRef sampleBuffer = (CMSampleBufferRef)[value pointerValue];
            if (sampleBuffer) {
                CFRelease(sampleBuffer);
            }
        }
        [self->_outputBufferQueue removeAllObjects];
    });
}

- (AVMediaType)mediaType
{
    return AVMediaTypeAudio;
}

- (AVMediaType)mediaTypeInternal { return [self mediaType]; }

- (CMTimeScale)mediaTimeScaleInternal { return self.mediaTimeScale; }
- (void)setMediaTimeScaleInternal:(CMTimeScale)mediaTimeScale { self.mediaTimeScale = mediaTimeScale; }

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
        // Ensure converter is available when formats are set
        if (!self->_audioConverter && self.sourceFormat && self.destinationFormat) {
            self->_audioConverter = [[AVAudioConverter alloc] initFromFormat:self.sourceFormat toFormat:self.destinationFormat];
            if (!self->_audioConverter) {
                self.failed = YES;
                if (self.verbose) {
                    SecureErrorLog(@"Failed to create AVAudioConverter");
                }
                success = NO;
                return;
            }
        }

        // Store the sample buffer for processing
        CFRetain(sb);
        NSValue* value = [NSValue valueWithPointer:sb];
        [self->_inputBufferQueue addObject:value];

        // Trigger processing if converter is available
        if (self->_audioConverter && self.sourceFormat && self.destinationFormat) {
            [self processNextBuffer];
        }
    });
    
    return success;
}

- (BOOL)appendSampleBufferInternal:(CMSampleBufferRef)sb { return [self appendSampleBuffer:sb]; }

- (BOOL)isReadyForMoreMediaData
{
    if (_inputFinished || self.failed) {
        return NO;
    }
    
    // Limit queue size to prevent memory issues
    NSUInteger limit = self.maxInputBufferCount;
    __block BOOL ready;
    dispatch_sync(_inputQueue, ^{
        ready = (limit > 0) ? (self->_inputBufferQueue.count < limit) : NO;
    });
    return ready;
}

- (BOOL)isReadyForMoreMediaDataInternal { return [self isReadyForMoreMediaData]; }

- (void)markAsFinished
{
    dispatch_sync(_inputQueue, ^{
        self->_inputFinished = YES;
        // Process any remaining buffers
        while (self->_inputBufferQueue.count > 0 && self->_audioConverter) {
            [self processNextBuffer];
        }
        
        // Signal semaphore to unblock any waiting threads
        dispatch_semaphore_signal(self->_outputDataSemaphore);
    });
    
    // Mark output as finished separately to avoid nested dispatch_sync deadlock
    dispatch_async(_outputQueue, ^{
        self->_outputFinished = YES;
    });
}

- (void)markAsFinishedInternal { [self markAsFinished]; }

- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block
{
    dispatch_sync(_inputQueue, ^{
        self->_inputRequestQueue = queue;
        self->_inputRequestHandler = [block copy];
        
        // Initialize the audio converter if not already done
        if (!self->_audioConverter && self.sourceFormat && self.destinationFormat) {
            self->_audioConverter = [[AVAudioConverter alloc] initFromFormat:self.sourceFormat toFormat:self.destinationFormat];
            if (!self->_audioConverter) {
                self.failed = YES;
                if (self.verbose) {
                    SecureErrorLog(@"Failed to create AVAudioConverter");
                }
                return;
            }
        }
        
        // Start the processing loop
        if (self->_inputRequestQueue && self->_inputRequestHandler) {
            dispatch_async(self->_inputRequestQueue, self->_inputRequestHandler);
        }
    });
}

- (void)requestMediaDataWhenReadyOnQueueInternal:(dispatch_queue_t)queue usingBlock:(RequestHandler)block { [self requestMediaDataWhenReadyOnQueue:queue usingBlock:block]; }

- (void)processNextBuffer
{
    if (_inputBufferQueue.count == 0) {
        return;
    }

    if (!_audioConverter && self.sourceFormat && self.destinationFormat) {
        _audioConverter = [[AVAudioConverter alloc] initFromFormat:self.sourceFormat toFormat:self.destinationFormat];
        if (!_audioConverter) {
            self.failed = YES;
            if (self.verbose) {
                SecureErrorLog(@"Failed to create AVAudioConverter");
            }
            return;
        }
    }
    if (!_audioConverter) {
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
                            [self->_outputBufferQueue addObject:outputValue];
                            
                            // Signal that new data is available
                            dispatch_semaphore_signal(self->_outputDataSemaphore);
                        });
                    }
                } else if (convertError) {
                    if (self.verbose) {
                        SecureErrorLogf(@"Audio conversion error: %@", convertError);
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
            if (self->_outputBufferQueue.count > 0) {
                NSValue* value = self->_outputBufferQueue.firstObject;
                [self->_outputBufferQueue removeObjectAtIndex:0];
                result = (CMSampleBufferRef)[value pointerValue];
                // Don't release here as this method should return a retained reference
            } else if (self->_inputFinished) {
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

- (nullable CMSampleBufferRef)copyNextSampleBufferInternal { return [self copyNextSampleBuffer]; }

@end

NS_ASSUME_NONNULL_END
