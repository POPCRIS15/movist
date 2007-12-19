//
//  Movist
//
//  Copyright 2006, 2007 Yong-Hoe Kim. All rights reserved.
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

#import "FullNavListView.h"

#import "FullNavView.h"
#import "FullNavItems.h"

@interface FullNavItem (Drawing)

- (void)drawInRect:(NSRect)rect withAttributes:(NSDictionary*)attrs;
- (void)drawInRect:(NSRect)rect withAttributes:(NSDictionary*)attrs
        scrollSize:(float)scrollSize
          nameSize:(NSSize*)nameSize nameRect:(NSRect*)nameRect;

@end

@implementation FullNavItem (Drawing)

- (void)drawInRect:(NSRect)rect withAttributes:(NSDictionary*)attrs
{
    [self drawInRect:rect withAttributes:attrs
          scrollSize:0 nameSize:nil nameRect:nil];
}

- (void)drawInRect:(NSRect)rect withAttributes:(NSDictionary*)attrs
        scrollSize:(float)scrollSize
          nameSize:(NSSize*)nameSize nameRect:(NSRect*)nameRect
{
    float LEFT_MARGIN = 0;
    float CONTAINER_MARK_WIDTH = (float)(int)(rect.size.width * 0.05);
    NSSize size = [_name sizeWithAttributes:attrs];
    NSRect rc = NSMakeRect(rect.origin.x + LEFT_MARGIN,
                           rect.origin.y + (rect.size.height - size.height) / 2,
                           rect.size.width - LEFT_MARGIN,
                           size.height);
    if ([self hasSubContents]) {
        rc.size.width -= CONTAINER_MARK_WIDTH;
    }
    if (nameSize) {
        *nameSize = size;
    }
    if (nameRect) {
        *nameRect = rc;
        //[[NSColor cyanColor] set];
        //NSFrameRect(*nameRect);
    }

    float unitSize = size.width + 100;  // gap between name & name
    if (unitSize < scrollSize) {
        scrollSize -= unitSize;
    }
    if (0 == scrollSize) {
        [_name drawInRect:rc withAttributes:attrs];
    }
    else {
        rc.origin.x -= scrollSize;
        rc.size.width += scrollSize;
        [_name drawInRect:rc withAttributes:attrs];

        if (unitSize < rc.size.width) {
            rc.origin.x += unitSize;
            rc.size.width -= unitSize;
            [_name drawInRect:rc withAttributes:attrs];
        }
    }
    // container mark
    if ([self hasSubContents]) {
        rc.size.width = CONTAINER_MARK_WIDTH;
        rc.origin.x = NSMaxX(rect) - rc.size.width + 5;
        [@">" drawInRect:rc withAttributes:attrs];
    }
    //[[NSColor greenColor] set];
    //NSFrameRect(rect);
}

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark

@interface FullNavSelBox : NSView
{
    NSImage* _bgImage;
}

- (id)initWithFrame:(NSRect)frame;

@end

@implementation FullNavSelBox

- (id)initWithFrame:(NSRect)frame
{
    if (self = [super initWithFrame:frame]) {
        NSSize size = frame.size;
        _bgImage = [[NSImage alloc] initWithSize:size];
        [_bgImage lockFocus];
            NSImage* lImage = [NSImage imageNamed:@"FSNavSelBoxLeft"];
            NSImage* cImage = [NSImage imageNamed:@"FSNavSelBoxCenter"];
            NSImage* rImage = [NSImage imageNamed:@"FSNavSelBoxRight"];
            NSRect rc;
            rc.origin.x = 0, rc.size.width = [lImage size].width;
            rc.origin.y = 0, rc.size.height = size.height;
            [lImage drawInRect:rc fromRect:NSZeroRect
                     operation:NSCompositeSourceOver fraction:1.0];
            rc.origin.x = size.width - [rImage size].width;
            rc.size.width = [rImage size].width;
            [rImage drawInRect:rc fromRect:NSZeroRect
                     operation:NSCompositeSourceOver fraction:1.0];
            rc.origin.x = [lImage size].width;
            rc.size.width = size.width - [lImage size].width - [rImage size].width;
            [cImage drawInRect:rc fromRect:NSZeroRect
                     operation:NSCompositeSourceOver fraction:1.0];
            //[[NSColor redColor] set];
            //NSFrameRect([self bounds]);
        [_bgImage unlockFocus];
    }
    return self;
}

- (void)dealloc
{
    [_bgImage release];
    [super dealloc];
}

- (void)drawRect:(NSRect)rect
{
    [_bgImage drawInRect:[self bounds] fromRect:NSZeroRect
               operation:NSCompositePlusLighter fraction:1.0];
}

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark

@implementation FullNavListView

#define ITEM_HSCROLL_FADE_SIZE    _itemHeight

- (id)initWithFrame:(NSRect)frame window:(NSWindow*)window
{
    if (self = [super initWithFrame:frame]) {
        _itemHeight = (float)(int)(frame.size.height / 10);

        CIColor* c0 = [CIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0];
        CIColor* c1 = [CIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.0];
        CIVector* p0 = [CIVector vectorWithX:0 Y:_itemHeight];
        CIVector* p1 = [CIVector vectorWithX:0 Y:0];
        _tFilter = [[CIFilter filterWithName:@"CILinearGradient"] retain];
        [_tFilter setValue:p0 forKey:@"inputPoint0"];
        [_tFilter setValue:p1 forKey:@"inputPoint1"];
        [_tFilter setValue:c0 forKey:@"inputColor0"];
        [_tFilter setValue:c1 forKey:@"inputColor1"];

        p0 = [CIVector vectorWithX:0 Y:0];
        p1 = [CIVector vectorWithX:0 Y:_itemHeight];
        _bFilter = [[CIFilter filterWithName:@"CILinearGradient"] retain];
        [_bFilter setValue:p0 forKey:@"inputPoint0"];
        [_bFilter setValue:p1 forKey:@"inputPoint1"];
        [_bFilter setValue:c0 forKey:@"inputColor0"];
        [_bFilter setValue:c1 forKey:@"inputColor1"];

        p0 = [CIVector vectorWithX:0 Y:0];
        p1 = [CIVector vectorWithX:ITEM_HSCROLL_FADE_SIZE Y:0];
        _lFilter = [[CIFilter filterWithName:@"CILinearGradient"] retain];
        [_lFilter setValue:p0 forKey:@"inputPoint0"];
        [_lFilter setValue:p1 forKey:@"inputPoint1"];
        [_lFilter setValue:c0 forKey:@"inputColor0"];
        [_lFilter setValue:c1 forKey:@"inputColor1"];

        p0 = [CIVector vectorWithX:ITEM_HSCROLL_FADE_SIZE Y:0];
        p1 = [CIVector vectorWithX:0 Y:0];
        _rFilter = [[CIFilter filterWithName:@"CILinearGradient"] retain];
        [_rFilter setValue:p0 forKey:@"inputPoint0"];
        [_rFilter setValue:p1 forKey:@"inputPoint1"];
        [_rFilter setValue:c0 forKey:@"inputColor0"];
        [_rFilter setValue:c1 forKey:@"inputColor1"];
    }
    return self;
}

- (void)dealloc
{
    [_rFilter release];
    [_lFilter release];
    [_bFilter release];
    [_tFilter release];
    [super dealloc];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark

- (void)drawRect:(NSRect)rect
{
    //TRACE(@"%s rect=%@", __PRETTY_FUNCTION__, NSStringFromRect(rect));
    NSRect br = [self bounds];

    NSMutableParagraphStyle* paragraphStyle;
    paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];

    NSMutableDictionary* attrs;
    attrs = [[[NSMutableDictionary alloc] init] autorelease];
    [attrs setObject:[NSColor colorWithDeviceWhite:0.95 alpha:1.0]
              forKey:NSForegroundColorAttributeName];
    [attrs setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
    [attrs setObject:[NSFont boldSystemFontOfSize:38 * br.size.width / 640.0]
              forKey:NSFontAttributeName];

    CIContext* ciContext = [[NSGraphicsContext currentContext] CIContext];

    NSSize ns;
    NSRect r, nr;
    r.size.width = br.size.width;
    r.size.height = _itemHeight;
    r.origin.x = br.origin.x;
    r.origin.y = NSMaxY(br) - _itemHeight;
    CGPoint fadePoint;
    CGRect fadeRect = CGRectMake(0, 0, ITEM_HSCROLL_FADE_SIZE, r.size.height);
    int i, count = [_list count];
    for (i = 0; i < count; i++) {
        if (NSIntersectsRect(rect, r)) {
            if (i != [_list selectedIndex]) {
                [paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
                [[_list itemAtIndex:i] drawInRect:r withAttributes:attrs];
            }
            else {
                [paragraphStyle setLineBreakMode:NSLineBreakByClipping];
                [[_list itemAtIndex:i] drawInRect:r withAttributes:attrs
                                       scrollSize:_itemScrollSize
                                         nameSize:&ns nameRect:&nr];

                if (nr.size.width < ns.width) {
                    fadePoint.y = NSMinY(r);
                    fadePoint.x = NSMinX(nr);
                    if (0 < _itemScrollSize) {
                        [ciContext drawImage:[_lFilter valueForKey:@"outputImage"]
                                     atPoint:fadePoint fromRect:fadeRect];
                    }
                    fadePoint.x = NSMaxX(nr) - ITEM_HSCROLL_FADE_SIZE;
                    [ciContext drawImage:[_rFilter valueForKey:@"outputImage"]
                                 atPoint:fadePoint fromRect:fadeRect];
                    if (_itemScrollRect.size.width == 0) {
                        _itemScrollRect = nr;
                        [NSTimer scheduledTimerWithTimeInterval:1.0
                                    target:self selector:@selector(startScrollTimer:)
                                    userInfo:nil repeats:FALSE];
                    }
                }
            }
        }
        r.origin.y -= r.size.height;
    }

    rect = [self visibleRect];
    if (rect.size.height < _itemHeight * count) {  // vertical scrollable
        NSRect fr = [self frame];
        if (rect.size.height < NSMaxY(fr)) {
            [ciContext drawImage:[_tFilter valueForKey:@"outputImage"]
                         atPoint:CGPointMake(NSMinX(rect), NSMaxY(rect) - _itemHeight)
                        fromRect:CGRectMake(0, 0, rect.size.width, _itemHeight)];
        }
        if (fr.origin.y < 0) {
            [ciContext drawImage:[_bFilter valueForKey:@"outputImage"]
                         atPoint:CGPointMake(NSMinX(rect), NSMinY(rect))
                        fromRect:CGRectMake(0, 0, rect.size.width, _itemHeight)];
        }
    }

    //[[NSColor yellowColor] set];
    //NSFrameRect(br);
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark

- (void)startScrollTimer:(NSTimer*)timer
{
    if (0 < _itemScrollRect.size.width) {
        _itemScrollSize = 0;
        _itemScrollTimer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                    target:self selector:@selector(scrollItemName:)
                                    userInfo:nil repeats:TRUE];
    }
}

- (void)scrollItemName:(NSTimer*)timer
{
    _itemScrollSize++;
    [self setNeedsDisplayInRect:_itemScrollRect];
}

- (void)resetItemScroll
{
    TRACE(@"%s", __PRETTY_FUNCTION__);
    _itemScrollRect.size.width = 0;
    _itemScrollSize = 0;
    [_itemScrollTimer invalidate];
    _itemScrollTimer = nil;
}

- (int)topIndex
{
    NSRect rc = [[self superview] bounds];
    int visibleCount = rc.size.height / _itemHeight;
    int halfCount = visibleCount / 2 - ((visibleCount % 2) ? 0 : 1);
    int sel = [_list selectedIndex];
    if ([_list count] <= visibleCount || sel <= halfCount) {
        return 0;
    }
    else if (sel < [_list count] - visibleCount / 2) {
        return sel - halfCount;
    }
    else {
        return [_list count] - visibleCount;
    }
}

- (NSRect)calcViewRect
{
    float height = [_list count] * _itemHeight;
    
    NSRect rc = [[self superview] bounds];
    rc.origin.y = NSMaxY(rc) - height;
    rc.size.height = height;

    rc.origin.y += [self topIndex] * _itemHeight;
    //TRACE(@"listViewRect=%@", NSStringFromRect(rc));
    return rc;
}

#define SEL_BOX_HMARGIN     60
#define SEL_BOX_VMARGIN     37

- (NSView*)createSelBox
{
    // cannot use -selBoxRect here because it refers _selBox.
    NSRect frame = [self bounds];
    frame.size.width += SEL_BOX_HMARGIN * 2;
    frame.size.height = _itemHeight + SEL_BOX_VMARGIN * 2;
    _selBox = [[FullNavSelBox alloc] initWithFrame:frame];
    return _selBox;
}

- (NSRect)selBoxRect
{
    if ([_list count] == 0) {
        return NSZeroRect;
    }
    else {
        NSRect rc = [[self superview] bounds];
        rc.origin.y = NSMaxY(rc) - _itemHeight -
                        ([_list selectedIndex] - [self topIndex]) * _itemHeight;
        rc.size.height = _itemHeight;
        rc = NSInsetRect(rc, -SEL_BOX_HMARGIN, -SEL_BOX_VMARGIN);
        return [[self superview] convertRect:rc toView:[_selBox superview]];
    }
}

- (void)slideSelBox
{
    TRACE(@"%s", __PRETTY_FUNCTION__);
    [self resetItemScroll];

    if (_animation && [_animation isAnimating]) {
        [_animation stopAnimation];/*
        NSArray* array = [_animation viewAnimations];
        NSDictionary* dict = [array objectAtIndex:0];
        NSValue* value = [dict objectForKey:NSViewAnimationEndFrameKey];
        [self setFrame:[value rectValue]];
        [self display];
        dict = [array objectAtIndex:1];
        value = [dict objectForKey:NSViewAnimationEndFrameKey];
        [_selBox setFrame:[value rectValue]];*/
        [_animation release];
    }

    NSRect frame = [self calcViewRect];
    NSRect selBoxRect = [self selBoxRect];

    NSArray* array = [NSArray arrayWithObjects:
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       self, NSViewAnimationTargetKey,
                       [NSValue valueWithRect:frame], NSViewAnimationEndFrameKey,
                       nil],
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       _selBox, NSViewAnimationTargetKey,
                       [NSValue valueWithRect:selBoxRect], NSViewAnimationEndFrameKey,
                       nil],
                      nil];
    NSViewAnimation* animation;
    animation = [[NSViewAnimation alloc] initWithViewAnimations:array];
    [animation setAnimationBlockingMode:NSAnimationNonblocking];
    [animation setAnimationCurve:NSAnimationLinear];
    [animation setDuration:0.2];
    [animation setDelegate:self];
    [animation startAnimation];

    _animation = animation;
}

- (void)animatioinDidEnd:(NSAnimation*)animation
{
    TRACE(@"%s", __PRETTY_FUNCTION__);
    if (_animation == animation) {
        [_animation release];
        _animation = nil;
    }
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark

- (void)setNavList:(FullNavList*)list
{
    TRACE(@"%s", __PRETTY_FUNCTION__);
    [self resetItemScroll];

    _list = list;   // no retain
    
    [self setFrame:[self calcViewRect]];
    [[self superview] display];
    [_selBox setFrame:[self selBoxRect]];
    [[_selBox superview] display];
}

@end