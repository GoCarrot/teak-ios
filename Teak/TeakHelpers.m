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

///// Recursive form encode

#define IS_VALID_STRING_TO_APPEND(x) (thingToJoin != [NSNull null] && [thingToJoin length] != 0 && ![thingToJoin isEqualToString:@"&"])
NSString* TeakFormEncode(NSString* name, id value, BOOL escape) {
  NSMutableArray* listOfThingsToJoin = [[NSMutableArray alloc] init];
  if ([value isKindOfClass:NSDictionary.class]) {
    for (id key in value) {
      id thingToJoin = TeakFormEncode([NSString stringWithFormat:@"%@[%@]", name, key], value[key], escape);
      if (IS_VALID_STRING_TO_APPEND(thingToJoin)) {
        [listOfThingsToJoin addObject:thingToJoin];
      }
    }
  } else if ([value isKindOfClass:NSArray.class]) {
    for (id v in value) {
      id thingToJoin = TeakFormEncode([NSString stringWithFormat:@"%@[]", name], v, escape);
      if (IS_VALID_STRING_TO_APPEND(thingToJoin)) {
        [listOfThingsToJoin addObject:thingToJoin];
      }
    }
  } else if (value != nil && value != [NSNull null]) {
    if (name == nil) {
      [listOfThingsToJoin addObject:escape ? TeakURLEscapedString(TeakNSStringOrNilFor(value)) : TeakNSStringOrNilFor(value)];
    } else {
      [listOfThingsToJoin addObject:[NSString stringWithFormat:@"%@=%@", name, escape ? TeakURLEscapedString(TeakNSStringOrNilFor(value)) : TeakNSStringOrNilFor(value)]];
    }
  }
  return [listOfThingsToJoin componentsJoinedByString:@"&"];
}
#undef IS_VALID_STRING_TO_APPEND

///// Assign NSDictionary into 'application/json' request

void TeakAssignPayloadToRequest(NSMutableURLRequest* request, NSDictionary* payload) {
  NSData* postData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

  [request setHTTPMethod:@"POST"];
  [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
  [request setHTTPBody:postData];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
}
