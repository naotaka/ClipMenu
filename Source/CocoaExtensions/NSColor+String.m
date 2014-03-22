// Copyright 2008 Google Inc.
// 
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License.  You may obtain a copy
// of the License at
// 
// http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
// License for the specific language governing permissions and limitations under
// the License.

#import "NSColor+String.h"

typedef struct {
  unsigned long value;
  const char name[24];  // Longest name is 20 chars, pad out to multiple of 8
} ColorNameRec;

static ColorNameRec sColorTable[] = {
  { 0xf0f8ff, "aliceblue" },
  { 0xfaebd7, "antiquewhite" },
  { 0x00ffff, "aqua" },
  { 0x7fffd4, "aquamarine" },
  { 0xf0ffff, "azure" },
  { 0xf5f5dc, "beige" },
  { 0xffe4c4, "bisque" },
  { 0x000000, "black" },
  { 0xffebcd, "blanchedalmond" },
  { 0x0000ff, "blue" },
  { 0x8a2be2, "blueviolet" },
  { 0xa52a2a, "brown" },
  { 0xdeb887, "burlywood" },
  { 0x5f9ea0, "cadetblue" },
  { 0x7fff00, "chartreuse" },
  { 0xd2691e, "chocolate" },
  { 0xff7f50, "coral" },
  { 0x6495ed, "cornflowerblue" },
  { 0xfff8dc, "cornsilk" },
  { 0xdc143c, "crimson" },
  { 0x00ffff, "cyan" },
  { 0x00008b, "darkblue" },
  { 0x008b8b, "darkcyan" },
  { 0xb8860b, "darkgoldenrod" },
  { 0xa9a9a9, "darkgray" },
  { 0xa9a9a9, "darkgrey" },
  { 0x006400, "darkgreen" },
  { 0xbdb76b, "darkkhaki" },
  { 0x8b008b, "darkmagenta" },
  { 0x556b2f, "darkolivegreen" },
  { 0xff8c00, "darkorange" },
  { 0x9932cc, "darkorchid" },
  { 0x8b0000, "darkred" },
  { 0xe9967a, "darksalmon" },
  { 0x8fbc8f, "darkseagreen" },
  { 0x483d8b, "darkslateblue" },
  { 0x2f4f4f, "darkslategray" },
  { 0x2f4f4f, "darkslategrey" },
  { 0x00ced1, "darkturquoise" },
  { 0x9400d3, "darkviolet" },
  { 0xff1493, "deeppink" },
  { 0x00bfff, "deepskyblue" },
  { 0x696969, "dimgray" },
  { 0x696969, "dimgrey" },
  { 0x1e90ff, "dodgerblue" },
  { 0xb22222, "firebrick" },
  { 0xfffaf0, "floralwhite" },
  { 0x228b22, "forestgreen" },
  { 0xff00ff, "fuchsia" },
  { 0xdcdcdc, "gainsboro" },
  { 0xf8f8ff, "ghostwhite" },
  { 0xffd700, "gold" },
  { 0xdaa520, "goldenrod" },
  { 0x808080, "gray" },
  { 0x808080, "grey" },
  { 0x008000, "green" },
  { 0xadff2f, "greenyellow" },
  { 0xf0fff0, "honeydew" },
  { 0xff69b4, "hotpink" },
  { 0xcd5c5c, "indianred" },
  { 0x4b0082, "indigo" },
  { 0xfffff0, "ivory" },
  { 0xf0e68c, "khaki" },
  { 0xe6e6fa, "lavender" },
  { 0xfff0f5, "lavenderblush" },
  { 0x7cfc00, "lawngreen" },
  { 0xfffacd, "lemonchiffon" },
  { 0xadd8e6, "lightblue" },
  { 0xf08080, "lightcoral" },
  { 0xe0ffff, "lightcyan" },
  { 0xfafad2, "lightgoldenrodyellow" },
  { 0xd3d3d3, "lightgray" },
  { 0xd3d3d3, "lightgrey" },
  { 0x90ee90, "lightgreen" },
  { 0xffb6c1, "lightpink" },
  { 0xffa07a, "lightsalmon" },
  { 0x20b2aa, "lightseagreen" },
  { 0x87cefa, "lightskyblue" },
  { 0x8470ff, "lightslateblue" },
  { 0x778899, "lightslategray" },
  { 0x778899, "lightslategrey" },
  { 0xb0c4de, "lightsteelblue" },
  { 0xffffe0, "lightyellow" },
  { 0x00ff00, "lime" },
  { 0x32cd32, "limegreen" },
  { 0xfaf0e6, "linen" },
  { 0xff00ff, "magenta" },
  { 0x800000, "maroon" },
  { 0x66cdaa, "mediumaquamarine" },
  { 0x0000cd, "mediumblue" },
  { 0xba55d3, "mediumorchid" },
  { 0x9370d8, "mediumpurple" },
  { 0x3cb371, "mediumseagreen" },
  { 0x7b68ee, "mediumslateblue" },
  { 0x00fa9a, "mediumspringgreen" },
  { 0x48d1cc, "mediumturquoise" },
  { 0xc71585, "mediumvioletred" },
  { 0x191970, "midnightblue" },
  { 0xf5fffa, "mintcream" },
  { 0xffe4e1, "mistyrose" },
  { 0xffe4b5, "moccasin" },
  { 0xffdead, "navajowhite" },
  { 0x000080, "navy" },
  { 0xfdf5e6, "oldlace" },
  { 0x808000, "olive" },
  { 0x6b8e23, "olivedrab" },
  { 0xffa500, "orange" },
  { 0xff4500, "orangered" },
  { 0xda70d6, "orchid" },
  { 0xeee8aa, "palegoldenrod" },
  { 0x98fb98, "palegreen" },
  { 0xafeeee, "paleturquoise" },
  { 0xd87093, "palevioletred" },
  { 0xffefd5, "papayawhip" },
  { 0xffdab9, "peachpuff" },
  { 0xcd853f, "peru" },
  { 0xffc0cb, "pink" },
  { 0xdda0dd, "plum" },
  { 0xb0e0e6, "powderblue" },
  { 0x800080, "purple" },
  { 0xff0000, "red" },
  { 0xbc8f8f, "rosybrown" },
  { 0x4169e1, "royalblue" },
  { 0x8b4513, "saddlebrown" },
  { 0xfa8072, "salmon" },
  { 0xf4a460, "sandybrown" },
  { 0x2e8b57, "seagreen" },
  { 0xfff5ee, "seashell" },
  { 0xa0522d, "sienna" },
  { 0xc0c0c0, "silver" },
  { 0x87ceeb, "skyblue" },
  { 0x6a5acd, "slateblue" },
  { 0x708090, "slategray" },
  { 0x708090, "slategrey" },
  { 0xfffafa, "snow" },
  { 0x00ff7f, "springgreen" },
  { 0x4682b4, "steelblue" },
  { 0xd2b48c, "tan" },
  { 0x008080, "teal" },
  { 0xd8bfd8, "thistle" },
  { 0xff6347, "tomato" },
  { 0x40e0d0, "turquoise" },
  { 0xee82ee, "violet" },
  { 0xd02090, "violetred" },
  { 0xf5deb3, "wheat" },
  { 0xffffff, "white" },
  { 0xf5f5f5, "whitesmoke" },
  { 0xffff00, "yellow" },
  { 0x9acd32, "yellowgreen" },
};

@implementation NSColor(TopDrawString)
//------------------------------------------------------------------------------
+ (NSArray *)colorNames {
  static NSArray *sAllNames = nil;
  
  if (!sAllNames) {
    int count = sizeof(sColorTable) / sizeof(sColorTable[0]);
    NSMutableArray *names = [[NSMutableArray alloc] init];
    ColorNameRec *rec = sColorTable;

    for (int i = 0; i < count; ++i, ++rec)
      [names addObject:[NSString stringWithUTF8String:rec->name]];
    
    sAllNames = [[NSArray alloc] initWithArray:names];
    [names release];
  }

  return sAllNames;
}

//------------------------------------------------------------------------------
static NSColor *ColorWithUnsignedLong(unsigned long value, BOOL hasAlpha) {
  float a = 1.0;
  
  // Extract alpha, if available
  if (hasAlpha) {
    a = (float)(0x00FF & value) / 255.0;
    value >>= 8;
  }

  float r = (float)(value >> 16) / 255.0;
  float g = (float)(0x00FF & (value >> 8)) / 255.0;
  float b = (float)(0x00FF & value) / 255.0;
  
  return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
}

//------------------------------------------------------------------------------
static NSColor *ColorWithHexDigits(NSString *str) {
  NSScanner *scanner = [NSScanner scannerWithString:[str lowercaseString]];
  NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
  NSString *hexStr;
  
  [scanner scanUpToCharactersFromSet:hexSet intoString:nil];
  [scanner scanCharactersFromSet:hexSet intoString:&hexStr];
  
  int len = [hexStr length];
  if (len >= 6) {
    BOOL hasAlpha = (len == 8) ? YES : NO;
    unsigned long value = strtoul([hexStr UTF8String], NULL, 16);
    
    return ColorWithUnsignedLong(value, hasAlpha);
  }
  
  return nil;
}

//------------------------------------------------------------------------------
static NSColor *ColorWithCSSString(NSString *str) {
  NSString *trimmed = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSString *lowerStr = [trimmed lowercaseString];
  NSScanner *scanner = [NSScanner scannerWithString:lowerStr];

  if ([scanner scanString:@"rgb" intoString:NULL]) {
    [scanner scanString:@"(" intoString:NULL];
    NSString *content;
    [scanner scanUpToString:@")" intoString:&content];
    NSCharacterSet *spaceOrCommaSet = [NSCharacterSet characterSetWithCharactersInString:@" ,"];
    NSArray *components = [content componentsSeparatedByCharactersInSet:spaceOrCommaSet];
    int count = [components count];
    float a = 1.0;
    
    // Alpha in CSS-mode is a 0-1 float
    if (count > 3)
      a = (float)[[components objectAtIndex:3] floatValue];
    
    float r = (float)strtoul([[components objectAtIndex:0] UTF8String], NULL, 10) / 255.0;
    float g = (float)strtoul([[components objectAtIndex:1] UTF8String], NULL, 10) / 255.0;
    float b = (float)strtoul([[components objectAtIndex:2] UTF8String], NULL, 10) / 255.0;
    
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
  }
  
  return nil;
}

//------------------------------------------------------------------------------
+ (NSColor *)colorWithString:(NSString *)name {
  if (![name length])
    return nil;
  
  NSArray *allNames = [self colorNames];
  NSUInteger count = [allNames count];
  NSUInteger idx = [allNames indexOfObject:[name lowercaseString]];

  if (idx >= count) {
    // If the string contains some hex digits, try to convert
    // #RRGGBB or #RRGGBBAA
    // rgb(r,g,b) or rgba(r,g,b,a)
    NSColor *color = ColorWithHexDigits(name);
    
    if (!color)
      color = ColorWithCSSString(name);
    
    return color;
  }
  
  return ColorWithUnsignedLong(sColorTable[idx].value, NO);
}

@end
