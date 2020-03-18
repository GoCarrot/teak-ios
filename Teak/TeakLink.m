#import "Teak+Internal.h"
#import "TeakAppConfiguration.h"

BOOL TeakLink_HandleDeepLink(NSURL* deepLink);

NSString* const TeakLinkIncomingUrlKey = @"__incoming_url";
NSString* const TeakLinkIncomingUrlPathKey = @"__incoming_path";

@interface TeakLink ()

@property (strong, nonatomic) NSArray* argumentIndicies;
@property (copy, nonatomic) TeakLinkBlock block;
@property (strong, nonatomic) NSString* name;
@property (strong, nonatomic) NSString* routeDescription;
@property (strong, nonatomic) NSString* route;

- (nullable TeakLink*)initWithName:(NSString*)name description:(NSString*)description argumentOrder:(NSArray*)argumentOrder block:(TeakLinkBlock)block route:(NSString*)route;

+ (nonnull NSMutableDictionary*)deepLinkRegistration;

+ (BOOL)handleDeepLink:(NSURL*)deepLink;

@end

typedef NSString* (^TeakRegexReplaceBlock)(NSString*);
NSString* TeakRegexHelper(NSString* pattern, NSString* string, TeakRegexReplaceBlock block) {
  NSMutableString* output = [[NSMutableString alloc] init];
  NSError* error = NULL;
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
                       usingBlock:^(NSTextCheckingResult* match, NSMatchingFlags flags, BOOL* stop) {
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

BOOL TeakLink_WillHandleDeepLink(NSURL* deepLink) {
  // Check URL scheme to see if it matches the set we support
  for (NSString* scheme in [TeakConfiguration configuration].appConfiguration.urlSchemes) {
    if ([scheme isEqualToString:deepLink.scheme]) {
      return YES;
    }
  }

  return NO;
}

BOOL TeakLink_HandleDeepLink(NSURL* deepLink) {
  if (TeakLink_WillHandleDeepLink(deepLink)) {
    NSBlockOperation* handleDeepLinkOp = [NSBlockOperation blockOperationWithBlock:^{
      [TeakLink handleDeepLink:deepLink];
    }];
    [handleDeepLinkOp addDependency:[Teak sharedInstance].waitForDeepLinkOperation];
    [[Teak sharedInstance].operationQueue addOperation:handleDeepLinkOp];

    return YES;
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
  if (deepLink == nil || deepLink.path == nil) return NO;

  NSDictionary* deepLinkPatterns = [TeakLink deepLinkRegistration];
  for (NSString* key in deepLinkPatterns) {
    NSError* error = nil;
    NSRegularExpression* regExp = [NSRegularExpression regularExpressionWithPattern:key options:0 error:&error];
    if (error != nil) {
      TeakLog_e(@"deep_link.parse_error", @{@"error" : [error localizedDescription]});
    } else {
      teak_try {
        teak_log_data_breadcrumb(@"Looking for matching pattern", (@{@"pattern" : key, @"deep_link" : deepLink.path}));
        NSRange range = NSMakeRange(0, [deepLink.path length]);
        NSTextCheckingResult* match = [regExp firstMatchInString:deepLink.path options:0 range:range];
        if (match != nil) {
          teak_log_data_breadcrumb(@"Found matching pattern", (@{@"match" : [match description]}));
          TeakLink* link = deepLinkPatterns[key];
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

          // Original path
          if (params[TeakLinkIncomingUrlPathKey] == nil) {
            params[TeakLinkIncomingUrlPathKey] = deepLink.path;
          }

          // Full URL
          if (params[TeakLinkIncomingUrlKey] == nil) {
            params[TeakLinkIncomingUrlKey] = [deepLink absoluteString];
          }

          // Log that we handled the deep link
          TeakLog_i(@"deep_link.handled", @{
            @"url" : [deepLink absoluteString],
            @"params" : params,
            @"route" : [link route]
          });

          link.block(params);
          return YES;
        }
      }
      teak_catch_report;
    }
  }

  // Log that we ignored the deep link
  TeakLog_i(@"deep_link.ignored", @{@"url" : [deepLink absoluteString]});
  return NO;
}

+ (nonnull NSArray*)routeNamesAndDescriptions {
  NSMutableArray* namesAndDescriptions = [[NSMutableArray alloc] init];
  NSDictionary* deepLinkPatterns = [TeakLink deepLinkRegistration];
  for (NSString* key in deepLinkPatterns) {
    TeakLink* link = deepLinkPatterns[key];
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
  NSString* escapedRoute = TeakRegexHelper(@"[\\?\\%\\\\/\\:\\*]", route, ^NSString*(NSString* toReplace) {
    return [NSRegularExpression escapedPatternForString:toReplace];
  });

  // Build pattern, get argument-order array
  NSMutableArray* argumentOrder = [[NSMutableArray alloc] init];
  NSString* pattern = TeakRegexHelper(@"((\\:\\w+)|\\*)", escapedRoute, ^NSString*(NSString* toReplace) {
    if ([toReplace isEqualToString:@"*"]) {
      [NSException raise:@"'splat' functionality is not supported by TeakLinks." format:@"In route: %@", route];
      return nil;
    }

    [argumentOrder addObject:[toReplace substringFromIndex:1]];
    return @"([^\\/]+)";
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

+ (void)checkAttributionForDeepLinkAndDispatchEvents:(nonnull NSDictionary*)attribution {
  NSString* deepLink = attribution[@"deep_link"];
  if (NSNullOrNil(deepLink)) return;

  @try {
    NSURL* url = [NSURL URLWithString:deepLink];
    if (!url) return;

    // Time to handle our deep link, finally!
    TeakLink_HandleDeepLink(url);

    dispatch_async(dispatch_get_main_queue(), ^{
      UIApplication* application = [UIApplication sharedApplication];

      // It is safe to do this even with links that are handled by Teak,
      // because the Teak delegate hooks check if the link was opened by the
      // host app and bail if it was. By doing this, we ensure that all links
      // are handled to application delegates even in cases where Teak failed
      // to hook the application delegate, e.g. Unity custom application
      // delegates.
      if ([application canOpenURL:url]) {
        [application openURL:url];
      }
    });
  } @finally {
  }
}

@end
