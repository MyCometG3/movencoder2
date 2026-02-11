//
//  MEManager+SampleBuffer.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEManager+SampleBuffer.h
 * @abstract Sample buffer I/O operations for MEManager
 * @discussion
 * This category handles the creation and processing of CMSampleBuffers for
 * both compressed (encoded) and uncompressed (filtered) video data. It provides
 * the input/output bridge APIs that mimic AVAssetWriter/Reader interfaces.
 */

#ifndef MEManager_SampleBuffer_h
#define MEManager_SampleBuffer_h

#import "MEManager.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEManager (SampleBuffer)

/**
 * @brief Create CMSampleBuffer from filtered video frame
 * @discussion Wraps the filtered AVFrame output into a CMSampleBuffer for
 * consumption by AVFoundation. Used when filter-only processing is active.
 * @return Retained CMSampleBuffer (caller must release), or NULL on failure
 */
- (nullable CMSampleBufferRef)createUncompressedSampleBuffer CF_RETURNS_RETAINED;

/**
 * @brief Create CMSampleBuffer from encoded video packet
 * @discussion Wraps the encoded AVPacket output into a CMSampleBuffer with
 * appropriate format description for the codec. Used when encoder is active.
 * @return Retained CMSampleBuffer (caller must release), or NULL on failure
 */
- (nullable CMSampleBufferRef)createCompressedSampleBuffer CF_RETURNS_RETAINED;

/**
 * @brief Append sample buffer to input pipeline
 * @discussion Input bridge API (mimics AVAssetWriterInput). Queues sample buffer
 * for processing through filter/encoder pipeline. Handles pipeline preparation
 * and frame conversion internally.
 * @param sb CMSampleBuffer to append (NULL to signal flush)
 * @return TRUE if buffer was accepted, FALSE if error or pipeline not ready
 */
- (BOOL)appendSampleBuffer:(CMSampleBufferRef _Nullable)sb;

/**
 * @brief Check if pipeline is ready for more input
 * @discussion Input bridge API (mimics AVAssetWriterInput). Returns whether
 * the pipeline can accept additional sample buffers.
 * @return TRUE if ready for more data, FALSE if pipeline is full or completed
 */
- (BOOL)isReadyForMoreMediaData;

/**
 * @brief Signal end of input stream
 * @discussion Input bridge API (mimics AVAssetWriterInput). Signals that no
 * more input will be provided and flushes the pipeline.
 */
- (void)markAsFinished;

/**
 * @brief Copy next processed sample buffer from output pipeline
 * @discussion Output bridge API (mimics AVAssetReaderOutput). Pulls the next
 * processed sample buffer (filtered or encoded) from the pipeline. Blocks until
 * a buffer is available or EOF is reached.
 * @return Retained CMSampleBuffer (caller must release), or NULL if EOF or error
 */
- (nullable CMSampleBufferRef)copyNextSampleBuffer CF_RETURNS_RETAINED;

/**
 * @brief Get the natural display size for the output video
 * @discussion Computes the display size accounting for pixel aspect ratio.
 * Based on encoder configuration (declaredSize × pixelAspect).
 * @return Natural size in pixels, or CGSizeZero if not configured
 */
- (CGSize)naturalSize;

/**
 * @brief Set the natural display size (unsupported)
 * @discussion Currently unsupported - logs error if called.
 * @param naturalSize Desired natural size (ignored)
 */
- (void)setNaturalSize:(CGSize)naturalSize;

/**
 * @brief Get the media type for output
 * @discussion Output bridge API (mimics AVAssetReaderOutput).
 * @return Always returns AVMediaTypeVideo
 */
- (AVMediaType)mediaType;

@end

NS_ASSUME_NONNULL_END

#endif /* MEManager_SampleBuffer_h */
