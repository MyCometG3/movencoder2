//
//  MESampleBufferFactory.h
//  movencoder2
//
//  Created by Copilot on 2025-09-29.
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

#ifndef MESampleBufferFactory_h
#define MESampleBufferFactory_h

@import Foundation;
@import CoreMedia;
@import CoreVideo;

@class MEVideoEncoderConfig;

NS_ASSUME_NONNULL_BEGIN

/**
 * MESampleBufferFactory is responsible for creating and managing sample buffers for video data.
 * This component is extracted from MEManager to separate sample buffer creation concerns.
 */
@interface MESampleBufferFactory : NSObject

/**
 * The video encoder settings dictionary.
 */
@property (nonatomic, strong, nullable) NSMutableDictionary *videoEncoderSetting;

/**
 * The time base for timestamp calculations.
 */
@property (atomic) CMTimeScale timeBase;

/**
 * Format description for sample buffers.
 */
@property (atomic, strong, nullable) __attribute__((NSObject)) CMFormatDescriptionRef formatDescription;

/**
 * Pixel buffer pool for uncompressed frames.
 */
@property (atomic, strong, nullable) __attribute__((NSObject)) CVPixelBufferPoolRef pixelBufferPool;

/**
 * Pixel buffer attachments dictionary.
 */
@property (atomic, strong, nullable) __attribute__((NSObject)) CFDictionaryRef pixelBufferAttachments;

/**
 * Verbose logging flag.
 */
@property (nonatomic) BOOL verbose;

/**
 * Initialize the sample buffer factory.
 */
- (instancetype)init;

/**
 * Create an uncompressed sample buffer from a filtered AVFrame.
 * This method converts an AVFrame from the filter pipeline into a CMSampleBuffer.
 *
 * @param filteredFrame Pointer to the filtered AVFrame
 * @return CMSampleBuffer or NULL on failure
 */
- (nullable CMSampleBufferRef)createUncompressedSampleBufferFromFilteredFrame:(void *)filteredFrame CF_RETURNS_RETAINED;

/**
 * Create a compressed sample buffer from an encoded AVPacket.
 * This method converts an AVPacket from the encoder pipeline into a CMSampleBuffer.
 *
 * @param encodedPacket Pointer to the encoded AVPacket
 * @param codecContext Pointer to the AVCodecContext for format description creation
 * @param videoEncoderConfig The video encoder configuration for clean aperture settings
 * @return CMSampleBuffer or NULL on failure
 */
- (nullable CMSampleBufferRef)createCompressedSampleBufferFromPacket:(void *)encodedPacket 
                                                         codecContext:(void *)codecContext
                                                   videoEncoderConfig:(MEVideoEncoderConfig * _Nullable)videoEncoderConfig CF_RETURNS_RETAINED;

/**
 * Check if we're using a video filter (utility method).
 */
- (BOOL)isUsingVideoFilter;

/**
 * Check if we're using a video encoder (utility method).
 */
- (BOOL)isUsingVideoEncoder;

/**
 * Check if we're using libx264 encoder (utility method).
 */
- (BOOL)isUsingLibx264WithConfig:(MEVideoEncoderConfig * _Nullable)config;

/**
 * Check if we're using libx265 encoder (utility method).
 */
- (BOOL)isUsingLibx265WithConfig:(MEVideoEncoderConfig * _Nullable)config;

/**
 * Reset the format description (typically when switching contexts).
 */
- (void)resetFormatDescription;

/**
 * Reset the pixel buffer pool (typically when switching contexts).
 */
- (void)resetPixelBufferPool;

/**
 * Cleanup resources.
 */
- (void)cleanup;

@end

NS_ASSUME_NONNULL_END

#endif /* MESampleBufferFactory_h */