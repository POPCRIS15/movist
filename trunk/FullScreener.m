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

#import "FullScreener.h"

#import "MMovieView.h"
#import "MainWindow.h"
#import "FullWindow.h"
#import "PlayPanel.h"

@implementation FullScreener

- (id)initWithMainWindow:(MainWindow*)mainWindow
               playPanel:(PlayPanel*)playPanel
            blackScreens:(BOOL)blackScreens
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if (self = [super init]) {
        _mainWindow = [mainWindow retain];
        _movieView = [[_mainWindow movieView] retain];
        _playPanel = [playPanel retain];
        _fullWindow = [[FullWindow alloc] initWithScreen:[_mainWindow screen]
                                               playPanel:_playPanel];

        _movieViewRect = [_movieView frame];

        // for animation effect
        [self initAnimation];

        // for black-screens effect
        if (blackScreens && 1 < [[NSScreen screens] count]) {
            _screenFaders = [[NSMutableArray alloc] initWithCapacity:1];
        }
    }
    return self;
}

- (void)dealloc
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    [_screenFaders release];
    [_fullWindow release];
    [_mainWindow release];
    [_movieView release];
    [_movieURL release];
    [super dealloc];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -

- (FullWindow*)fullWindow { return _fullWindow; }

- (void)setEffect:(int)effect
{
    //TRACE(@"%s %d", __PRETTY_FUNCTION__, effect);
    _effect = effect;
}

- (void)setMovieURL:(NSURL*)movieURL
{
    //TRACE(@"%s \"%@\"", __PRETTY_FUNCTION__, [movieURL absoluteString]);
    [movieURL retain], [_movieURL release], _movieURL = movieURL;
    [_fullWindow setMovieURL:_movieURL];
    [_playPanel setMovieURL:_movieURL];

    if ([self isNavigatable]) {
        [_fullWindow selectMovie:movieURL];
    }
}

// black-screens effect
// based on patch of Min-Jun Park <pmjpmj@gmail.com>.

#define SCREEN_FADE_DURATION    0.25

- (void)beginBlackScreens
{
    assert(_screenFaders != nil);

    NSScreen* screen;
    ScreenFader* fader;
    NSEnumerator* enumerator = [[NSScreen screens] objectEnumerator];
    while (screen = [enumerator nextObject]) {
        if ([_mainWindow screen] == screen) {
            continue;
        }
        fader = [ScreenFader screenFaderWithScreen:screen];
        [fader fadeOutAsync:SCREEN_FADE_DURATION];

        [_screenFaders addObject:fader];
    }
}

- (void)endBlackScreens
{
    assert(_screenFaders != nil);
    
    ScreenFader* fader;
    NSEnumerator* enumerator = [_screenFaders objectEnumerator];
    while (fader = [enumerator nextObject]) {
        [fader fadeInAsync:SCREEN_FADE_DURATION];
    }
    [_screenFaders removeAllObjects];
}

- (void)showMainMenuAndDock
{
    SystemUIMode systemUIMode;
    GetSystemUIMode(&systemUIMode, 0);
    if (systemUIMode == kUIModeAllSuppressed) {
        SetSystemUIMode(_normalSystemUIMode, _normalSystemUIOptions);
    }
}

- (void)hideMainMenuAndDock
{
    GetSystemUIMode(&_normalSystemUIMode, &_normalSystemUIOptions);

    // if currently in menu-bar-screen, hide system UI elements(main-menu, dock)
    NSScreen* menuBarScreen = [[NSScreen screens] objectAtIndex:0];
    if (_screenFaders ||
        [[_mainWindow screen] isEqualTo:menuBarScreen]) {
        // if cursor is in dock, move cursor out of dock area to hide dock.
        NSRect rc = [menuBarScreen visibleFrame];
        NSPoint p = [NSEvent mouseLocation];
        if (!NSPointInRect(p, rc)) {
            float margin = 20;   // some margin needed
            if (p.x < NSMinX(rc)) {         // left-side dock
                p.x = NSMinX(rc) + margin;
            }
            else if (NSMaxX(rc) <= p.x) {   // right-side dock
                p.x = NSMaxX(rc) - margin;
            }
            else if (p.y < NSMinY(rc)) {    // bottom-side dock
                p.y = NSMinY(rc) + margin;
            }
            CGDisplayMoveCursorToPoint([_movieView displayID],
                                       CGPointMake(p.x, NSMaxY(rc) - p.y));
        }
        SetSystemUIMode(kUIModeAllSuppressed, 0);
    }
}

#define NAV_FADE_DURATION       1.0
#define FADE_EFFECT_DURATION    0.5

- (void)beginFullScreen
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if (_screenFaders) {
        [self beginBlackScreens];
    }

    BOOL forNavigation = (_movieURL == nil);

    float rate;         // for FS_EFFECT_FADE
    ScreenFader* fader; // for FS_EFFECT_FADE
    float fadeDuration = (forNavigation) ? NAV_FADE_DURATION : FADE_EFFECT_DURATION;
    int effect = (forNavigation) ? FS_EFFECT_FADE : _effect;
    if (effect == FS_EFFECT_FADE) {
        [NSCursor setHiddenUntilMouseMoves:TRUE];
        rate = [[_movieView movie] rate];
        [[_movieView movie] setRate:0.0];
        fader = [ScreenFader screenFaderWithScreen:[_mainWindow screen]];
        [fader fadeOut:fadeDuration];
    }

    [self hideMainMenuAndDock];

    switch (effect) {
        case FS_EFFECT_FADE :
            // already fade-out
            break;
        case FS_EFFECT_ANIMATION :
            [NSCursor setHiddenUntilMouseMoves:TRUE];
            [_fullWindow setFrame:_restoreRect display:TRUE];
            break;
        default :   // FS_EFFECT_NONE
            [NSCursor setHiddenUntilMouseMoves:TRUE];
            break;
    }

    BOOL subtitleVisible = [_movieView subtitleVisible];
    [_movieView setSubtitleVisible:FALSE];

    // move _movieView to _fullWindow from _mainWindow
    [_mainWindow setHasShadow:FALSE];
    [_mainWindow disableScreenUpdatesUntilFlush];
    [_movieView lockDraw];
    [_movieView removeFromSuperviewWithoutNeedingDisplay];
    [_fullWindow setMovieView:_movieView];
    [_fullWindow makeKeyAndOrderFront:nil];
    [_movieView unlockDraw];

    switch (effect) {
        case FS_EFFECT_FADE :
            [_fullWindow setFrame:[[_fullWindow screen] frame] display:TRUE];
            [_fullWindow addChildWindow:_mainWindow ordered:NSWindowBelow];
            [_fullWindow flushWindow];
            [_mainWindow flushWindow];
            [fader fadeIn:fadeDuration];
            [[_movieView movie] setRate:rate];
            break;
        case FS_EFFECT_ANIMATION :
            [self runBeginAnimation];
            break;
        default :   // FS_EFFECT_NONE
            [_fullWindow addChildWindow:_mainWindow ordered:NSWindowBelow];
            break;
    }

    [_movieView setSubtitleVisible:subtitleVisible];
    [_fullWindow setAcceptsMouseMovedEvents:TRUE];
}

- (void)endFullScreen
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    [_fullWindow setAcceptsMouseMovedEvents:FALSE];
    [_playPanel orderOut:self];     // immediately without fade-effect

    BOOL subtitleVisible = [_movieView subtitleVisible];
    [_movieView setSubtitleVisible:FALSE];

    float rate;         // for FS_EFFECT_FADE
    ScreenFader* fader; // for FS_EFFECT_FADE
    int effect = ([self isNavigatable]) ? FS_EFFECT_FADE : _effect;
    float fadeDuration = ([self isNavigatable]) ? NAV_FADE_DURATION : FADE_EFFECT_DURATION;
    switch (effect) {
        case FS_EFFECT_FADE :
            rate = [[_movieView movie] rate];
            [[_movieView movie] setRate:0.0];
            fader = [ScreenFader screenFaderWithScreen:[_mainWindow screen]];
            [fader fadeOut:fadeDuration];
            [_fullWindow removeChildWindow:_mainWindow];
            break;
        case FS_EFFECT_ANIMATION :
            [self runEndAnimation];
            break;
        default :   // FS_EFFECT_NONE
            [_fullWindow removeChildWindow:_mainWindow];
            break;
    }
    [_mainWindow disableScreenUpdatesUntilFlush];
    [_mainWindow disableFlushWindow];
    [_fullWindow orderOut:self];

    // move _movieView to _mainWindow from _fullWindow
    [_movieView lockDraw];
    [_movieView removeFromSuperviewWithoutNeedingDisplay];
    [[_mainWindow contentView] addSubview:_movieView];
    [_movieView setFrame:_movieViewRect];
    [_movieView updateMovieRect:FALSE];
    [_movieView unlockDraw];
    [_movieView display];

    [_mainWindow makeFirstResponder:_movieView];
    [_mainWindow makeKeyAndOrderFront:nil];
    [_mainWindow setHasShadow:TRUE];
    [_mainWindow enableFlushWindow];
    [_mainWindow flushWindowIfNeeded];

    [_movieView setSubtitleVisible:subtitleVisible];

    // restore system UI elements(main-menu, dock)
    [self showMainMenuAndDock];
    [NSCursor setHiddenUntilMouseMoves:FALSE];

    [_fullWindow release];
    _fullWindow = nil;

    if (effect == FS_EFFECT_FADE) {
        [_mainWindow flushWindow];
        [fader fadeIn:fadeDuration];
        [[_movieView movie] setRate:rate];
    }

    if (_screenFaders) {
        [self endBlackScreens];
    }
}

- (void)autoHidePlayPanel { [_playPanel autoHidePanel]; }

////////////////////////////////////////////////////////////////////////////////
#pragma mark navigation

- (BOOL)isNavigatable   { return [_fullWindow isNavigatable]; }
- (BOOL)isNavigating    { return [_fullWindow isNavigating]; }
- (BOOL)isPreviewing    { return [_fullWindow isPreviewing]; }

- (void)selectUpper     { [_fullWindow selectUpper]; }
- (void)selectLower     { [_fullWindow selectLower]; }
- (void)selectCurrent   { [_fullWindow selectMovie:_movieURL]; }

- (void)openCurrent     { [_fullWindow openCurrent]; }
- (BOOL)closeCurrent    { return [_fullWindow closeCurrent]; }
- (BOOL)canCloseCurrent { return [_fullWindow canCloseCurrent]; }

@end
