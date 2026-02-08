//
//  monitorUtil.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header monitorUtil.h
 * @abstract Internal API - Signal monitoring utilities
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * It is not intended for public use and its interface may change without notice.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef monitorUtil_h
#define monitorUtil_h

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

typedef void (^monitor_block_t)(void);
typedef void (^cancel_block_t)(void);

void startMonitor(monitor_block_t mon, cancel_block_t can);
void finishMonitor(int code, NSString* _Nullable msg, NSString* _Nullable errMsg);
int lastSignal(void);

NS_ASSUME_NONNULL_END

#endif /* monitorUtil_h */
