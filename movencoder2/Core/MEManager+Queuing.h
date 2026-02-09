//
//  MEManager+Queuing.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEManager+Queuing.h
 * @abstract Queue management and synchronization for MEManager
 * @discussion
 * This category handles dispatch queue creation, synchronization primitives,
 * and coordination between input and output queues for the processing pipeline.
 */

#ifndef MEManager_Queuing_h
#define MEManager_Queuing_h

#import "MEManager.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEManager (Queuing)

/**
 * @brief Input queue for sample buffer ingestion
 * @discussion Serial dispatch queue used for coordinating input operations.
 * Lazily created on first access.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t inputQueue;

/**
 * @brief Output queue for sample buffer production
 * @discussion Serial dispatch queue used for coordinating output operations.
 * Lazily created on first access.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t outputQueue;

/**
 * @brief Execute block synchronously on input queue
 * @discussion If already on input queue, executes immediately to prevent deadlock.
 * Otherwise dispatches synchronously.
 * @param block Block to execute
 */
- (void)input_sync:(dispatch_block_t)block;

/**
 * @brief Execute block asynchronously on input queue
 * @discussion If already on input queue, executes immediately.
 * Otherwise dispatches asynchronously.
 * @param block Block to execute
 */
- (void)input_async:(dispatch_block_t)block;

/**
 * @brief Execute block synchronously on output queue
 * @discussion If already on output queue, executes immediately to prevent deadlock.
 * Otherwise dispatches synchronously.
 * @param block Block to execute
 */
- (void)output_sync:(dispatch_block_t)block;

/**
 * @brief Execute block asynchronously on output queue
 * @discussion If already on output queue, executes immediately.
 * Otherwise dispatches asynchronously.
 * @param block Block to execute
 */
- (void)output_async:(dispatch_block_t)block;

@end

NS_ASSUME_NONNULL_END

#endif /* MEManager_Queuing_h */
