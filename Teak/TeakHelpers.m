#import <Foundation/Foundation.h>

NSString* TeakNSStringOrNilFor(id object) {
  if (object == nil) return nil;

  NSString* ret = nil;
  @try {
    ret = ((object == nil || [object isKindOfClass:[NSString class]]) ? object : [object stringValue]);
  } @catch (NSException* ignored) {
    ret = nil;
  }
  return ret;
}

NSString* TeakURLEscapedString(NSString* inString) {
  static NSCharacterSet* rfc3986Reserved = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // Future-Pat, we're making our own allowed set because the Apple provided character sets
    // are opaque. I tried iterating through the inverted [NSCharacterSet URLQueryAllowedCharacterSet]
    // but still could not get the data out of it. It's better to know what we're dealing with, since
    // the [NSCharacterSet URLQueryAllowedCharacterSet] was not percent-encoding a +
    rfc3986Reserved = [[NSCharacterSet characterSetWithCharactersInString:@"!*'();:@&=+$,/?#[]% "] invertedSet];
  });

  return [inString stringByAddingPercentEncodingWithAllowedCharacters:rfc3986Reserved];
}

BOOL TeakBoolFor(id object) {
  return NSNullOrNil(object) ? NO : [object boolValue];
}

NSString* TeakHexStringFromData(NSData* data) {
  NSUInteger dataLength = data.length;
  if (dataLength == 0) {
    return nil;
  }

  const unsigned char* dataBuffer = data.bytes;
  NSMutableString* hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];
  for (int i = 0; i < dataLength; ++i) {
    [hexString appendFormat:@"%02x", dataBuffer[i]];
  }
  return [hexString copy];
}

///// Assign NSDictionary into 'application/json' request

void TeakAssignPayloadToRequest(NSString* method, NSMutableURLRequest* request, NSDictionary* payload) {
  NSData* postData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

  [request setHTTPMethod:method];
  [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
  [request setHTTPBody:postData];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
}

NSDictionary* TeakGetQueryParameterDictionaryFromUrl(NSURL* url) {
  NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] init];
  if (url) {
    NSURLComponents* launchUrlComponents = [NSURLComponents componentsWithString:url.absoluteString];
    for (NSURLQueryItem* item in launchUrlComponents.queryItems) {
      if ([dictionary objectForKey:item.name] != nil) {
        if ([dictionary[item.name] isKindOfClass:[NSArray class]]) {
          NSMutableArray* array = dictionary[item.name];
          [array addObject:item.value];
          dictionary[item.name] = array;
        } else {
          NSMutableArray* array = [NSMutableArray arrayWithObjects:dictionary[item.name], item.value, nil];
          dictionary[item.name] = array;
        }
      } else {
        dictionary[item.name] = item.value;
      }
    }
  }
  return dictionary;
}
