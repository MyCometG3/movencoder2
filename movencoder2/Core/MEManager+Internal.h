//
//  MEManager+Internal.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEManager+Internal.h
 * @abstract Internal interfaces for MEManager categories
 * @discussion
 * This header exposes internal properties and methods needed by category
 * implementations. Not for external use.
 * @internal
 */

#ifndef MEManager_Internal_h
#define MEManager_Internal_h

#import "MEManager.h"
#import "MECommon.h"

@class MEFilterPipeline;
@class MEEncoderPipeline;
@class MESampleBufferFactory;
@class MEVideoEncoderConfig;

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEManager (Internal)

// Pipeline components
@property (nonatomic, strong, readonly) MEFilterPipeline *filterPipeline;
@property (nonatomic, strong, readonly) MEEncoderPipeline *encoderPipeline;
@property (nonatomic, strong, readonly) MESampleBufferFactory *sampleBufferFactory;

// Synchronization semaphores
@property (readonly, nonatomic, strong) dispatch_semaphore_t timestampGapSemaphore;
@property (readonly, nonatomic, strong) dispatch_semaphore_t filterReadySemaphore;
@property (readonly, nonatomic, strong) dispatch_semaphore_t encoderReadySemaphore;
@property (readonly, nonatomic, strong) dispatch_semaphore_t eagainDelaySemaphore;

// Queue management
@property (nonatomic, strong) dispatch_queue_t inputQueue;
@property (nonatomic, strong) dispatch_block_t inputBlock;
@property (nonatomic, strong) dispatch_queue_t outputQueue;
@property (nonatomic) void* inputQueueKey;
@property (nonatomic) void* outputQueueKey;

// State management
@property (atomic) BOOL queueing;
@property (atomic) CMTimeScale time_base;
@property (atomic, readwrite) int64_t lastEnqueuedPTS;
@property (atomic, readwrite) int64_t lastDequeuedPTS;
@property (atomic, assign) BOOL colorMetadataCached;
@property (atomic, strong, readwrite, nullable) MEVideoEncoderConfig *videoEncoderConfig;
@property (atomic, assign) BOOL configIssuesLogged;

// Computed properties
@property (readonly) BOOL videoFilterIsReady;
@property (readonly) BOOL videoFilterEOF;
@property (readonly) BOOL filteredValid;
@property (readonly) BOOL videoEncoderIsReady;
@property (readonly) BOOL videoEncoderEOF;
@property (readonly) BOOL videoFilterFlushed;
@property (readonly) BOOL videoEncoderFlushed;

// Internal frame access
- (void *)input; // AVFrame*
- (struct AVFrameColorMetadata *)cachedColorMetadata;
- (struct AVFPixelFormatSpec *)pxl_fmt_filter;

@end

NS_ASSUME_NONNULL_END

#endif /* MEManager_Internal_h */
