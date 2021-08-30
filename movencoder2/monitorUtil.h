//
//  monitorUtil.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//  Copyright © 2018-2021 MyCometG3. All rights reserved.
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

#ifndef monitorUtil_h
#define monitorUtil_h

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

typedef void (^monitor_block_t)(void);
typedef void (^cancel_block_t)(void);

void startMonitor(monitor_block_t mon, cancel_block_t can);
void finishMonitor(int code) ;
int lastSignal(void);

NS_ASSUME_NONNULL_END

#endif /* monitorUtil_h */
