// Copyright © Microsoft Open Technologies, Inc.
//
// All Rights Reserved
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
// OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
// ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A
// PARTICULAR PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
//
// See the Apache License, Version 2.0 for the specific language
// governing permissions and limitations under the License.
#import "ADAuthenticationSettings.h"
#   import "ADKeychainTokenCacheStore.h"

@implementation ADAuthenticationSettings

@synthesize defaultTokenCacheStore = _defaultTokenCacheStore;
@synthesize expirationBuffer       = _expirationBuffer;
@synthesize credentialsType        = _credentialsType;
@synthesize requestTimeOut         = _requestTimeOut;
@synthesize enableFullScreen       = _enableFullScreen;
@synthesize clientTLSKeychainGroup  = _clientTLSKeychainGroup;
#if !TARGET_OS_IPHONE
@synthesize createSecAccessBlock    = _createSecAccessBlock;
#endif // !TARGET_OS_IPHONE

/*!
 An internal initializer used from the static creation function.
 */
-(id) initInternal
{
    self = [super init];
    if (self)
    {
        //Initialize the defaults here:
        self.credentialsType = AD_CREDENTIALS_AUTO;
        self.requestTimeOut = 300;//in seconds.
        self.expirationBuffer = 300;//in seconds, ensures catching of clock differences between the server and the device
        self.enableFullScreen = YES;
        
        _dispatchQueue              = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        SAFE_ARC_DISPATCH_RETAIN(_dispatchQueue);
//#if TARGET_OS_IPHONE
        _defaultTokenCacheStore = [ADKeychainTokenCacheStore new];
//#else
//        _defaultTokenCacheStore     = [[ADPersistentTokenCacheStore alloc] initWithLocation:nil];
//#endif
    }
    return self;
}

- (void)dealloc
{
    AD_LOG_VERBOSE(@"ADAuthenticationSettings", @"dealloc");
    
    NSAssert( false, @"Cannot dealloc ADAuthenticationSettings object" );
    
    SAFE_ARC_SUPER_DEALLOC();
}

+(ADAuthenticationSettings*)sharedInstance
{
    /* Below is a standard objective C singleton pattern*/
    static ADAuthenticationSettings* instance = nil;
    static dispatch_once_t onceToken = 0;
    @synchronized(self)
    {
        dispatch_once(&onceToken, ^{
            instance = [[ADAuthenticationSettings alloc] initInternal];
        });
    }
#if !__has_feature(objc_arc)
    if ( [instance retainCount] > 1 )
    {
        DebugLog( @"ADAuthenticationSettings retainCount = %lu", (unsigned long)[instance retainCount] );
    }
    NSAssert( [instance retainCount] >= 1, @"Bad retain count on shared instance" );
#endif
    return instance;
}
- (dispatch_queue_t)dispatchQueue
{
    return _dispatchQueue;
}

- (void)setDispatchQueue:(dispatch_queue_t)dispatchQueue
{
    dispatch_queue_t oldQueue = _dispatchQueue;
    _dispatchQueue = dispatchQueue;
    if ( _dispatchQueue ) SAFE_ARC_DISPATCH_RETAIN( _dispatchQueue );
    if ( oldQueue ) SAFE_ARC_DISPATCH_RELEASE( oldQueue );
}


#if TARGET_OS_IPHONE
-(NSString*) getSharedCacheKeychainGroup
{
    id store = self.defaultTokenCacheStore;
    if ([store isKindOfClass:[ADKeychainTokenCacheStore class]])
    {
        return ((ADKeychainTokenCacheStore*)store).sharedGroup;
    }
    else
    {
        return nil;
    }
}
#endif//TARGET_OS_IPHONE

#if TARGET_OS_IPHONE
-(void) setSharedCacheKeychainGroup:(NSString *)sharedKeychainGroup
{
    id store = self.defaultTokenCacheStore;
    if ([store isKindOfClass:[ADKeychainTokenCacheStore class]])
    {
        ((ADKeychainTokenCacheStore*)store).sharedGroup = sharedKeychainGroup;
    }
}
#endif//TARGET_OS_IPHONEf

@end

