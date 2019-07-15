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
    rfc3986Reserved = [[NSCharacterSet characterSetWithCharactersInString:@"!*'();:@&=+$,/?#[]"] invertedSet];
  });

  if (inString == nil) return nil;
  return [inString stringByAddingPercentEncodingWithAllowedCharacters:rfc3986Reserved];
}

BOOL TeakBoolFor(id object) {
  return NSNullOrNil(object) ? NO : [object boolValue];
}

///// Recursive form encode

NSString* TeakFormEncode(NSString* name, id value, BOOL escape) {
  NSMutableArray* listOfThingsToJoin = [[NSMutableArray alloc] init];
  if ([value isKindOfClass:NSDictionary.class]) {
    for (id key in value) {
      [listOfThingsToJoin addObject:TeakFormEncode([NSString stringWithFormat:@"%@[%@]", name, key], value[key], escape)];
    }
  } else if ([value isKindOfClass:NSArray.class]) {
    for (id v in value) {
      [listOfThingsToJoin addObject:TeakFormEncode([NSString stringWithFormat:@"%@[]", name], v, escape)];
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

///// Assign NSDictionary into 'application/x-www-form-urlencoded' request

void TeakAssignPayloadToRequest(NSMutableURLRequest* request, NSDictionary* payload) {
  NSMutableData* postData = [[NSMutableData alloc] init];
  NSMutableArray* escapedPayloadComponents = [[NSMutableArray alloc] init];
  for (NSString* key in payload) {
    id value = payload[key];
    [escapedPayloadComponents addObject:TeakFormEncode(key, value, YES)];
  }
  NSString* escapedPayloadString = [escapedPayloadComponents componentsJoinedByString:@"&"];
  [postData appendData:[escapedPayloadString dataUsingEncoding:NSUTF8StringEncoding]];

  [request setHTTPMethod:@"POST"];
  [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
  [request setHTTPBody:postData];
  [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
}
