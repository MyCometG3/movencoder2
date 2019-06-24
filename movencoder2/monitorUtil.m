//
//  monitorUtil.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//  Copyright © 2018 MyCometG3. All rights reserved.
//

/*
 * This file is part of movencoder2.
 *
 * movencoder2 is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * movencoder2 is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#import "monitorUtil.h"

#ifndef ALog
#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

static uint64_t hbInterval = NSEC_PER_SEC / 5; // run _monBlock every 0.2 sec

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

dispatch_queue_t _queue = NULL; // Monitor Queue
monitor_block_t _monBlock = NULL; // monitor handler
cancel_block_t _canBlock = NULL; // cancel handler
dispatch_source_t _timerSource = NULL; // timer source
dispatch_source_t _signalSource = NULL; // signal source

static dispatch_queue_t monitorQueue() {
    if (!_queue) {
        dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UNSPECIFIED, 0);
        _queue = queue;
    }
    return _queue;
}

static dispatch_source_t timerSource() {
    if (!_timerSource) {
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                          0, 0, monitorQueue());
        _timerSource = source;
    }
    return _timerSource;
}

static dispatch_source_t signalSource(int code) {
    if (!_signalSource) {
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,
                                                          code, 0, monitorQueue());
        _signalSource = source;
    }
    return _signalSource;
}

static void exitAsync(int code, dispatch_source_t _Nullable srcToCancel) {
    if (srcToCancel) {
        dispatch_source_cancel(srcToCancel);
    }
    dispatch_async(monitorQueue(), ^{ exit(code); });
}

static dispatch_source_t timerSrcInstaller(dispatch_block_t handler, dispatch_block_t completion) {
    dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, hbInterval);
    dispatch_source_t src = timerSource();
    dispatch_source_set_timer(src, start, hbInterval, 0);
    dispatch_source_set_event_handler(src, handler);
    dispatch_source_set_cancel_handler(src, completion);
    dispatch_resume(src);
    return src;
}

static dispatch_source_t signalSrcInstaller(int code, dispatch_block_t handler) {
    signal(code, SIG_IGN);
    dispatch_source_t src = signalSource(code);
    dispatch_source_set_event_handler(src, handler);
    dispatch_resume(src);
    return src;
}

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

/**
 Start progress monitor queue. Never returns. Handle SIGINT.
 */
void startMonitor(monitor_block_t mon, cancel_block_t can) {
    // install GSD based timer handler
    timerSrcInstaller(mon, can);
    
    // install GCD based signal handler
    signalSrcInstaller(SIGINT, ^{
        printf("\n");
        NSLog(@"SIGINT detected");
        exitAsync(SIGINT, timerSource());
    });
    
    // start main queue - never returns
    dispatch_main();
}

void finishMonitor(int code) {
    exitAsync(code, timerSource());
}

NS_ASSUME_NONNULL_END
