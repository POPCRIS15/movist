//
//  Movist
//
//  Copyright 2006 ~ 2008 Yong-Hoe Kim. All rights reserved.
//      Yong-Hoe Kim  <cocoable@gmail.com>
//
//  This file is part of Movist.
//
//  Movist is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 3 of the License, or
//  (at your option) any later version.
//
//  Movist is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "MSubtitleParser_SUB.h"

@interface MSubtitleParser_SUB (Private)

- (int)subtitlesCount;

- (void)addSubtitleClass:(NSString*)class atIndex:(int)index;
- (void)classIndex:(int)classIndex
      addTimeStamp:(float)time fileOffset:(int)fileOffset;

- (void)idxLoadEnded;
- (BOOL)classIndex:(int)classIndex
           setData:(void*)data dataSize:(int)dataSize atFileOffset:(int)fileOffset;

@end

////////////////////////////////////////////////////////////////////////////////
// copied & modified from vobsub.c in MPlayer.

/*
 * Some code freely inspired from VobSub <URL:http://vobsub.edensrising.com>,
 * with kind permission from Gabest <gabest@freemail.hu>
 */
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>

//#include "config.h"
//#include "version.h"

//#include "spudec.h"
//#include "mp_msg.h"
#include "unrarlib.h"

#define mp_msg(_1, _2, ...)    TRACE(@ __VA_ARGS__)
       
static int vobsub_id;

/**********************************************************************
 * RAR stream handling
 * The RAR file must have the same basename as the file to open
 * See <URL:http://www.unrarlib.org/>
 **********************************************************************/

typedef struct {
    FILE *file;
    unsigned char *data;
    unsigned long size;
    unsigned long pos;
} rar_stream_t;

static rar_stream_t *
rar_open(const char *const filename, const char *const mode)
{
    rar_stream_t *stream;
    /* unrarlib can only read */
    if (strcmp("r", mode) && strcmp("rb", mode)) {
        errno = EINVAL;
        return NULL;
    }
    stream = malloc(sizeof(rar_stream_t));
    if (stream == NULL)
        return NULL;
    /* first try normal access */
    stream->file = fopen(filename, mode);
    if (stream->file == NULL) {
        char *rar_filename;
        const char *p;
        int rc;
        /* Guess the RAR archive filename */
        rar_filename = NULL;
        p = strrchr(filename, '.');
        if (p) {
            ptrdiff_t l = p - filename;
            rar_filename = malloc(l + 5);
            if (rar_filename == NULL) {
                free(stream);
                return NULL;
            }
            strncpy(rar_filename, filename, l);
            strcpy(rar_filename + l, ".rar");
        }
        else {
            rar_filename = malloc(strlen(filename) + 5);
            if (rar_filename == NULL) {
                free(stream);
                return NULL;
            }
            strcpy(rar_filename, filename);
            strcat(rar_filename, ".rar");
        }
        /* get rid of the path if there is any */
        if ((p = strrchr(filename, '/')) == NULL) {
            p = filename;
        }
        else {
            p++;
        }
        rc = urarlib_get(&stream->data, &stream->size, (char*) p, rar_filename, "");
        if (!rc) {
            /* There is no matching filename in the archive. However, sometimes
             * the files we are looking for have been given arbitrary names in the archive.
             * Let's look for a file with an exact match in the extension only. */
            int i, num_files, name_len;
            ArchiveList_struct *list, *lp;
            /* the cast in the next line is a hack to overcome a design flaw (IMHO) in unrarlib */
            num_files = urarlib_list (rar_filename, (ArchiveList_struct *)&list);
            if (num_files > 0) {
                char *demanded_ext;
                demanded_ext = strrchr (p, '.');
                if (demanded_ext) {
                    int demanded_ext_len = strlen (demanded_ext);
                    for (i=0, lp=list; i<num_files; i++, lp=lp->next) {
                        name_len = strlen (lp->item.Name);
                        if (name_len >= demanded_ext_len && !strcasecmp (lp->item.Name + name_len - demanded_ext_len, demanded_ext)) {
                            if ((rc = urarlib_get(&stream->data, &stream->size, lp->item.Name, rar_filename, ""))) {
                                break;
                            }
                        }
                    }
                }
                urarlib_freelist (list);
            }
            if (!rc) {
                free(rar_filename);
                free(stream);
                return NULL;
            }
        }
        
        free(rar_filename);
        stream->pos = 0;
    }
    return stream;
}

static int
rar_close(rar_stream_t *stream)
{
    if (stream->file)
        return fclose(stream->file);
    free(stream->data);
    return 0;
}

static int
rar_eof(rar_stream_t *stream)
{
    if (stream->file)
        return feof(stream->file);
    return stream->pos >= stream->size;
}

static long
rar_tell(rar_stream_t *stream)
{
    if (stream->file)
        return ftell(stream->file);
    return stream->pos;
}

static int
rar_seek(rar_stream_t *stream, long offset, int whence)
{
    if (stream->file)
        return fseek(stream->file, offset, whence);
    switch (whence) {
        case SEEK_SET:
            if (offset < 0) {
                errno = EINVAL;
                return -1;
            }
            stream->pos = offset;
            break;
            case SEEK_CUR:
            if (offset < 0 && stream->pos < (unsigned long) -offset) {
                errno = EINVAL;
                return -1;
            }
            stream->pos += offset;
            break;
            case SEEK_END:
            if (offset < 0 && stream->size < (unsigned long) -offset) {
                errno = EINVAL;
                return -1;
            }
            stream->pos = stream->size + offset;
            break;
            default:
            errno = EINVAL;
            return -1;
    }
    return 0;
}

static int
rar_getc(rar_stream_t *stream)
{
    if (stream->file)
        return getc(stream->file);
    if (rar_eof(stream))
        return EOF;
    return stream->data[stream->pos++];
}

static size_t
rar_read(void *ptr, size_t size, size_t nmemb, rar_stream_t *stream)
{
    size_t res;
    unsigned long remain;
    if (stream->file)
        return fread(ptr, size, nmemb, stream->file);
    if (rar_eof(stream))
        return 0;
    res = size * nmemb;
    remain = stream->size - stream->pos;
    if (res > remain)
        res = remain / size * size;
    memcpy(ptr, stream->data + stream->pos, res);
    stream->pos += res;
    res /= size;
    return res;
}

/**********************************************************************/

static ssize_t
vobsub_getline(char **lineptr, size_t *n, rar_stream_t *stream)
{
    size_t res = 0;
    int c;
    if (*lineptr == NULL) {
        *lineptr = malloc(4096);
        if (*lineptr)
            *n = 4096;
    }
    else if (*n == 0) {
        char *tmp = realloc(*lineptr, 4096);
        if (tmp) {
            *lineptr = tmp;
            *n = 4096;
        }
    }
    if (*lineptr == NULL || *n == 0)
        return -1;
    
    for (c = rar_getc(stream); c != EOF; c = rar_getc(stream)) {
        if (res + 1 >= *n) {
            char *tmp = realloc(*lineptr, *n * 2);
            if (tmp == NULL)
                return -1;
            *lineptr = tmp;
            *n *= 2;
        }
        (*lineptr)[res++] = c;
        if (c == '\n') {
            (*lineptr)[res] = 0;
            return res;
        }
    }
    if (res == 0)
        return -1;
    (*lineptr)[res] = 0;
    return res;
}

/**********************************************************************
 * MPEG parsing
 **********************************************************************/

typedef struct {
    rar_stream_t *stream;
    unsigned int pts;
    int aid;
    unsigned char *packet;
    unsigned int packet_reserve;
    unsigned int packet_size;
} mpeg_t;

static mpeg_t *
mpeg_open(const char *filename)
{
    mpeg_t *res = malloc(sizeof(mpeg_t));
    int err = res == NULL;
    if (!err) {
        res->pts = 0;
        res->aid = -1;
        res->packet = NULL;
        res->packet_size = 0;
        res->packet_reserve = 0;
        res->stream = rar_open(filename, "rb");
        err = res->stream == NULL;
        if (err)
            perror("fopen Vobsub file failed");
        if (err)
            free(res);
    }
    return err ? NULL : res;
}

static void
mpeg_free(mpeg_t *mpeg)
{
    if (mpeg->packet)
        free(mpeg->packet);
    if (mpeg->stream)
        rar_close(mpeg->stream);
    free(mpeg);
}

static int
mpeg_eof(mpeg_t *mpeg)
{
    return rar_eof(mpeg->stream);
}

static off_t
mpeg_tell(mpeg_t *mpeg)
{
    return rar_tell(mpeg->stream);
}

static int
mpeg_run(mpeg_t *mpeg)
{
    unsigned int len, idx, version;
    int c;
    /* Goto start of a packet, it starts with 0x000001?? */
    const unsigned char wanted[] = { 0, 0, 1 };
    unsigned char buf[5];
    
    mpeg->aid = -1;
    mpeg->packet_size = 0;
    if (rar_read(buf, 4, 1, mpeg->stream) != 1)
        return -1;
    while (memcmp(buf, wanted, sizeof(wanted)) != 0) {
        c = rar_getc(mpeg->stream);
        if (c < 0)
            return -1;
        memmove(buf, buf + 1, 3);
        buf[3] = c;
    }
    switch (buf[3]) {
        case 0xb9:			/* System End Code */
            break;
        case 0xba:			/* Packet start code */
            c = rar_getc(mpeg->stream);
            if (c < 0)
                return -1;
            if ((c & 0xc0) == 0x40)
                version = 4;
            else if ((c & 0xf0) == 0x20)
                version = 2;
            else {
                mp_msg(MSGT_VOBSUB,MSGL_ERR, "VobSub: Unsupported MPEG version: 0x%02x\n", c);
                return -1;
            }
            if (version == 4) {
                if (rar_seek(mpeg->stream, 9, SEEK_CUR))
                    return -1;
            }
            else if (version == 2) {
                if (rar_seek(mpeg->stream, 7, SEEK_CUR))
                    return -1;
            }
            else
                abort();
            break;
            case 0xbd:			/* packet */
            if (rar_read(buf, 2, 1, mpeg->stream) != 1)
                return -1;
            len = buf[0] << 8 | buf[1];
            idx = mpeg_tell(mpeg);
            c = rar_getc(mpeg->stream);
            if (c < 0)
                return -1;
            if ((c & 0xC0) == 0x40) { /* skip STD scale & size */
                if (rar_getc(mpeg->stream) < 0)
                    return -1;
                c = rar_getc(mpeg->stream);
                if (c < 0)
                    return -1;
            }
            if ((c & 0xf0) == 0x20) { /* System-1 stream timestamp */
                /* Do we need this? */
                abort();
            }
            else if ((c & 0xf0) == 0x30) {
                /* Do we need this? */
                abort();
            }
            else if ((c & 0xc0) == 0x80) { /* System-2 (.VOB) stream */
                unsigned int pts_flags, hdrlen, dataidx;
                c = rar_getc(mpeg->stream);
                if (c < 0)
                    return -1;
                pts_flags = c;
                c = rar_getc(mpeg->stream);
                if (c < 0)
                    return -1;
                hdrlen = c;
                dataidx = mpeg_tell(mpeg) + hdrlen;
                if (dataidx > idx + len) {
                    mp_msg(MSGT_VOBSUB,MSGL_ERR, "Invalid header length: %d (total length: %d, idx: %d, dataidx: %d)\n",
                           hdrlen, len, idx, dataidx);
                    return -1;
                }
                if ((pts_flags & 0xc0) == 0x80) {
                    if (rar_read(buf, 5, 1, mpeg->stream) != 1)
                        return -1;
                    if (!(((buf[0] & 0xf0) == 0x20) && (buf[0] & 1) && (buf[2] & 1) &&  (buf[4] & 1))) {
                        mp_msg(MSGT_VOBSUB,MSGL_ERR, "vobsub PTS error: 0x%02x %02x%02x %02x%02x \n",
                               buf[0], buf[1], buf[2], buf[3], buf[4]);
                        mpeg->pts = 0;
                    }
                    else
                        mpeg->pts = ((buf[0] & 0x0e) << 29 | buf[1] << 22 | (buf[2] & 0xfe) << 14
                                     | buf[3] << 7 | (buf[4] >> 1));
                }
                else /* if ((pts_flags & 0xc0) == 0xc0) */ {
                    /* what's this? */
                    /* abort(); */
                }
                rar_seek(mpeg->stream, dataidx, SEEK_SET);
                mpeg->aid = rar_getc(mpeg->stream);
                if (mpeg->aid < 0) {
                    mp_msg(MSGT_VOBSUB,MSGL_ERR, "Bogus aid %d\n", mpeg->aid);
                    return -1;
                }
                mpeg->packet_size = len - ((unsigned int) mpeg_tell(mpeg) - idx);
                if (mpeg->packet_reserve < mpeg->packet_size) {
                    if (mpeg->packet)
                        free(mpeg->packet);
                    mpeg->packet = malloc(mpeg->packet_size);
                    if (mpeg->packet)
                        mpeg->packet_reserve = mpeg->packet_size;
                }
                if (mpeg->packet == NULL) {
                    mp_msg(MSGT_VOBSUB,MSGL_FATAL,"malloc failure");
                    mpeg->packet_reserve = 0;
                    mpeg->packet_size = 0;
                    return -1;
                }
                if (rar_read(mpeg->packet, mpeg->packet_size, 1, mpeg->stream) != 1) {
                    mp_msg(MSGT_VOBSUB,MSGL_ERR,"fread failure");
                    mpeg->packet_size = 0;
                    return -1;
                }
                idx = len;
            }
            break;
            case 0xbe:			/* Padding */
            if (rar_read(buf, 2, 1, mpeg->stream) != 1)
                return -1;
            len = buf[0] << 8 | buf[1];
            if (len > 0 && rar_seek(mpeg->stream, len, SEEK_CUR))
                return -1;
            break;
            default:
            if (0xc0 <= buf[3] && buf[3] < 0xf0) {
                /* MPEG audio or video */
                if (rar_read(buf, 2, 1, mpeg->stream) != 1)
                    return -1;
                len = buf[0] << 8 | buf[1];
                if (len > 0 && rar_seek(mpeg->stream, len, SEEK_CUR))
                    return -1;
                
            }
            else {
                mp_msg(MSGT_VOBSUB,MSGL_ERR,"unknown header 0x%02X%02X%02X%02X\n",
                       buf[0], buf[1], buf[2], buf[3]);
                return -1;
            }
    }
    return 0;
}

/**********************************************************************
 * Vobsub
 **********************************************************************/

typedef struct {
    unsigned int palette[16];
    unsigned int cuspal[4];
    int delay;
    unsigned int custom;
    unsigned int have_palette;
    unsigned int orig_frame_width, orig_frame_height;
    unsigned int origin_x, origin_y;
    unsigned int forced_subs;
#if 0000
    /* index */
    packet_queue_t *spu_streams;
    unsigned int spu_streams_size;
    unsigned int spu_streams_current;
#else
    MSubtitleParser_SUB* _parser;
    int _classIndex;
#endif
} vobsub_t;

/* Make sure that the spu stream idx exists. */
static int
vobsub_ensure_spu_stream(vobsub_t *vob, unsigned int index)
{
#if 0000
    if (index >= vob->spu_streams_size) {
        /* This is a new stream */
        if (vob->spu_streams) {
            packet_queue_t *tmp = realloc(vob->spu_streams, (index + 1) * sizeof(packet_queue_t));
            if (tmp == NULL) {
                mp_msg(MSGT_VOBSUB,MSGL_ERR,"vobsub_ensure_spu_stream: realloc failure");
                return -1;
            }
            vob->spu_streams = tmp;
        }
        else {
            vob->spu_streams = malloc((index + 1) * sizeof(packet_queue_t));
            if (vob->spu_streams == NULL) {
                mp_msg(MSGT_VOBSUB,MSGL_ERR,"vobsub_ensure_spu_stream: malloc failure");
                return -1;
            }
        }
        while (vob->spu_streams_size <= index) {
            packet_queue_construct(vob->spu_streams + vob->spu_streams_size);
            ++vob->spu_streams_size;
        }
    }
#else
    return (index < [vob->_parser subtitlesCount]);
#endif
    return 0;
}

static int
vobsub_add_id(vobsub_t *vob, const char *id, size_t idlen, const unsigned int index)
{
    TRACE(@"%s(id=\"%s\", len=%d, index=%u)", __PRETTY_FUNCTION__, id, idlen, index);
    if (vobsub_ensure_spu_stream(vob, index) < 0)
        return -1;
#if 0000
    if (id && idlen) {
        if (vob->spu_streams[index].id)
            free(vob->spu_streams[index].id);
        vob->spu_streams[index].id = malloc(idlen + 1);
        if (vob->spu_streams[index].id == NULL) {
            mp_msg(MSGT_VOBSUB,MSGL_FATAL,"vobsub_add_id: malloc failure");
            return -1;
        }
        vob->spu_streams[index].id[idlen] = 0;
        memcpy(vob->spu_streams[index].id, id, idlen);
    }
    vob->spu_streams_current = index;
    mp_msg(MSGT_IDENTIFY, MSGL_INFO, "ID_VOBSUB_ID=%d\n", index);
    if (id && idlen)
        mp_msg(MSGT_IDENTIFY, MSGL_INFO, "ID_VSID_%d_LANG=%s\n", index, vob->spu_streams[index].id);
    mp_msg(MSGT_VOBSUB,MSGL_V,"[vobsub] subtitle (vobsubid): %d language %s\n",
           index, vob->spu_streams[index].id);
#else
    if (id && idlen) {
        char name[256];
        strncpy(name, id, MIN(idlen, sizeof(name)));
        name[idlen] = '\0';
        NSString* class = [NSString stringWithCString:name encoding:NSASCIIStringEncoding];
        [vob->_parser addSubtitleClass:class atIndex:index];
        vob->_classIndex = index;
    }
#endif
    return 0;
}

static int
vobsub_add_timestamp(vobsub_t *vob, off_t filepos, int ms)
{
#if 0000
    packet_queue_t *queue;
    packet_t *pkt;
    if (vob->spu_streams == 0) {
        mp_msg(MSGT_VOBSUB,MSGL_WARN,"[vobsub] warning, binning some index entries.  Check your index file\n");
        return -1;
    }
    queue = vob->spu_streams + vob->spu_streams_current;
    if (packet_queue_grow(queue) >= 0) {
        pkt = queue->packets + (queue->packets_size - 1);
        pkt->filepos = filepos;
        pkt->pts100 = ms < 0 ? UINT_MAX : (unsigned int)ms * 90;
        return 0;
    }
    return -1;
#else
    float time = ms / 1000.f;
    [vob->_parser classIndex:vob->_classIndex
                addTimeStamp:time fileOffset:filepos];
    return 0;
#endif
}

static int
vobsub_parse_id(vobsub_t *vob, const char *line)
{
    // id: xx, index: n
    size_t idlen;
    const char *p, *q;
    p  = line;
    while (isspace(*p))
        ++p;
    q = p;
    while (isalpha(*q))
        ++q;
    idlen = q - p;
    if (idlen == 0)
        return -1;
    ++q;
    while (isspace(*q))
        ++q;
    if (strncmp("index:", q, 6))
        return -1;
    q += 6;
    while (isspace(*q))
        ++q;
    if (!isdigit(*q))
        return -1;
    return vobsub_add_id(vob, p, idlen, atoi(q));
}

static int
vobsub_parse_timestamp(vobsub_t *vob, const char *line)
{
    // timestamp: HH:MM:SS.mmm, filepos: 0nnnnnnnnn
    const char *p;
    int h, m, s, ms;
    off_t filepos;
    while (isspace(*line))
        ++line;
    p = line;
    while (isdigit(*p))
        ++p;
    if (p - line != 2)
        return -1;
    h = atoi(line);
    if (*p != ':')
        return -1;
    line = ++p;
    while (isdigit(*p))
        ++p;
    if (p - line != 2)
        return -1;
    m = atoi(line);
    if (*p != ':')
        return -1;
    line = ++p;
    while (isdigit(*p))
        ++p;
    if (p - line != 2)
        return -1;
    s = atoi(line);
    if (*p != ':')
        return -1;
    line = ++p;
    while (isdigit(*p))
        ++p;
    if (p - line != 3)
        return -1;
    ms = atoi(line);
    if (*p != ',')
        return -1;
    line = p + 1;
    while (isspace(*line))
        ++line;
    if (strncmp("filepos:", line, 8))
        return -1;
    line += 8;
    while (isspace(*line))
        ++line;
    if (! isxdigit(*line))
        return -1;
    filepos = strtol(line, NULL, 16);
    return vobsub_add_timestamp(vob, filepos, vob->delay + ms + 1000 * (s + 60 * (m + 60 * h)));
}

static int
vobsub_parse_size(vobsub_t *vob, const char *line)
{
    // size: WWWxHHH
    char *p;
    while (isspace(*line))
        ++line;
    if (!isdigit(*line))
        return -1;
    vob->orig_frame_width = strtoul(line, &p, 10);
    if (*p != 'x')
        return -1;
    ++p;
    vob->orig_frame_height = strtoul(p, NULL, 10);
    return 0;
}

static int
vobsub_parse_origin(vobsub_t *vob, const char *line)
{
    // org: X,Y
    char *p;
    while (isspace(*line))
        ++line;
    if (!isdigit(*line))
        return -1;
    vob->origin_x = strtoul(line, &p, 10);
    if (*p != ',')
        return -1;
    ++p;
    vob->origin_y = strtoul(p, NULL, 10);
    return 0;
}

static int
vobsub_parse_palette(vobsub_t *vob, const char *line)
{
    // palette: XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX, XXXXXX
    unsigned int n;
    n = 0;
    while (1) {
        const char *p;
        int r, g, b, y, u, v, tmp;
        while (isspace(*line))
            ++line;
        p = line;
        while (isxdigit(*p))
            ++p;
        if (p - line != 6)
            return -1;
        tmp = strtoul(line, NULL, 16);
        r = tmp >> 16 & 0xff;
        g = tmp >> 8 & 0xff;
        b = tmp & 0xff;
        y = MIN(MAX((int)(0.1494 * r + 0.6061 * g + 0.2445 * b), 0), 0xff);
        u = MIN(MAX((int)(0.6066 * r - 0.4322 * g - 0.1744 * b) + 128, 0), 0xff);
        v = MIN(MAX((int)(-0.08435 * r - 0.3422 * g + 0.4266 * b) + 128, 0), 0xff);
        vob->palette[n++] = y << 16 | u << 8 | v;
        if (n == 16)
            break;
        if (*p == ',')
            ++p;
        line = p;
    }
    vob->have_palette = 1;
    return 0;
}

static int
vobsub_parse_custom(vobsub_t *vob, const char *line)
{
    //custom colors: OFF/ON(0/1)
    if ((strncmp("ON", line + 15, 2) == 0)||strncmp("1", line + 15, 1) == 0)
        vob->custom=1;
    else if ((strncmp("OFF", line + 15, 3) == 0)||strncmp("0", line + 15, 1) == 0)
        vob->custom=0;
    else
        return -1;
    return 0;
}

static int
vobsub_parse_cuspal(vobsub_t *vob, const char *line)
{
    //colors: XXXXXX, XXXXXX, XXXXXX, XXXXXX
    unsigned int n;
    n = 0;
    line += 40;
    while(1){
    	const char *p;
        while (isspace(*line))
            ++line;
        p=line;
        while (isxdigit(*p))
            ++p;
        if (p - line !=6)
            return -1;
        vob->cuspal[n++] = strtoul(line, NULL,16);
        if (n==4)
            break;
        if(*p == ',')
            ++p;
        line = p;
    }
    return 0;
}

/* don't know how to use tridx */
static int
vobsub_parse_tridx(const char *line)
{
    //tridx: XXXX
    int tridx;
    tridx = strtoul((line + 26), NULL, 16);
    tridx = ((tridx&0x1000)>>12) | ((tridx&0x100)>>7) | ((tridx&0x10)>>2) | ((tridx&1)<<3);
    return tridx;
}

static int
vobsub_parse_delay(vobsub_t *vob, const char *line)
{
    int h, m, s, ms;
    int forward = 1;
    if (*(line + 7) == '+'){
    	forward = 1;
        line++;
    }
    else if (*(line + 7) == '-'){
    	forward = -1;
        line++;
    }
    mp_msg(MSGT_SPUDEC,MSGL_V, "forward=%d", forward);
    h = atoi(line + 7);
    mp_msg(MSGT_VOBSUB,MSGL_V, "h=%d," ,h);
    m = atoi(line + 10);
    mp_msg(MSGT_VOBSUB,MSGL_V, "m=%d,", m);
    s = atoi(line + 13);
    mp_msg(MSGT_VOBSUB,MSGL_V, "s=%d,", s);
    ms = atoi(line + 16);
    mp_msg(MSGT_VOBSUB,MSGL_V, "ms=%d", ms);
    vob->delay = (ms + 1000 * (s + 60 * (m + 60 * h))) * forward;
    return 0;
}

static int
vobsub_set_lang(const char *line)
{
    if (vobsub_id == -1)
        vobsub_id = atoi(line + 8);
    return 0;
}

static int
vobsub_parse_forced_subs(vobsub_t *vob, const char *line)
{
    const char *p;
    
    p  = line;
    while (isspace(*p))
        ++p;
    
    if (strncasecmp("on",p,2) == 0){
	    vob->forced_subs=~0;
	    return 0;
    } else if (strncasecmp("off",p,3) == 0){
	    vob->forced_subs=0;
	    return 0;
    }
	
    return -1;
}

static int
vobsub_parse_one_line(vobsub_t *vob, rar_stream_t *fd)
{
    ssize_t line_size;
    int res = -1;
	size_t line_reserve = 0;
	char *line = NULL;
    do {
        line_size = vobsub_getline(&line, &line_reserve, fd);
        if (line_size < 0) {
            break;
        }
        if (*line == 0 || *line == '\r' || *line == '\n' || *line == '#')
            continue;
        else if (strncmp("langidx:", line, 8) == 0)
            res = vobsub_set_lang(line);
        else if (strncmp("delay:", line, 6) == 0)
            res = vobsub_parse_delay(vob, line);
        else if (strncmp("id:", line, 3) == 0)
            res = vobsub_parse_id(vob, line + 3);
        else if (strncmp("palette:", line, 8) == 0)
            res = vobsub_parse_palette(vob, line + 8);
        else if (strncmp("size:", line, 5) == 0)
            res = vobsub_parse_size(vob, line + 5);
        else if (strncmp("org:", line, 4) == 0)
            res = vobsub_parse_origin(vob, line + 4);
        else if (strncmp("timestamp:", line, 10) == 0)
            res = vobsub_parse_timestamp(vob, line + 10);
        else if (strncmp("custom colors:", line, 14) == 0)
            //custom colors: ON/OFF, tridx: XXXX, colors: XXXXXX, XXXXXX, XXXXXX,XXXXXX
            res = vobsub_parse_cuspal(vob, line) + vobsub_parse_tridx(line) + vobsub_parse_custom(vob, line);
        else if (strncmp("forced subs:", line, 12) == 0)
            res = vobsub_parse_forced_subs(vob, line + 12);
        else {
            mp_msg(MSGT_VOBSUB,MSGL_V, "vobsub: ignoring %s", line);
            continue;
        }
        if (res < 0)
            mp_msg(MSGT_VOBSUB,MSGL_ERR,  "ERROR in %s", line);
        break;
    } while (1);
    if (line)
        free(line);
    return res;
}

int
vobsub_parse_ifo(void* this, const char *const name, unsigned int *palette, unsigned int *width, unsigned int *height, int force,
                 int sid, char *langid)
{
    vobsub_t *vob = (vobsub_t*)this;
    int res = -1;
    rar_stream_t *fd = rar_open(name, "rb");
    if (fd == NULL) {
        if (force)
            mp_msg(MSGT_VOBSUB,MSGL_ERR, "VobSub: Can't open IFO file\n");
    } else {
        // parse IFO header
        unsigned char block[0x800];
        const char *const ifo_magic = "DVDVIDEO-VTS";
        if (rar_read(block, sizeof(block), 1, fd) != 1) {
            if (force)
                mp_msg(MSGT_VOBSUB,MSGL_ERR, "VobSub: Can't read IFO header\n");
        } else if (memcmp(block, ifo_magic, strlen(ifo_magic) + 1))
            mp_msg(MSGT_VOBSUB,MSGL_ERR, "VobSub: Bad magic in IFO header\n");
        else {
            unsigned long pgci_sector = block[0xcc] << 24 | block[0xcd] << 16
            | block[0xce] << 8 | block[0xcf];
            int standard = (block[0x200] & 0x30) >> 4;
            int resolution = (block[0x201] & 0x0c) >> 2;
            *height = standard ? 576 : 480;
            *width = 0;
            switch (resolution) {
                case 0x0:
                    *width = 720;
                    break;
                case 0x1:
                    *width = 704;
                    break;
                case 0x2:
                    *width = 352;
                    break;
                case 0x3:
                    *width = 352;
                    *height /= 2;
                    break;
                default:
                    mp_msg(MSGT_VOBSUB,MSGL_WARN,"Vobsub: Unknown resolution %d \n", resolution);
            }
            if (langid && 0 <= sid && sid < 32) {
                unsigned char *tmp = block + 0x256 + sid * 6 + 2;
                langid[0] = tmp[0];
                langid[1] = tmp[1];
                langid[2] = 0;
            }
            if (rar_seek(fd, pgci_sector * sizeof(block), SEEK_SET)
                || rar_read(block, sizeof(block), 1, fd) != 1)
                mp_msg(MSGT_VOBSUB,MSGL_ERR, "VobSub: Can't read IFO PGCI\n");
            else {
                unsigned long idx;
                unsigned long pgc_offset = block[0xc] << 24 | block[0xd] << 16
                | block[0xe] << 8 | block[0xf];
                for (idx = 0; idx < 16; ++idx) {
                    unsigned char *p = block + pgc_offset + 0xa4 + 4 * idx;
                    palette[idx] = p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3];
                }
                if(vob)
                    vob->have_palette = 1;
                res = 0;
            }
        }
        rar_close(fd);
    }
    return res;
}

void *
vobsub_open(const char *const name,const char *const ifo,const int force,void** spu,
            MSubtitleParser_SUB* parser)
{
    vobsub_t *vob = malloc(sizeof(vobsub_t));
    if (spu) {
        *spu = NULL;
    }
    if (vob) {
        char *buf;
        vob->custom = 0;
        vob->have_palette = 0;
        vob->orig_frame_width = 0;
        vob->orig_frame_height = 0;
#if 0000
        vob->spu_streams = NULL;
        vob->spu_streams_size = 0;
        vob->spu_streams_current = 0;
#else
        vob->_parser = parser;
        vob->_classIndex = 0;
#endif
        vob->delay = 0;
        vob->forced_subs=0;
        buf = malloc(strlen(name) + 5);
        if (buf) {
            rar_stream_t *fd;
            mpeg_t *mpg;
            /* read in the info file */
            if(!ifo) {
                strcpy(buf, name);
                strcat(buf, ".ifo");
                vobsub_parse_ifo(vob,buf, vob->palette, &vob->orig_frame_width, &vob->orig_frame_height, force, -1, NULL);
            }
            else {
                vobsub_parse_ifo(vob,ifo, vob->palette, &vob->orig_frame_width, &vob->orig_frame_height, force, -1, NULL);
            }
            /* read in the index */
            strcpy(buf, name);
            strcat(buf, ".idx");
            fd = rar_open(buf, "rb");
            if (fd == NULL) {
                if(force)
                    mp_msg(MSGT_VOBSUB,MSGL_ERR,"VobSub: Can't open IDX file\n");
                else {
                    free(buf);
                    free(vob);
                    return NULL;
                }
            }
            else {
                while (vobsub_parse_one_line(vob, fd) >= 0) {
                    /* NOOP */ ;
                }
                rar_close(fd);
            }
            /* if no palette in .idx then use custom colors */
            if ((vob->custom == 0)&&(vob->have_palette!=1)) {
                vob->custom = 1;
            }
            if (spu && vob->orig_frame_width && vob->orig_frame_height) {
                // FIXME: 0000
                //*spu = spudec_new_scaled_vobsub(vob->palette, vob->cuspal, vob->custom, vob->orig_frame_width, vob->orig_frame_height);
            }
#if 0000
#else
            [vob->_parser idxLoadEnded];
#endif
            /* read the indexed mpeg_stream */
            strcpy(buf, name);
            strcat(buf, ".sub");
            mpg = mpeg_open(buf);
            if (mpg == NULL) {
                if (force) {
                    mp_msg(MSGT_VOBSUB,MSGL_ERR,"VobSub: Can't open SUB file\n");
                }
                else {
                    free(buf);
                    free(vob);
                    return NULL;
                }
            }
            else {
#if 0000
                long last_pts_diff = 0;
#endif
                while (!mpeg_eof(mpg)) {
                    off_t pos = mpeg_tell(mpg);
                    if (mpeg_run(mpg) < 0) {
                        if (!mpeg_eof(mpg)) {
                            mp_msg(MSGT_VOBSUB,MSGL_ERR,"VobSub: mpeg_run error\n");
                        }
                        break;
                    }
                    if (mpg->packet_size) {
                        if ((mpg->aid & 0xe0) == 0x20) {
                            unsigned int sid = mpg->aid & 0x1f;
                            if (vobsub_ensure_spu_stream(vob, sid) >= 0)  {
#if 0000
                                packet_queue_t *queue = vob->spu_streams + sid;
                                /* get the packet to fill */
                                if (queue->packets_size == 0 && packet_queue_grow(queue)  < 0) {
                                    abort();
                                }
                                while (queue->current_index + 1 < queue->packets_size
                                       && queue->packets[queue->current_index + 1].filepos <= pos) {
                                    ++queue->current_index;
                                }
                                if (queue->current_index < queue->packets_size) {
                                    packet_t *pkt;
                                    if (queue->packets[queue->current_index].data) {
                                        /* insert a new packet and fix the PTS ! */
                                        packet_queue_insert(queue);
                                        queue->packets[queue->current_index].pts100 =
                                        mpg->pts + last_pts_diff;
                                    }
                                    pkt = queue->packets + queue->current_index;
                                    if (pkt->pts100 != UINT_MAX) {
                                        if (queue->packets_size > 1) {
                                            last_pts_diff = pkt->pts100 - mpg->pts;
                                        }
                                        else {
                                            pkt->pts100 = mpg->pts;
                                        }
                                        /* FIXME: should not use mpg_sub internal informations, make a copy */
                                        pkt->data = mpg->packet;
                                        pkt->size = mpg->packet_size;
                                        mpg->packet = NULL;
                                        mpg->packet_reserve = 0;
                                        mpg->packet_size = 0;
                                    }
                                }
#else
                                if ([vob->_parser classIndex:sid
                                                     setData:mpg->packet
                                                    dataSize:mpg->packet_size
                                                atFileOffset:pos]) {
                                    mpg->packet = NULL;
                                    mpg->packet_reserve = 0;
                                    mpg->packet_size = 0;
                                }
#endif
                            }
                            else {
                                mp_msg(MSGT_VOBSUB,MSGL_WARN, "don't know what to do with subtitle #%u\n", sid);
                            }
                        }
                    }
                }
#if 0000
                vob->spu_streams_current = vob->spu_streams_size;
                while (vob->spu_streams_current-- > 0) {
                    vob->spu_streams[vob->spu_streams_current].current_index = 0;
                }
#endif
                mpeg_free(mpg);
            }
            free(buf);
        }
    }
    return vob;
}

void
vobsub_close(void *this)
{
    vobsub_t *vob = (vobsub_t *)this;
#if 0000
    if (vob->spu_streams) {
        while (vob->spu_streams_size--)
            packet_queue_destroy(vob->spu_streams + vob->spu_streams_size);
        free(vob->spu_streams);
    }
#endif
    free(vob);
}

#if 0000
unsigned int
vobsub_get_indexes_count(void *vobhandle)
{
    vobsub_t *vob = (vobsub_t *) vobhandle;
    return vob->spu_streams_size;
}

char *
vobsub_get_id(void *vobhandle, unsigned int index)
{
    vobsub_t *vob = (vobsub_t *) vobhandle;
    return (index < vob->spu_streams_size) ? vob->spu_streams[index].id : NULL;
}
#endif
unsigned int 
vobsub_get_forced_subs_flag(void const * const vobhandle)
{
    if (vobhandle)
        return ((vobsub_t*) vobhandle)->forced_subs;
    else
        return 0;
}

#if 0000
int
vobsub_set_from_lang(void *vobhandle, unsigned char * lang)
{
    int i;
    vobsub_t *vob= (vobsub_t *) vobhandle;
    while(lang && strlen(lang) >= 2){
        for(i=0; i < vob->spu_streams_size; i++)
            if (vob->spu_streams[i].id)
                if ((strncmp(vob->spu_streams[i].id, lang, 2)==0)){
                    vobsub_id=i;
                    mp_msg(MSGT_VOBSUB, MSGL_INFO, "Selected VOBSUB language: %d language: %s\n", i, vob->spu_streams[i].id);
                    return 0;
                }
        lang+=2;while (lang[0]==',' || lang[0]==' ') ++lang;
    }
    mp_msg(MSGT_VOBSUB, MSGL_WARN, "No matching VOBSUB language found!\n");
    return -1;
}

int
vobsub_get_packet(void *vobhandle, float pts,void** data, int* timestamp) {
    vobsub_t *vob = (vobsub_t *)vobhandle;
    unsigned int pts100 = 90000 * pts;
    if (vob->spu_streams && 0 <= vobsub_id && (unsigned) vobsub_id < vob->spu_streams_size) {
        packet_queue_t *queue = vob->spu_streams + vobsub_id;
        while (queue->current_index < queue->packets_size) {
            packet_t *pkt = queue->packets + queue->current_index;
            if (pkt->pts100 != UINT_MAX)
                if (pkt->pts100 <= pts100) {
                    ++queue->current_index;
                    *data = pkt->data;
                    *timestamp = pkt->pts100;
                    return pkt->size;
                } else break;
                else
                    ++queue->current_index;
        }
    }
    return -1;
}

int
vobsub_get_next_packet(void *vobhandle, void** data, int* timestamp)
{
    vobsub_t *vob = (vobsub_t *)vobhandle;
    if (vob->spu_streams && 0 <= vobsub_id && (unsigned) vobsub_id < vob->spu_streams_size) {
        packet_queue_t *queue = vob->spu_streams + vobsub_id;
        if (queue->current_index < queue->packets_size) {
            packet_t *pkt = queue->packets + queue->current_index;
            ++queue->current_index;
            *data = pkt->data;
            *timestamp = pkt->pts100;
            return pkt->size;
        }
    }
    return -1;
}

void vobsub_seek(void * vobhandle, float pts)
{
    vobsub_t * vob = (vobsub_t *)vobhandle;
    packet_queue_t * queue;
    int seek_pts100 = (int)pts * 90000;
    
    if (vob->spu_streams && 0 <= vobsub_id && (unsigned) vobsub_id < vob->spu_streams_size) {
        /* do not seek if we don't know the id */
        if (vobsub_get_id(vob, vobsub_id) == NULL)
            return;
        queue = vob->spu_streams + vobsub_id;
        queue->current_index = 0;
        while ((queue->packets + queue->current_index)->pts100 < seek_pts100)
            ++queue->current_index;
        if (queue->current_index > 0)
            --queue->current_index;
    }
}

void
vobsub_reset(void *vobhandle)
{
    vobsub_t *vob = (vobsub_t *)vobhandle;
    if (vob->spu_streams) {
        unsigned int n = vob->spu_streams_size;
        while (n-- > 0)
            vob->spu_streams[n].current_index = 0;
    }
}
#endif
////////////////////////////////////////////////////////////////////////////////
#pragma mark -

@implementation MSubtitleParser_SUB

- (id)initWithURL:(NSURL*)subtitleURL
{
    if (self = [super initWithURL:subtitleURL]) {
        _subtitles = [NSMutableArray arrayWithCapacity:2];
        _fileOffsets = [NSMutableArray arrayWithCapacity:2];
    }
    return self;
}

- (NSArray*)parseWithOptions:(NSDictionary*)options error:(NSError**)error
{
    NSString* name = [[_subtitleURL path] stringByDeletingPathExtension];
    const char* path = [name UTF8String];
    //const char* path = [name cStringUsingEncoding:NSASCIIStringEncoding];
    const char* spudec_ifo = 0;
    int force = 0;
    void* vo_spudec = 0;
    vobsub_t* vob = vobsub_open(path, spudec_ifo, force, &vo_spudec, self);
    if (vob) {
        /*
        inited_flags|=INITED_VOBSUB;
        vobsub_set_from_lang(vob, dvdsub_lang);
        // check if vobsub requested only to display forced subtitles
        forced_subs_only=vobsub_get_forced_subs_flag(vob);
        
        // setup global sub numbering
        global_sub_indices[SUB_SOURCE_VOBSUB] = global_sub_size; // the global # of the first vobsub.
        global_sub_size += vobsub_get_indexes_count(vob);
        if (vo_spudec) {
            spudec_free(vo_spudec);
        }
         */
        vobsub_close(vob);
        return _subtitles;
    }
    return nil;
}

@end

@implementation MSubtitleParser_SUB (Private)

- (int)subtitlesCount { return [_fileOffsets count]; }

- (void)addSubtitleClass:(NSString*)class atIndex:(int)index
{
    TRACE(@"%s class=%@ index=%d", __PRETTY_FUNCTION__, class, index);
    MSubtitle* subtitle = [[[MSubtitle alloc] initWithURL:_subtitleURL type:@"SUB"] autorelease];
    [subtitle setName:class];
    [_subtitles addObject:subtitle];
    [_fileOffsets addObject:[NSMutableDictionary dictionaryWithCapacity:1024]];
}

- (void)classIndex:(int)classIndex
      addTimeStamp:(float)time fileOffset:(int)fileOffset
{
    //TRACE(@"%s class=%@ time=%g, offset=%d", __PRETTY_FUNCTION__,
    //      [[_subtitles objectAtIndex:classIndex] name], time, fileOffset);
    NSMutableDictionary* offsetDict = [_fileOffsets objectAtIndex:classIndex];
    [offsetDict setObject:[NSNumber numberWithFloat:time]
                   forKey:[NSNumber numberWithInt:fileOffset]];
}

- (void)idxLoadEnded
{
    _sortedOffsets = [NSMutableArray arrayWithCapacity:[_fileOffsets count]];

    NSDictionary* offsetDict;
    NSMutableArray* offsets;
    int i, count = [_fileOffsets count];
    for (i = 0; i < count; i++) {
        offsetDict = [_fileOffsets objectAtIndex:i];
        offsets = [NSMutableArray arrayWithArray:[offsetDict allKeys]];
        [offsets sortUsingSelector:@selector(compare:)];
        [_sortedOffsets addObject:offsets];
        _lastSearchedIndex[i] = 0;
    }
}

- (BOOL)classIndex:(int)classIndex
           setData:(void*)data dataSize:(int)dataSize atFileOffset:(int)fileOffset
{
    NSArray* offsets = [_sortedOffsets objectAtIndex:classIndex];

    int i, count = [offsets count];
    NSNumber* offset, *nextOffset = nil;
    for (i = _lastSearchedIndex[classIndex]; i < count; i++) {
        offset = [offsets objectAtIndex:i];
        nextOffset = (i < count - 1) ? [offsets objectAtIndex:i + 1] : nil;
        if (!nextOffset || fileOffset < [nextOffset intValue]) {
            _lastSearchedIndex[classIndex] = i;
            break;
        }
    }
    if (0 <= i) {
        NSData* data = [NSData dataWithBytes:data length:dataSize];
        NSImage* image = [[[NSImage alloc] initWithData:data] autorelease];

        NSDictionary* offsetDict = [_fileOffsets objectAtIndex:classIndex];
        float beginTime = [[offsetDict objectForKey:offset] floatValue];
        float endTime   = (nextOffset == nil) ? (beginTime + 5) :
                          [[offsetDict objectForKey:nextOffset] floatValue];
        MSubtitle* subtitle = [_subtitles objectAtIndex:classIndex];
        [subtitle addImage:image beginTime:beginTime endTime:endTime];
        return TRUE;
    }
    return FALSE;
}

@end