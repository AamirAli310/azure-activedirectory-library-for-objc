// Copyright (c) Microsoft Corporation.
// All rights reserved.
//
// This code is licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "ADAuthenticationContext+Internal.h"
#import "ADUserIdentifier.h"
#import "ADTokenCacheItem+Internal.h"

NSString* const ADUnknownError = @"Uknown error.";
NSString* const ADCredentialsNeeded = @"The user credentials are need to obtain access token. Please call the non-silent acquireTokenWithResource methods.";
NSString* const ADInteractionNotSupportedInExtension = @"Interaction is not supported in an app extension.";
NSString* const ADServerError = @"The authentication server returned an error: %@.";
NSString* const ADBrokerAppIdentifier = @"com.microsoft.azureadauthenticator";
NSString* const ADRedirectUriInvalidError = @"Your AuthenticationContext is configured to allow brokered authentication but your redirect URI is not setup properly. Make sure your redirect URI is in the form of <app-scheme>://<bundle-id> (e.g. \"x-adal-broker-testapp://com.microsoft.adal.testapp\") and that the \"app-scheme\" you choose is registered in your application's info.plist.";

@implementation ADAuthenticationContext (Internal)

/*! Verifies that the string parameter is not nil or empty. If it is,
 the method generates an error and set it to an authentication result.
 Then the method calls the callback with the result.
 The method returns if the argument is valid. If the method returns false,
 the calling method should return. */
+ (BOOL)checkAndHandleBadArgument:(NSObject *)argumentValue
                     argumentName:(NSString *)argumentName
                    correlationId:(NSUUID *)correlationId
                  completionBlock:(ADAuthenticationCallback)completionBlock
{
    if (!argumentValue || ([argumentValue isKindOfClass:[NSString class]] && [NSString adIsStringNilOrBlank:(NSString*)argumentValue]))
    {
        ADAuthenticationError* argumentError = [ADAuthenticationError errorFromArgument:argumentValue argumentName:argumentName correlationId:correlationId];
        ADAuthenticationResult* result = [ADAuthenticationResult resultFromError:argumentError];
        completionBlock(result);//Call the callback to tell about the result
        return NO;
    }
    else
    {
        return YES;
    }
}

+ (BOOL)handleNilOrEmptyAsResult:(NSObject*)argumentValue
                    argumentName:(NSString*)argumentName
            authenticationResult:(ADAuthenticationResult**)authenticationResult
{
    if (!argumentValue || ([argumentValue isKindOfClass:[NSString class]] && [NSString adIsStringNilOrBlank:(NSString*)argumentValue]))
    {
        ADAuthenticationError* argumentError = [ADAuthenticationError errorFromArgument:argumentValue argumentName:argumentName correlationId:nil];
        *authenticationResult = [ADAuthenticationResult resultFromError:argumentError];
        return NO;
    }
    
    return YES;
}
//Obtains a protocol error from the response:
+ (ADAuthenticationError*)errorFromDictionary:(NSDictionary*)dictionary
                                    errorCode:(ADErrorCode)errorCode
{
    //First check for explicit OAuth2 protocol error:
    NSString* serverOAuth2Error = [dictionary objectForKey:OAUTH2_ERROR];
    if (![NSString adIsStringNilOrBlank:serverOAuth2Error])
    {
        NSString* errorDetails = [dictionary objectForKey:OAUTH2_ERROR_DESCRIPTION];
        // Error response from the server
        NSUUID* correlationId = [dictionary objectForKey:OAUTH2_CORRELATION_ID_RESPONSE] ?
                                [[NSUUID alloc] initWithUUIDString:[dictionary objectForKey:OAUTH2_CORRELATION_ID_RESPONSE]]:
                                nil;
        SAFE_ARC_AUTORELEASE(correlationId);
        return [ADAuthenticationError OAuthServerError:serverOAuth2Error description:errorDetails code:errorCode correlationId:correlationId];
    }
    //In the case of more generic error, e.g. server unavailable, DNS error or no internet connection, the error object will be directly placed in the dictionary:
    return [dictionary objectForKey:AUTH_NON_PROTOCOL_ERROR];
}

//Returns YES if we shouldn't attempt other means to get access token.
//
+ (BOOL)isFinalResult:(ADAuthenticationResult*)result
{
    return (AD_SUCCEEDED == result.status) /* access token provided, no need to try anything else */
    || (result.error && !result.error.protocolCode); //Connection is down, server is unreachable or DNS error. No need to try refresh tokens.
}

//Translates the ADPromptBehavior into prompt query parameter. May return nil, if such
//parameter is not needed.
+ (NSString*)getPromptParameter:(ADPromptBehavior)prompt
{
    switch (prompt) {
        case AD_PROMPT_ALWAYS:
        case AD_FORCE_PROMPT:
            return @"login";
        case AD_PROMPT_REFRESH_SESSION:
            return @"refresh_session";
        default:
            return nil;
    }
}

+ (BOOL)isForcedAuthorization:(ADPromptBehavior)prompt
{
    //If prompt parameter needs to be passed, re-authorization is needed.
    return [ADAuthenticationContext getPromptParameter:prompt] != nil;
}

- (BOOL)hasCacheStore
{
    return self.tokenCacheStore != nil;
}

//Used in the flows, where developer requested an explicit user. The method compares
//the user for the obtained tokens (if provided by the server). If the user is different,
//an error result is returned. Returns the same result, if no issues are found.
+ (ADAuthenticationResult*)updateResult:(ADAuthenticationResult*)result
                                 toUser:(ADUserIdentifier*)userId
{
    if (!result)
    {
        ADAuthenticationError* error =
        [ADAuthenticationError errorFromAuthenticationError:AD_ERROR_DEVELOPER_INVALID_ARGUMENT
                                               protocolCode:nil
                                               errorDetails:@"ADAuthenticationResult is nil"
                                              correlationId:nil];
        return [ADAuthenticationResult resultFromError:error correlationId:[result correlationId]];
    }
    
    if (AD_SUCCEEDED != result.status || !userId || [NSString adIsStringNilOrBlank:userId.userId] || userId.type == OptionalDisplayableId)
    {
        //No user to compare - either no specific user id requested, or no specific userId obtained:
        return result;
    }
    
    ADUserInformation* userInfo = [[result tokenCacheItem] userInformation];
    
    if (!userInfo || ![userId userIdMatchString:userInfo])
    {
        // TODO: This behavior is questionable. Look into removing.
        return result;
    }
    
    if (![ADUserIdentifier identifier:userId matchesInfo:userInfo])
    {
        ADAuthenticationError* error =
        [ADAuthenticationError errorFromAuthenticationError:AD_ERROR_SERVER_WRONG_USER
                                               protocolCode:nil
                                               errorDetails:@"Different user was returned by the server then specified in the acquireToken call. If this is a new sign in use and ADUserIdentifier of OptionalDisplayableId type and pass in the userId returned on the initial authentication flow in all future acquireToken calls."
                                              correlationId:nil];
        return [ADAuthenticationResult resultFromError:error correlationId:[result correlationId]];
    }
    
    return result;
}

@end
