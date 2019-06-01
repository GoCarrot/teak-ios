//  OCHamcrest by Jon Reid, https://qualitycoding.org/
//  Copyright 2018 hamcrest.org. See LICENSE.txt

#import "HCReturnTypeHandlerChain.h"

#import "HCBoolReturnGetter.h"
#import "HCCharReturnGetter.h"
#import "HCDoubleReturnGetter.h"
#import "HCFloatReturnGetter.h"
#import "HCIntReturnGetter.h"
#import "HCLongLongReturnGetter.h"
#import "HCLongReturnGetter.h"
#import "HCObjectReturnGetter.h"
#import "HCShortReturnGetter.h"
#import "HCUnsignedCharReturnGetter.h"
#import "HCUnsignedIntReturnGetter.h"
#import "HCUnsignedLongLongReturnGetter.h"
#import "HCUnsignedLongReturnGetter.h"
#import "HCUnsignedShortReturnGetter.h"

HCReturnValueGetter* HCReturnValueGetterChain(void) {
  static HCReturnValueGetter* chain = nil;
  if (!chain) {
    HCReturnValueGetter* doubleHandler = [[HCDoubleReturnGetter alloc] initWithSuccessor:nil];
    HCReturnValueGetter* floatHandler = [[HCFloatReturnGetter alloc] initWithSuccessor:doubleHandler];
    HCReturnValueGetter* uLongLongHandler = [[HCUnsignedLongLongReturnGetter alloc] initWithSuccessor:floatHandler];
    HCReturnValueGetter* uLongHandler = [[HCUnsignedLongReturnGetter alloc] initWithSuccessor:uLongLongHandler];
    HCReturnValueGetter* uShortHandler = [[HCUnsignedShortReturnGetter alloc] initWithSuccessor:uLongHandler];
    HCReturnValueGetter* uIntHandler = [[HCUnsignedIntReturnGetter alloc] initWithSuccessor:uShortHandler];
    HCReturnValueGetter* uCharHandler = [[HCUnsignedCharReturnGetter alloc] initWithSuccessor:uIntHandler];
    HCReturnValueGetter* longLongHandler = [[HCLongLongReturnGetter alloc] initWithSuccessor:uCharHandler];
    HCReturnValueGetter* longHandler = [[HCLongReturnGetter alloc] initWithSuccessor:longLongHandler];
    HCReturnValueGetter* shortHandler = [[HCShortReturnGetter alloc] initWithSuccessor:longHandler];
    HCReturnValueGetter* intHandler = [[HCIntReturnGetter alloc] initWithSuccessor:shortHandler];
    HCReturnValueGetter* boolHandler = [[HCBoolReturnGetter alloc] initWithSuccessor:intHandler];
    HCReturnValueGetter* charHandler = [[HCCharReturnGetter alloc] initWithSuccessor:boolHandler];
    HCReturnValueGetter* objectHandler = [[HCObjectReturnGetter alloc] initWithSuccessor:charHandler];
    chain = objectHandler;
  }
  return chain;
}
