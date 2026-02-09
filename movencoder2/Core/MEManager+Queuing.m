//
//  MEManager+Queuing.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MEManager+Queuing.h"
#import "MEManager+Internal.h"
#import "MECommon.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

static const char* const kMEInputQueue = "MEManager.MEInputQueue";
static const char* const kMEOutputQueue = "MEManager.MEOutputQueue";

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation MEManager (Queuing)

- (dispatch_queue_t) inputQueue
{
    if (!_inputQueue) {
        _inputQueue = dispatch_queue_create(kMEInputQueue, DISPATCH_QUEUE_SERIAL);
        self.inputQueueKey = &_inputQueueKey;
        void* unused = (__bridge void*)self;
        dispatch_queue_set_specific(_inputQueue, self.inputQueueKey, unused, NULL);
    }
    return _inputQueue;
}

- (dispatch_queue_t) outputQueue
{
    if (!_outputQueue) {
        _outputQueue = dispatch_queue_create(kMEOutputQueue, DISPATCH_QUEUE_SERIAL);
        self.outputQueueKey = &_outputQueueKey;
        void* unused = (__bridge void*)self;
        dispatch_queue_set_specific(_outputQueue, self.outputQueueKey, unused, NULL);
    }
    return _outputQueue;
}

- (void) input_sync:(dispatch_block_t)block
{
    dispatch_queue_t queue = self.inputQueue;
    void * key = self.inputQueueKey;
    assert (queue && key);
    if (dispatch_get_specific(key)) {
        block(); // do sync operation
    } else {
        dispatch_sync(queue, block);
    }
}

- (void) input_async:(dispatch_block_t)block
{
    dispatch_queue_t queue = self.inputQueue;
    void * key = self.inputQueueKey;
    assert (queue && key);
    if (dispatch_get_specific(key)) {
        block(); // do sync operation
    } else {
        dispatch_async(queue, block);
    }
}

- (void) output_sync:(dispatch_block_t)block
{
    dispatch_queue_t queue = self.outputQueue;
    void * key = self.outputQueueKey;
    assert (queue && key);
    if (dispatch_get_specific(key)) {
        block(); // do sync operation
    } else {
        dispatch_sync(queue, block);
    }
}

- (void) output_async:(dispatch_block_t)block
{
    dispatch_queue_t queue = self.outputQueue;
    void * key = self.outputQueueKey;
    assert (queue && key);
    if (dispatch_get_specific(key)) {
        block(); // do sync operation
    } else {
        dispatch_async(queue, block);
    }
}

- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block
{
    self.inputQueue = queue;
    self.inputBlock = block;

    self.inputQueueKey = &_inputQueueKey;
    void* unused = (__bridge void*)self;
    dispatch_queue_set_specific(_inputQueue, self.inputQueueKey, unused, NULL);
}

@end

NS_ASSUME_NONNULL_END
