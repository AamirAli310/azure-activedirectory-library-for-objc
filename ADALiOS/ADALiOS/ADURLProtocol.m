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

#import "ADURLProtocol.h"
#import "ADLogger.h"
#import "ADNTLMHandler.h"
#import "WorkPlaceJoinConstants.h"

NSString* const sLog = @"HTTP Protocol";

@implementation ADURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    //TODO: Experiment with filtering of the URL to ensure that this class intercepts only
    //ADAL initiated webview traffic, INCLUDING redirects. This may have issues, if requests are
    //made from javascript code, instead of full page redirection. As such, I am intercepting
    //all traffic while authorization webview session is displayed for now.
    if ( [[request.URL.scheme lowercaseString] isEqualToString:@"https"] )
    {
        //This class needs to handle only TLS. The check below is needed to avoid infinite recursion between starting and checking
        //for initialization
        if ( [NSURLProtocol propertyForKey:@"ADURLProtocol" inRequest:request] == nil )
        {
            AD_LOG_VERBOSE_F(sLog, @"Requested handling of URL: %@", [request.URL absoluteString]);
            
            return YES;
        }
    }
    
    AD_LOG_VERBOSE_F(sLog, @"Ignoring handling of URL: %@", [request.URL absoluteString]);
    
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    AD_LOG_VERBOSE_F(sLog, @"canonicalRequestForRequest: %@", [request.URL absoluteString] );
    
    return request;
}

- (void)startLoading
{
    if (!self.request)
    {
        AD_LOG_WARN(sLog, @"startLoading called without specifying the request.");
        return;
    }
    
    AD_LOG_VERBOSE_F(sLog, @"startLoading: %@", [self.request.URL absoluteString] );
    NSMutableURLRequest *mutableRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@"YES" forKey:@"ADURLProtocol" inRequest:mutableRequest];
    _connection = [[NSURLConnection alloc] initWithRequest:mutableRequest
                                                  delegate:self
                                          startImmediately:YES];
    SAFE_ARC_RELEASE(mutableRequest);
    mutableRequest = nil;
}

- (void)stopLoading
{
    AD_LOG_VERBOSE_F(sLog, @"Stop loading");
    [_connection cancel];
    SAFE_ARC_RELEASE(_connection);
    _connection = nil;
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
}

#pragma mark - NSURLConnectionDelegate Methods

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
#pragma unused (connection)
    
    AD_LOG_VERBOSE_F(sLog, @"connection:didFaileWithError: %@", error);
    [self.client URLProtocol:self didFailWithError:error];
}

-(void) connection:(NSURLConnection *)connection
willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
#pragma unused (connection)
    
    AD_LOG_VERBOSE_F(sLog, @"connection:willSendRequestForAuthenticationChallenge: %@. Previous challenge failure count: %ld", challenge.protectionSpace.authenticationMethod, (long)challenge.previousFailureCount);
    BOOL ntlmHandled = NO;
#if TARGET_OS_IPHONE
    ntlmHandled = [ADNTLMHandler handleNTLMChallenge:challenge urlRequest:[connection currentRequest] customProtocol:self];
#else
    ntlmHandled = [ADNTLMHandler handleNTLMChallenge:challenge customProtocol:self];
#endif
    
    if (!ntlmHandled)
    {
        // Do default handling
        [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
    }
}

#pragma mark - NSURLConnectionDataDelegate Methods

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response
{
#pragma unused (connection)
    
    AD_LOG_VERBOSE_F(sLog, @"HTTPProtocol::connection:willSendRequest:. Redirect response: %@. New request:%@", response.URL, request.URL);
    //Ensure that the webview gets the redirect notifications:
    if (response)
    {
        NSMutableURLRequest* mutableRequest = [request mutableCopy];
        
        [[self class] removePropertyForKey:@"ADURLProtocol" inRequest:mutableRequest];
        [self.client URLProtocol:self wasRedirectedToRequest:mutableRequest redirectResponse:response];
        
        [_connection cancel];
        SAFE_ARC_RELEASE(_connection);
        _connection = nil;
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
        
        
#if TARGET_OS_IPHONE
        if(![request.allHTTPHeaderFields valueForKey:pKeyAuthHeader])
        {
            [mutableRequest addValue:pKeyAuthHeaderVersion forHTTPHeaderField:pKeyAuthHeader];
        }
#endif
        return mutableRequest;
    }
    
#if TARGET_OS_IPHONE
    if(![request.allHTTPHeaderFields valueForKey:pKeyAuthHeader])
    {
        NSMutableURLRequest* mutableRequest = [request mutableCopy];
        [mutableRequest addValue:pKeyAuthHeaderVersion forHTTPHeaderField:pKeyAuthHeader];
        request = [mutableRequest copy];
        mutableRequest = nil;
    }
#endif
    
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
#pragma unused (connection)
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
#pragma unused (connection)
    [self.client URLProtocol:self didLoadData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
#pragma unused (connection)
    [self.client URLProtocolDidFinishLoading:self];
    SAFE_ARC_RELEASE(_connection);
    _connection = nil;
}


@end
