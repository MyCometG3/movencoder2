//
//  MEFilterPipeline.h
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

#ifndef MEFilterPipeline_h
#define MEFilterPipeline_h

@import Foundation;
@import CoreMedia;

NS_ASSUME_NONNULL_BEGIN

/**
 * MEFilterPipeline encapsulates video filter graph setup, preparation, and filtered frame pulling logic.
 * This component is extracted from MEManager to separate concerns and improve maintainability.
 */
@interface MEFilterPipeline : NSObject

/**
 * Indicates if the video filter pipeline is ready for processing.
 */
@property (atomic, readonly) BOOL isReady;

/**
 * Indicates if the video filter pipeline has reached EOF.
 */
@property (atomic, readonly) BOOL isEOF;

/**
 * Indicates if a filtered frame is currently valid and ready for consumption.
 */
@property (atomic, readonly) BOOL hasValidFilteredFrame;

/**
 * The video filter string used for configuration.
 */
@property (nonatomic, strong, nullable) NSString *filterString;

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
 * Semaphore for signaling when the filter is ready.
 */
@property (readonly, nonatomic, strong) dispatch_semaphore_t filterReadySemaphore;

/**
 * Semaphore for signaling timestamp gap events.
 */
@property (readonly, nonatomic, strong) dispatch_semaphore_t timestampGapSemaphore;

/**
 * Initialize the filter pipeline.
 */
- (instancetype)init;

/**
 * Prepare the video filter with the provided sample buffer.
 * This method sets up the filter graph based on the sample buffer properties.
 *
 * @param sampleBuffer The CMSampleBuffer containing video frame information
 * @return YES if successful, NO otherwise
 */
- (BOOL)prepareVideoFilterWith:(CMSampleBufferRef)sampleBuffer;

/**
 * Pull a filtered frame from the filter graph.
 * This method retrieves the next available filtered frame.
 *
 * @param result Pointer to store the result code
 * @return YES if successful or needs more input (EAGAIN), NO on error
 */
- (BOOL)pullFilteredFrameWithResult:(int *)result;

/**
 * Get the last dequeued PTS value.
 */
- (int64_t)lastDequeuedPTS;

/**
 * Set the last dequeued PTS value.
 */
- (void)setLastDequeuedPTS:(int64_t)pts;

/**
 * Push a frame into the filter graph for processing.
 * 
 * OWNERSHIP: The caller retains ownership of the frame. This method makes an internal
 * copy using AV_BUFFERSRC_FLAG_KEEP_REF, so the caller is responsible for calling
 * av_frame_unref() on the frame after this method returns.
 *
 * @param frame The AVFrame to push into the filter graph (nullable - pass NULL to flush)
 * @param result Pointer to store the result code
 * @return YES if successful, NO on error
 */
- (BOOL)pushFrameToFilter:(void * _Nullable)frame withResult:(int *)result;

/**
 * Get the current filtered AVFrame pointer.
 * This should only be used by components that understand AVFrame memory management.
 */
- (void *)filteredFrame;

/**
 * Reset the filtered frame validity and free its resources.
 * 
 * OWNERSHIP: This method owns the internal 'filtered' frame and is responsible
 * for calling av_frame_unref() to free its data when resetting.
 */
- (void)resetFilteredFrame;

/**
 * Cleanup resources.
 */
- (void)cleanup;

@end

NS_ASSUME_NONNULL_END

#endif /* MEFilterPipeline_h */
