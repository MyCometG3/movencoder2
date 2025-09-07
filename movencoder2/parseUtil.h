//
//  parseUtil.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2019/06/16.
//  Copyright © 2019-2025 MyCometG3. All rights reserved.
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

#ifndef parseUtil_h
#define parseUtil_h

@import Foundation;
@import AVFoundation;

NS_ASSUME_NONNULL_BEGIN

/* =================================================================================== */
// MARK: - parse utilities
/* =================================================================================== */

extern NSString* const separator;
extern NSString* const equal;
extern NSString* const optSeparator;

NSNumber* _Nullable parseInteger(NSString* val);
NSNumber* _Nullable parseDouble(NSString* val);
NSValue* _Nullable parseSize(NSString* val);
NSValue* _Nullable parseRect(NSString* val);
NSValue* _Nullable parseTime(NSString* val);
NSNumber* _Nullable parseBool(NSString* val);
NSDictionary* _Nullable parseCodecOptions(NSString* val);
NSNumber* _Nullable parseLayoutTag(NSString* val); // Supports AAC layout names and integer values

NS_ASSUME_NONNULL_END

#endif /* parseUtil_h */
