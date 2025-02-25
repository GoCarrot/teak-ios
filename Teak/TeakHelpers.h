#ifndef TeakHelpers_h
#define TeakHelpers_h

extern NSString* TeakURLEscapedString(NSString* inString);
extern NSString* TeakNSStringOrNilFor(id object);
extern BOOL TeakBoolFor(id object);
extern NSString* TeakHexStringFromData(NSData* data);
extern NSDictionary* TeakGetQueryParameterDictionaryFromUrl(NSURL* url);
extern BOOL TeakStringsAreEqualConsideringNSNull(NSString* a, NSString* b);
extern BOOL TeakNSNullOrNil(id object);
extern id TeakValueOrNSNull(id object);
extern NSString* TeakStringForBool(BOOL x);

#define TeakUnused(_param) ((void)_param)
#define kTeakHostname @"gocarrot.com"

#endif
