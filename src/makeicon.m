//  makeicon.m — 绘制 TransNote 的图标（圆角渐变 + 「译」）

#import <Cocoa/Cocoa.h>

static void WritePNG(NSString *path, NSInteger px) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:px
                      pixelsHigh:px
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];
    rep.size = NSMakeSize(px, px);

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];

    CGFloat size = (CGFloat)px;
    CGFloat inset = size * 0.075;
    NSRect rect = NSMakeRect(inset, inset, size - inset * 2, size - inset * 2);
    CGFloat radius = rect.size.width * 0.225;

    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    [shape addClip];

    NSGradient *grad = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithSRGBRed:0.29 green:0.44 blue:0.96 alpha:1.0]
                 endingColor:[NSColor colorWithSRGBRed:0.46 green:0.19 blue:0.86 alpha:1.0]];
    [grad drawInRect:rect angle:-70.0];

    NSString *glyph = @"译";
    NSFont *font = [NSFont systemFontOfSize:rect.size.width * 0.50 weight:NSFontWeightBold];
    NSDictionary *attrs = @{ NSFontAttributeName: font,
                             NSForegroundColorAttributeName: [NSColor colorWithSRGBRed:1.0 green:1.0 blue:1.0 alpha:0.97] };
    NSSize textSize = [glyph sizeWithAttributes:attrs];
    NSPoint origin = NSMakePoint(NSMidX(rect) - textSize.width / 2.0,
                                 NSMidY(rect) - textSize.height / 2.0);
    [glyph drawAtPoint:origin withAttributes:attrs];

    [NSGraphicsContext restoreGraphicsState];

    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *out = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"TransNote.iconset";
        [[NSFileManager defaultManager] createDirectoryAtPath:out
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        NSArray<NSArray *> *specs = @[
            @[@"icon_16x16.png", @16],      @[@"icon_16x16@2x.png", @32],
            @[@"icon_32x32.png", @32],      @[@"icon_32x32@2x.png", @64],
            @[@"icon_128x128.png", @128],   @[@"icon_128x128@2x.png", @256],
            @[@"icon_256x256.png", @256],   @[@"icon_256x256@2x.png", @512],
            @[@"icon_512x512.png", @512],   @[@"icon_512x512@2x.png", @1024],
        ];
        for (NSArray *spec in specs) {
            WritePNG([out stringByAppendingPathComponent:spec[0]], [spec[1] integerValue]);
        }
        printf("iconset -> %s\n", out.UTF8String);
    }
    return 0;
}
