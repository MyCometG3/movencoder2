//
//  MEEncoderPipeline.h
//  movencoder2
//
//  Created by Copilot on 2025-09-29.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
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

/**
 * @header MEEncoderPipeline.h
 * @abstract Internal API - Video encoder abstraction
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * It is not intended for public use and its interface may change without notice.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MEEncoderPipeline_h
#define MEEncoderPipeline_h

@import Foundation;
@import CoreMedia;

@class MEVideoEncoderConfig;

NS_ASSUME_NONNULL_BEGIN

/**
 * MEEncoderPipeline encapsulates video encoder setup, management, and interaction.
 * This component is extracted from MEManager to separate encoder concerns and improve maintainability.
 */
@interface MEEncoderPipeline : NSObject

/**
 * Indicates if the video encoder pipeline is ready for processing.
 */
@property (atomic, readonly) BOOL isReady;

/**
 * Indicates if the video encoder pipeline has reached EOF.
 */
@property (atomic, readonly) BOOL isEOF;

/**
 * Indicates if the encoder has been flushed.
 */
@property (atomic, readonly) BOOL isFlushed;

/**
 * The video encoder settings dictionary.
 */
@property (nonatomic, strong, nullable) NSMutableDictionary *videoEncoderSetting;

/**
 * Format description extensions dictionary from source movie's track.
 */
@property (nonatomic, strong, nullable) __attribute__((NSObject)) CFDictionaryRef sourceExtensions;

/**
 * Verbose logging flag.
 */
@property (nonatomic) BOOL verbose;

/**
 * FFmpeg log level.
 */
@property (nonatomic) int logLevel;

/**
 * The time base for timestamp calculations.
 */
@property (atomic) CMTimeScale timeBase;

/**
 * Semaphore for signaling when the encoder is ready.
 */
@property (readonly, nonatomic, strong) dispatch_semaphore_t encoderReadySemaphore;

/**
 * Initialize the encoder pipeline.
 */
- (instancetype)init;

/**
 * Prepare the video encoder with the provided sample buffer or filtered frame.
 * This method sets up the encoder context based on the input properties.
 *
 * @param sampleBuffer The CMSampleBuffer containing video frame information (can be nil if using filtered frame)
 * @param filteredFrame Pointer to AVFrame from filter pipeline (can be NULL if using sample buffer)
 * @param hasValidFilteredFrame Whether the filtered frame is valid
 * @return YES if successful, NO otherwise
 */
- (BOOL)prepareVideoEncoderWith:(CMSampleBufferRef _Nullable)sampleBuffer 
                  filteredFrame:(void * _Nullable)filteredFrame
            hasValidFilteredFrame:(BOOL)hasValidFilteredFrame;

/**
 * Send a frame to the encoder for encoding.
 * 
 * OWNERSHIP: This method takes ownership of the frame and will call av_frame_unref()
 * on it internally. The caller should not unref the frame after calling this method.
 * The encoder makes an internal copy as needed via avcodec_send_frame().
 *
 * @param frame The AVFrame to encode (nullable - pass NULL to flush)
 * @param result Pointer to store the result code
 * @return YES if successful, NO on error
 */
- (BOOL)sendFrameToEncoder:(void * _Nullable)frame withResult:(int *)result;

/**
 * Receive an encoded packet from the encoder.
 *
 * @param result Pointer to store the result code
 * @return YES if successful or needs more input (EAGAIN), NO on error
 */
- (BOOL)receivePacketFromEncoderWithResult:(int *)result;

/**
 * Flush the encoder to get remaining packets.
 *
 * @param result Pointer to store the result code
 * @return YES if successful, NO on error
 */
- (BOOL)flushEncoderWithResult:(int *)result;

/**
 * Get the current encoded AVPacket pointer.
 * This should only be used by components that understand AVPacket memory management.
 */
- (void *)encodedPacket;

/**
 * Get the codec context pointer.
 * This should only be used by components that understand AVCodecContext memory management.
 */
- (void *)codecContext;

/**
 * Get the video encoder configuration object.
 */
- (MEVideoEncoderConfig * _Nullable)videoEncoderConfig;

/**
 * Set the video encoder configuration object.
 */
- (void)setVideoEncoderConfig:(MEVideoEncoderConfig * _Nullable)config;

/**
 * Get the pixel format specification for encoding.
 */
- (void)getPixelFormatSpec:(void *)spec;

/**
 * Cleanup resources.
 */
- (void)cleanup;

@end

NS_ASSUME_NONNULL_END

#endif /* MEEncoderPipeline_h */
