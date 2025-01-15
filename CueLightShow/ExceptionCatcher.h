//
//  ExceptionCatcher.h
//  CueLightShow
//
//  Created by Alexander Mokrushin on 21.08.2024.
//

#import <Foundation/Foundation.h>

NS_INLINE NSException * _Nullable tryBlock(void(^_Nonnull tryBlock)(void)) {
    @try {
        tryBlock();
    }
    @catch (NSException *exception) {
        return exception;
    }
    return nil;
}
