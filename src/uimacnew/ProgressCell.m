/******************************************************************************
 * Note -- loosely based on TorrentCell from Transmission (mostly just the .png
 * files.  Their original copyright is included below...
 *
 *
 * Copyright (c) 2006-2007 Transmission authors and contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *****************************************************************************/

#import "ProgressCell.h"

#define BAR_HEIGHT 12.0
#define BUTTONS_TOTAL_WIDTH 0.0

static NSImage *_ProgressWhite, *_ProgressBlue, *_ProgressGray, *_ProgressGreen,
		*_ProgressAdvanced, *_ProgressEndWhite, *_ProgressEndBlue,
		*_ProgressEndGray, *_ProgressEndGreen, *_ProgressLightGreen,
		*_ProgressEndAdvanced, * _ErrorImage;
static NSSize ZeroSize;

@implementation ProgressCell

+ (void) initialize
{
	NSSize startSize = NSMakeSize(100.0, BAR_HEIGHT);
	ZeroSize = NSMakeSize(0.0, 0.0);
	
	_ProgressWhite = [NSImage imageNamed: @"ProgressBarWhite.png"];
	[_ProgressWhite setScalesWhenResized: YES];
	
	_ProgressBlue = [NSImage imageNamed: @"ProgressBarBlue.png"];
	[_ProgressBlue setScalesWhenResized: YES];
	[_ProgressBlue setSize: startSize];
	
	_ProgressGray = [NSImage imageNamed: @"ProgressBarGray.png"];
	[_ProgressGray setScalesWhenResized: YES];
	[_ProgressGray setSize: startSize];
	
	_ProgressGreen = [NSImage imageNamed: @"ProgressBarGreen.png"];
	[_ProgressGreen setScalesWhenResized: YES];
	
	_ProgressLightGreen = [NSImage imageNamed: @"ProgressBarLightGreen.png"];
	[_ProgressLightGreen setScalesWhenResized: YES];
	
	_ProgressAdvanced = [NSImage imageNamed: @"ProgressBarAdvanced.png"];
	[_ProgressAdvanced setScalesWhenResized: YES];
	
	_ProgressEndWhite = [NSImage imageNamed: @"ProgressBarEndWhite.png"];
	_ProgressEndBlue = [NSImage imageNamed: @"ProgressBarEndBlue.png"];
	_ProgressEndGray = [NSImage imageNamed: @"ProgressBarEndGray.png"];
	_ProgressEndGreen = [NSImage imageNamed: @"ProgressBarEndGreen.png"];
	_ProgressEndAdvanced = [NSImage imageNamed: @"ProgressBarEndAdvanced.png"];
	
	_ErrorImage = [[NSImage imageNamed: @"Error.tiff"] copy];
	[_ErrorImage setFlipped: YES];
}

- (id)init
{
	self = [super init];
	_minVal = 0.0;
	_maxVal = 100.0;
	_isActive = YES;

	return self;
}

- (void)dealloc
{
	[_icon release];
	[_statusString release];
	[super dealloc];
}

- (void)setStatusString:(NSString *)string
{
	[_statusString autorelease];
	_statusString = [string retain];
}

- (void)setIcon:(NSImage *)image
{
	[_icon autorelease];
	_icon = [image retain];
}

- (void)setIsActive:(BOOL)yn
{
	_isActive = yn;
}

- (void)drawBarImage:(NSImage *)barImage width:(float)width point:(NSPoint)point
{
    if (width <= 0.0)
        return;
    
    if ([barImage size].width < width)
        [barImage setSize: NSMakeSize(width * 2.0, BAR_HEIGHT)];

    [barImage compositeToPoint: point fromRect: NSMakeRect(0, 0, width, BAR_HEIGHT) operation: NSCompositeSourceOver];
}

- (void)drawBar:(float)width point:(NSPoint)point
{
	id objectValue = [self objectValue];
	if (!objectValue) return;
	
    float value = [objectValue floatValue];
	float progress = (value - _minVal)/ (_maxVal - _minVal);

    width -= 2.0;
    float completedWidth, remainingWidth = 0.0;
    
    //bar images and widths
    NSImage * barLeftEnd, * barRightEnd, * barComplete, * barRemaining;
	if (progress >= 1.0) {
        completedWidth = width;
        barLeftEnd = _ProgressEndGreen;
        barRightEnd = _ProgressEndGreen;
        barComplete = _ProgressGreen;
        barRemaining = _ProgressLightGreen;
	} 
	else {
        completedWidth = progress * width;
        remainingWidth = width - completedWidth;
		barLeftEnd = (remainingWidth == width) ? _ProgressEndWhite
						: ((_isActive) ? _ProgressEndBlue : _ProgressEndGray);
		barRightEnd = (completedWidth < width) ? _ProgressEndWhite
						: ((_isActive) ? _ProgressEndBlue : _ProgressEndGray);
        barComplete = _isActive ? _ProgressBlue : _ProgressGray;
        barRemaining = _ProgressWhite;
    }
    
    [barLeftEnd compositeToPoint: point operation: NSCompositeSourceOver];
    
    point.x += 1.0;
    [self drawBarImage: barComplete width: completedWidth point: point];
    
    point.x += completedWidth;
    [self drawBarImage: barRemaining width: remainingWidth point: point];
    
    point.x += remainingWidth;
    [barRightEnd compositeToPoint: point operation: NSCompositeSourceOver];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)view
{
    NSPoint pen = cellFrame.origin;
    const float PADDING = 3.0;
        
	//progress bar
	// pen.x = cellFrame.origin.x + iconSize.width + 2.0 * PADDING;
	pen.y += PADDING + BAR_HEIGHT;
	float mainWidth = cellFrame.size.width;
	float barWidth = mainWidth;
	[self drawBar: barWidth point: pen];
    
	//icon
	NSImage * icon = _isError ? _ErrorImage : _icon;
	if (icon) {
		NSSize iconSize = icon ? [icon size] : ZeroSize;
		pen = cellFrame.origin;
		pen.x += (cellFrame.size.width - iconSize.width) * 0.5;
		pen.y += (cellFrame.size.height - iconSize.height) * 0.5;
		
		[icon drawAtPoint: pen fromRect: NSZeroRect // NSMakeRect(0, 0, iconSize.width, iconSize.height)
				operation: NSCompositeSourceOver fraction: 1.0];
	}

	// status string
	if (_statusString) {
	    BOOL highlighted = [self isHighlighted] && [[self highlightColorWithFrame: cellFrame inView: view]
                                                        isEqual: [NSColor alternateSelectedControlColor]];
		NSMutableParagraphStyle * paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		[paragraphStyle setLineBreakMode: NSLineBreakByTruncatingTail];
		
		NSDictionary * statusAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
						highlighted ? [NSColor whiteColor] : [NSColor darkGrayColor], NSForegroundColorAttributeName,
						[NSFont boldSystemFontOfSize: 9.0], NSFontAttributeName,
						paragraphStyle, NSParagraphStyleAttributeName, nil];
		[paragraphStyle release];

		NSSize statusSize = [_statusString sizeWithAttributes: statusAttributes];
		pen = cellFrame.origin;
		pen.x += (cellFrame.size.width - statusSize.width) * 0.5;
		pen.y += (cellFrame.size.height - statusSize.height) * 0.5;
		
		[_statusString drawInRect: NSMakeRect(pen.x, pen.y, statusSize.width, statusSize.height)
						withAttributes: statusAttributes];
	    [statusAttributes release];
	}
}

@end
