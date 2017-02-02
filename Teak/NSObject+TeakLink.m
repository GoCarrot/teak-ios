/* Teak -- Copyright (C) 2016 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "Teak+Internal.h"
#import <objc/runtime.h>

#define LOG_TAG "Teak:Link"

typedef NSString* (^TeakRegexReplaceBlock)(NSString*);
NSString* TeakRegexHelper(NSString* pattern, NSString* string, TeakRegexReplaceBlock block) {
   NSMutableString *output = [[NSMutableString alloc] init];
   NSError *error = NULL;
   NSRegularExpression* regex = [NSRegularExpression
                                 regularExpressionWithPattern:pattern
                                 options:NSRegularExpressionCaseInsensitive
                                 error:&error];
   // Check for errors
   if (regex == nil) {
      [NSException raise:@"Invalid regular expression created" format:@"%@", error];
   }

   __block unsigned long prevEndPosition = 0;
   [regex enumerateMatchesInString:string
                           options:0
                             range:NSMakeRange(0, [string length])
                        usingBlock:^(NSTextCheckingResult* match, NSMatchingFlags flags, BOOL* stop)
    {
       // Copy skipped text
       NSRange r = {.location = prevEndPosition, .length = match.range.location - prevEndPosition};
       [output appendString:[string substringWithRange:r]];

       // Replace
       NSRange r2 = {.location = match.range.location, .length = match.range.length};
       NSString* toReplace = [string substringWithRange:r2];
       NSString* replacement = block(toReplace);
       [output appendString:replacement];

       // prevEndPosition is always indexing into string, not output
       prevEndPosition = match.range.location + match.range.length;
    }];

   // Copy remaining text
   NSRange r = {.location = prevEndPosition, .length = [string length] - prevEndPosition};
   [output appendString:[string substringWithRange:r]];

   return output;
}

@interface TeakLink : NSObject
@property (strong, nonatomic) NSMethodSignature* methodSignature;
@property (strong, nonatomic) NSArray* argumentIndicies;
@property (weak,   nonatomic) id invocationTarget;
@property (        nonatomic) SEL selector;

- (nullable TeakLink*)initForSelector:(SEL)selector argumentOrder:(NSArray*)argumentOrder invocationTarget:(id)invocationTarget;

+ (nonnull NSMutableDictionary*)deepLinkRegistration;

+ (BOOL)handleDeepLink:(NSString*)deepLink;

@end

BOOL TeakLink_HandleDeepLink(NSString* deepLink) {
   return [TeakLink handleDeepLink:deepLink];
}

@implementation TeakLink

- (nullable TeakLink*)initForSelector:(SEL)selector argumentOrder:(NSArray*)argumentOrder invocationTarget:(id)invocationTarget {
   self = [super init];
   if (self) {
      self.selector = selector;
      self.argumentIndicies = argumentOrder;
      self.invocationTarget = invocationTarget;
      self.methodSignature = [self.invocationTarget methodSignatureForSelector:self.selector];;
   }
   return self;
}


+ (nonnull NSMutableDictionary*)deepLinkRegistration {
   static NSMutableDictionary* dict = nil;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      dict = [[NSMutableDictionary alloc] init];
   });
   return dict;
}

+ (BOOL)handleDeepLink:(NSString*)deepLink {
   NSDictionary* deepLinkPatterns = [TeakLink deepLinkRegistration];
   for (NSString* key in deepLinkPatterns) {
      NSError* error = nil;
      NSRegularExpression* regExp = [NSRegularExpression regularExpressionWithPattern:key options:0 error:&error];
      if (error != nil) {
         TeakDebugLog(@"Error parsing regular expression: %@", [error localizedDescription]);
      } else {
         teak_try {
            NSRange range = NSMakeRange(0, [deepLink length]);
            NSTextCheckingResult* match = [regExp firstMatchInString:deepLink options:0 range:range];
            if (match != nil) {
               teak_log_data_breadcrumb(@"Found matching pattern", (@{@"pattern" : key, @"deep_link" : deepLink}));
               TeakLink* link = [deepLinkPatterns objectForKey:key];
               NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:link.methodSignature];
               [invocation setTarget:link.invocationTarget];
               [invocation setSelector:link.selector];
               NSMutableArray* argHandleHolder = [[NSMutableArray alloc] init];
               for (NSUInteger i = 0; i < [link.argumentIndicies count]; i++) {
                  NSRange argRange = [match rangeAtIndex:i + 1];
                  NSString* arg = argRange.location == NSNotFound ? nil : [deepLink substringWithRange:argRange];
                  [argHandleHolder addObject:arg];
                  NSUInteger argIndex = [link.argumentIndicies[i] unsignedIntegerValue];
                  [invocation setArgument:&arg atIndex: argIndex + 2];
               }
               [invocation invoke];
               return YES;
            }
         } teak_catch_report
      }
   }

   return NO;
}

@end

@implementation NSObject (TeakLink)

- (void)teak_registerRoute:(NSString*)route forSelector:(SEL)selector {
   // Verify that whatever this is actually responds to the selector
   if (![self respondsToSelector:selector]) {
      [NSException raise:@"Invocation target must respond to selector." format:@"In method: %@", @"TODO METHOD"];
   }

   // Verify that only NSObjects are being used as parameters
   NSMethodSignature* methodSignature = [self methodSignatureForSelector:selector];
   for (NSUInteger i = 2; i < [methodSignature numberOfArguments]; i++) {
      if (strcmp([methodSignature getArgumentTypeAtIndex:i], "@") != 0) {
         [NSException raise:@"Argument type must be id" format:@"Argument type %s In route: %@", [methodSignature getArgumentTypeAtIndex:i], route];
      }
   }

   // Sanitize route
   NSString* escapedRoute = TeakRegexHelper(@"[^\\?\\%\\\\/\\:\\*\\w]", route, ^NSString* (NSString* toReplace) {
      return [NSRegularExpression escapedPatternForString:toReplace];
   });

   // Build pattern, get argument-order array
   NSMutableArray* argumentOrder = [[NSMutableArray alloc] init];
   NSString* pattern = TeakRegexHelper(@"((:\\w+)|\\*)", escapedRoute, ^NSString* (NSString* toReplace) {
      if ([toReplace isEqualToString:@"*"]) {
         [NSException raise:@"'splat' functionality is not supported by TeakLinks." format:@"In route: %@", route];
         return nil;
      }

      NSScanner* scanner = [NSScanner scannerWithString:toReplace];
      NSInteger argumentIndex;
      if (![scanner scanString:@":arg" intoString:nil] || ![scanner scanInteger:&argumentIndex]) {
         [NSException raise:@"Variable names must be 'arg0', 'arg1' etc" format:@"Arg Name '%@' In route: %@", toReplace, route];
         return nil;
      }
      [argumentOrder addObject:[NSNumber numberWithInteger:argumentIndex]];
      return [NSString stringWithFormat:@"(?<%@>[^/?#]+)", [toReplace substringFromIndex:1]];
   });

   // Check for duplicate group names
   NSSet* argumentOrderSet = [NSSet setWithArray:argumentOrder];
   if ([argumentOrder count] != [argumentOrderSet count]) {
      [NSException raise:@"Duplicate named parameter in TeakLink route." format:@"In route: %@", route];
   }

   // Prepend ^
   pattern = [NSString stringWithFormat:@"^%@", pattern];

   TeakLink* link = [[TeakLink alloc] initForSelector:selector argumentOrder:argumentOrder invocationTarget:self];
   [[TeakLink deepLinkRegistration] setValue:link forKey:pattern];
}

@end
