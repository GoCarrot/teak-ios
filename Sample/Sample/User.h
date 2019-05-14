//
//  User.h
//  Sample
//
//  Created by Alexander Scarborough on 5/14/19.
//  Copyright © 2019 GoCarrot Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct SlotWin {
  NSUInteger wager;
  NSUInteger win;
} SlotWin;

@interface User : NSObject

+ (User*)user;

// Resets the user to have 50,000 coins.
- (void)resetCoins;

// Collects our recurring bonus.
- (void)collectRecurringBonus;

// Plays a slot machine, wagering 1,000 coins, and winning some amount.
- (SlotWin)playSlot:(NSString*)slot;

@property NSUInteger coins;
@property NSString* lastSlot;

@end

NS_ASSUME_NONNULL_END
