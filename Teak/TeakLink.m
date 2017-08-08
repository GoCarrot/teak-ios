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
#import "TeakAppConfiguration.h"

@interface TeakLink()

@property (strong, nonatomic) NSArray* argumentIndicies;
@property (copy,   nonatomic) TeakLinkBlock block;
@property (strong, nonatomic) NSString* name;
@property (strong, nonatomic) NSString* routeDescription;
@property (strong, nonatomic) NSString* route;

- (nullable TeakLink*)initWithName:(NSString*)name description:(NSString*)description argumentOrder:(NSArray*)argumentOrder block:(TeakLinkBlock)block route:(NSString*)route;

+ (nonnull NSMutableDictionary*)deepLinkRegistration;

+ (BOOL)handleDeepLink:(NSURL*)deepLink;

@end

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

BOOL TeakLink_HandleDeepLink(NSURL* deepLink) {
   // Check URL scheme to see if it matches the set we support
   for (NSString* scheme in [Teak sharedInstance].appConfiguration.urlSchemes) {
      if ([scheme isEqualToString:deepLink.scheme]) {
         NSBlockOperation* handleDeepLinkOp = [NSBlockOperation blockOperationWithBlock:^{
            [TeakLink handleDeepLink:deepLink];
         }];
         if ([Teak sharedInstance].waitForDeepLinkOperation != nil) {
            [handleDeepLinkOp addDependency:[Teak sharedInstance].waitForDeepLinkOperation];
         }
         [[Teak sharedInstance].operationQueue addOperation:handleDeepLinkOp];

         return YES;
      }
   }

   if ([deepLink.scheme hasPrefix:@"http"]) {
      return [TeakLink handleDeepLink:deepLink];
   }

   return NO;
}

@implementation TeakLink

- (nullable TeakLink*)initWithName:(NSString*)name description:(NSString*)description argumentOrder:(NSArray*)argumentOrder block:(TeakLinkBlock)block route:(NSString*)route {
   self = [super init];
   if (self) {
      self.name = name;
      self.routeDescription = description;
      self.argumentIndicies = argumentOrder;
      self.block = block;
      self.route = route;
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

+ (BOOL)handleDeepLink:(NSURL*)deepLink {
   NSDictionary* deepLinkPatterns = [TeakLink deepLinkRegistration];
   for (NSString* key in deepLinkPatterns) {
      NSError* error = nil;
      NSRegularExpression* regExp = [NSRegularExpression regularExpressionWithPattern:key options:0 error:&error];
      if (error != nil) {
         TeakLog_e(@"deep_link.parse_error", @{@"error" : [error localizedDescription]});
      } else {
         teak_try {
            NSRange range = NSMakeRange(0, [deepLink.path length]);
            NSTextCheckingResult* match = [regExp firstMatchInString:deepLink.path options:0 range:range];
            if (match != nil) {
               teak_log_data_breadcrumb(@"Found matching pattern", (@{@"pattern" : key, @"deep_link" : deepLink.path}));
               TeakLink* link = [deepLinkPatterns objectForKey:key];
               NSMutableDictionary* params = [[NSMutableDictionary alloc] init];
               for (NSUInteger i = 0; i < [link.argumentIndicies count]; i++) {
                  NSRange argRange = [match rangeAtIndex:i + 1];
                  NSString* arg = argRange.location == NSNotFound ? nil : [deepLink.path substringWithRange:argRange];
                  [params setValue:arg forKey:link.argumentIndicies[i]];
               }

               // Query params
               NSURLComponents* urlComponents = [NSURLComponents componentsWithURL:deepLink
                                                           resolvingAgainstBaseURL:NO];
               for (NSURLQueryItem* item in urlComponents.queryItems) {
                  [params setValue:item.value forKey:item.name];
               }

               link.block(params);
               return YES;
            }
         } teak_catch_report
      }
   }

   return NO;
}

+ (nonnull NSArray*)routeNamesAndDescriptions {
   NSMutableArray* namesAndDescriptions = [[NSMutableArray alloc] init];
   NSDictionary* deepLinkPatterns = [TeakLink deepLinkRegistration];
   for (NSString* key in deepLinkPatterns) {
      TeakLink* link = [deepLinkPatterns objectForKey:key];
      if (link.name != nil && link.name.length > 0) {
         [namesAndDescriptions addObject:@{
            @"name" : link.name,
            @"description" : link.routeDescription == nil ? @"" : link.routeDescription,
            @"route" : link.route
         }];
      }
   }
   return namesAndDescriptions;
}

+ (void)registerRoute:(nonnull NSString*)route name:(nonnull NSString*)name description:(nonnull NSString*)description block:(nonnull TeakLinkBlock)block {

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

      [argumentOrder addObject:[toReplace substringFromIndex:1]];
      return [NSString stringWithFormat:@"(?<%@>[^/?#]+)", [toReplace substringFromIndex:1]];
   });

   // Check for duplicate group names
   NSSet* argumentOrderSet = [NSSet setWithArray:argumentOrder];
   if ([argumentOrder count] != [argumentOrderSet count]) {
      [NSException raise:@"Duplicate named parameter in TeakLink route." format:@"In route: %@", route];
   }

   // Prepend ^
   pattern = [NSString stringWithFormat:@"^%@", pattern];

   TeakLink* link = [[TeakLink alloc] initWithName:name description:description argumentOrder:argumentOrder block:block route:route];
   [[TeakLink deepLinkRegistration] setValue:link forKey:pattern];
}

@end
