//
//  MEH26xNALUtils.m
//  movencoder2
//
//  Created for refactoring on 2026/02/09.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MEH26xNALUtils.h"

#include <libavformat/avio.h>
#include <libavutil/mem.h>

NS_ASSUME_NONNULL_BEGIN

/* =================================================================================== */
// MARK: - NAL Unit Utilities (from FFmpeg)
/* =================================================================================== */

// nal support utility from ffmpeg project trunk/libavformat/avc.c
const static uint8_t *ff_avc_find_startcode_internal(const uint8_t *p, const uint8_t *end)
{
    const uint8_t *a = p + 4 - ((intptr_t)p & 3);
    
    for (end -= 3; p < a && p < end; p++) {
        if (p[0] == 0 && p[1] == 0 && p[2] == 1)
            return p;
    }
    
    for (end -= 3; p < end; p += 4) {
        uint32_t x = *(const uint32_t*)p;
        //      if ((x - 0x01000100) & (~x) & 0x80008000) // little endian
        //      if ((x - 0x00010001) & (~x) & 0x00800080) // big endian
        if ((x - 0x01010101) & (~x) & 0x80808080) { // generic
            if (p[1] == 0) {
                if (p[0] == 0 && p[2] == 1)
                    return p;
                if (p[2] == 0 && p[3] == 1)
                    return p+1;
            }
            if (p[3] == 0) {
                if (p[2] == 0 && p[4] == 1)
                    return p+2;
                if (p[4] == 0 && p[5] == 1)
                    return p+3;
            }
        }
    }
    
    for (end += 3; p < end; p++) {
        if (p[0] == 0 && p[1] == 0 && p[2] == 1)
            return p;
    }
    
    return end + 3;
}

const uint8_t *avc_find_startcode(const uint8_t *p, const uint8_t *end ) {
    const uint8_t *out= ff_avc_find_startcode_internal(p, end);
    if(p<out && out<end && !out[-1]) out--;
    return out;
}

// nal support utility from ffmpeg project trunk/libavformat/movenc.c
void avc_parse_nal_units(uint8_t **buf, int *size)
{
    const uint8_t *p = *buf;
    const uint8_t *end = p + *size;
    const uint8_t *nal_start, *nal_end;
    
    AVIOContext *pb;
    int ret = avio_open_dyn_buf(&pb);
    if(ret < 0)
        return;
    
    nal_start = avc_find_startcode(p, end);
    while (nal_start < end) {
        while(!*(nal_start++));
        nal_end = avc_find_startcode(nal_start, end);
        int offset = (int)(nal_end - nal_start);
        avio_wb32(pb, offset);
        avio_write(pb, nal_start, offset);
        nal_start = nal_end;
    }
    
    av_freep(buf);
    *size = avio_close_dyn_buf(pb, buf);
}

NS_ASSUME_NONNULL_END
