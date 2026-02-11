//
//  MEManager+Pipeline.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEManager+Pipeline.h
 * @abstract Video filter and encoder pipeline setup for MEManager
 * @discussion
 * This category handles the preparation and configuration of video filter
 * and encoder pipelines. It manages AVFrame preparation from CMSampleBuffers
 * and coordinates the filter/encoder initialization sequence.
 */

#ifndef MEManager_Pipeline_h
#define MEManager_Pipeline_h

#import "MEManager.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEManager (Pipeline)

/**
 * @brief Setup video encoder with parameters from CMSampleBuffer
 * @discussion Initializes the video encoder pipeline using configuration from
 * the provided sample buffer. If filter pipeline is active, waits for filtered
 * frame availability before initializing encoder.
 * @param sb CMSampleBuffer containing source format information (nullable for filter-only init)
 * @return TRUE if encoder was successfully prepared, FALSE otherwise
 */
- (BOOL)prepareVideoEncoderWith:(CMSampleBufferRef _Nullable)sb;

/**
 * @brief Setup video filter with parameters from CMSampleBuffer
 * @discussion Initializes the video filter pipeline using configuration from
 * the provided sample buffer. Sets up filtergraph based on videoFilterString.
 * @param sb CMSampleBuffer containing source format information
 * @return TRUE if filter was successfully prepared, FALSE otherwise
 */
- (BOOL)prepareVideoFilterWith:(CMSampleBufferRef)sb;

/**
 * @brief Prepare input AVFrame from CMSampleBuffer
 * @discussion Extracts image data and metadata from CMSampleBuffer and populates
 * an AVFrame for processing. Manages frame lifecycle with proper ref counting.
 * The internal input frame is reused across calls for efficiency.
 * @param sb CMSampleBuffer to extract frame data from
 * @return TRUE if frame was successfully prepared, FALSE otherwise
 */
- (BOOL)prepareInputFrameWith:(CMSampleBufferRef)sb;

@end

NS_ASSUME_NONNULL_END

#endif /* MEManager_Pipeline_h */
