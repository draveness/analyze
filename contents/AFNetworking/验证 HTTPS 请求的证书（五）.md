# 验证 HTTPS 请求的证书（五）

Blog: [Draveness](http://draveness.me)

<iframe src="http://ghbtns.com/github-btn.html?user=draveness&type=follow&size=large" height="30" width="240" frameborder="0" scrolling="0" style="width:240px; height: 30px;" allowTransparency="true"></iframe>

自 iOS9 发布之后，由于新特性 [App Transport Security](https://developer.apple.com/library/ios/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html) 的引入，在默认行为下是不能发送 HTTP 请求的。很多网站都在转用 HTTPS，而 `AFNetworking` 中的 `AFSecurityPolicy` 就是为了阻止中间人攻击，以及其它漏洞的工具。

`AFSecurityPolicy` 主要作用就是验证 HTTPS 请求的证书是否有效，如果 app 中有一些敏感信息或者涉及交易信息，一定要使用 HTTPS 来保证交易或者用户信息的安全。

## AFSSLPinningMode

使用 `AFSecurityPolicy` 时，总共有三种验证服务器是否被信任的方式：

```objectivec
typedef NS_ENUM(NSUInteger, AFSSLPinningMode) {
    AFSSLPinningModeNone,
    AFSSLPinningModePublicKey,
    AFSSLPinningModeCertificate,
};
```

+ `AFSSLPinningModeNone` 是默认的认证方式，只会在系统的信任的证书列表中对服务端返回的证书进行验证
+ `AFSSLPinningModeCertificate` 需要客户端预先保存服务端的证书
+ `AFSSLPinningModePublicKey` 也需要预先保存服务端发送的证书，但是这里只会验证证书中的公钥是否正确

## 初始化以及设置

在使用 `AFSecurityPolicy` 验证服务端是否受到信任之前，要对其进行初始化，使用初始化方法时，主要目的是设置**验证服务器是否受信任的方式**。

```objectivec
+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode {
    return [self policyWithPinningMode:pinningMode withPinnedCertificates:[self defaultPinnedCertificates]];
}

+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode withPinnedCertificates:(NSSet *)pinnedCertificates {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = pinningMode;

    [securityPolicy setPinnedCertificates:pinnedCertificates];

    return securityPolicy;
}
```

这里没有什么地方值得解释的。不过在调用 `pinnedCertificate` 的 setter 方法时，会从全部的证书中**取出公钥**保存到 `pinnedPublicKeys` 属性中。

```objectivec
- (void)setPinnedCertificates:(NSSet *)pinnedCertificates {
    _pinnedCertificates = pinnedCertificates;

    if (self.pinnedCertificates) {
        NSMutableSet *mutablePinnedPublicKeys = [NSMutableSet setWithCapacity:[self.pinnedCertificates count]];
        for (NSData *certificate in self.pinnedCertificates) {
            id publicKey = AFPublicKeyForCertificate(certificate);
            if (!publicKey) {
                continue;
            }
            [mutablePinnedPublicKeys addObject:publicKey];
        }
        self.pinnedPublicKeys = [NSSet setWithSet:mutablePinnedPublicKeys];
    } else {
        self.pinnedPublicKeys = nil;
    }
}
```

在这里调用了 `AFPublicKeyForCertificate` 对证书进行操作，返回一个公钥。

## 操作 SecTrustRef

对 `serverTrust` 的操作的函数基本上都是 C 的 API，都定义在 `Security` 模块中，先来分析一下在上一节中 `AFPublicKeyForCertificate` 的实现

```objectivec
static id AFPublicKeyForCertificate(NSData *certificate) {
    id allowedPublicKey = nil;
    SecCertificateRef allowedCertificate;
    SecCertificateRef allowedCertificates[1];
    CFArrayRef tempCertificates = nil;
    SecPolicyRef policy = nil;
    SecTrustRef allowedTrust = nil;
    SecTrustResultType result;

    allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificate);
    __Require_Quiet(allowedCertificate != NULL, _out);

    allowedCertificates[0] = allowedCertificate;
    tempCertificates = CFArrayCreate(NULL, (const void **)allowedCertificates, 1, NULL);

    policy = SecPolicyCreateBasicX509();
    __Require_noErr_Quiet(SecTrustCreateWithCertificates(tempCertificates, policy, &allowedTrust), _out);
    __Require_noErr_Quiet(SecTrustEvaluate(allowedTrust, &result), _out);

    allowedPublicKey = (__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust);

_out:
    if (allowedTrust) {
        CFRelease(allowedTrust);
    }

    if (policy) {
        CFRelease(policy);
    }

    if (tempCertificates) {
        CFRelease(tempCertificates);
    }

    if (allowedCertificate) {
        CFRelease(allowedCertificate);
    }

    return allowedPublicKey;
}
```

1. 初始化一坨临时变量

	```objectivec
	id allowedPublicKey = nil;
	SecCertificateRef allowedCertificate;
	SecCertificateRef allowedCertificates[1];
	CFArrayRef tempCertificates = nil;
	SecPolicyRef policy = nil;
	SecTrustRef allowedTrust = nil;
	SecTrustResultType result;
	```

2. 使用 `SecCertificateCreateWithData` 通过 DER 表示的数据生成一个 `SecCertificateRef`，然后判断返回值是否为 `NULL`

	```objectivec
	allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificate);
	__Require_Quiet(allowedCertificate != NULL, _out);
	```
	
	+ 这里使用了一个非常神奇的宏 `__Require_Quiet`，它会判断 `allowedCertificate != NULL` 是否成立，如果 `allowedCertificate` 为空就会跳到 `_out` 标签处继续执行

		```objectivec
		#ifndef __Require_Quiet
			#define __Require_Quiet(assertion, exceptionLabel)                            \
			  do                                                                          \
			  {                                                                           \
				  if ( __builtin_expect(!(assertion), 0) )                                \
				  {                                                                       \
					  goto exceptionLabel;                                                \
				  }                                                                       \
			  } while ( 0 )
		#endif
		```

3. 通过上面的 `allowedCertificate` 创建一个 `CFArray`

	```objectivec
	allowedCertificates[0] = allowedCertificate;
	tempCertificates = CFArrayCreate(NULL, (const void **)allowedCertificates, 1, NULL);
	```
	
	+ 下面的 `SecTrustCreateWithCertificates` 只会接收数组作为参数。
4. 创建一个默认的符合 X509 标准的 `SecPolicyRef`，通过默认的 `SecPolicyRef` 和证书创建一个 `SecTrustRef` 用于信任评估，对该对象进行信任评估，确认生成的 `SecTrustRef` 是值得信任的。

	```objectivec
	    policy = SecPolicyCreateBasicX509();
	    __Require_noErr_Quiet(SecTrustCreateWithCertificates(tempCertificates, policy, &allowedTrust), _out);
	    __Require_noErr_Quiet(SecTrustEvaluate(allowedTrust, &result), _out);
	```
	
	+ 这里使用的 `__Require_noErr_Quiet` 和上面的宏差不多，只是会根据返回值判断是否存在错误。
5. 获取公钥

	```objectivec
	allowedPublicKey = (__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust);
	```

	+ 这里的 `__bridge_transfer` 会将结果桥接成 `NSObject` 对象，然后将 `SecTrustCopyPublicKey` 返回的指针释放。
6. 释放各种 C 语言指针

	```objectivec
	if (allowedTrust) {
	    CFRelease(allowedTrust);
	}
	
	if (policy) {
	    CFRelease(policy);
	}
	
	if (tempCertificates) {
	    CFRelease(tempCertificates);
	}
	
	if (allowedCertificate) {
	    CFRelease(allowedCertificate);
	}
	```
	
> 每一个 `SecTrustRef` 的对象都是包含多个 `SecCertificateRef` 和 `SecPolicyRef`。其中 `SecCertificateRef` 可以使用 DER 进行表示，并且其中存储着公钥信息。

对它的操作还有 `AFCertificateTrustChainForServerTrust` 和 `AFPublicKeyTrustChainForServerTrust` 但是它们几乎调用了相同的 API。

```objectivec
static NSArray * AFCertificateTrustChainForServerTrust(SecTrustRef serverTrust) {
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];

    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        [trustChain addObject:(__bridge_transfer NSData *)SecCertificateCopyData(certificate)];
    }

    return [NSArray arrayWithArray:trustChain];
}
```

+ `SecTrustGetCertificateAtIndex` 获取 `SecTrustRef` 中的证书
+ `SecCertificateCopyData` 从证书中或者 DER 表示的数据

## 验证服务端是否受信

验证服务端是否守信是通过 `- [AFSecurityPolicy evaluateServerTrust:forDomain:]` 方法进行的。

```objectivec
- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain
{

	#1: 不能隐式地信任自己签发的证书
	
	#2: 设置 policy
	
	#3: 验证证书是否有效
	
	#4: 根据 SSLPinningMode 对服务端进行验证
    
    return NO;
}
```

1. 不能隐式地信任自己签发的证书

	```objectivec
	if (domain && self.allowInvalidCertificates && self.validatesDomainName && (self.SSLPinningMode == AFSSLPinningModeNone || [self.pinnedCertificates count] == 0)) {
	    NSLog(@"In order to validate a domain name for self signed certificates, you MUST use pinning.");
	    return NO;
	}
	```

	> Do not implicitly trust self-signed certificates as anchors (kSecTrustOptionImplicitAnchors).
	> Instead, add your own (self-signed) CA certificate to the list of trusted anchors.

	+ 所以如果没有提供证书或者不验证证书，并且还设置 `allowInvalidCertificates` 为**真**，满足上面的所有条件，说明这次的验证是不安全的，会直接返回 `NO`
2. 设置 policy

	```objectivec
	NSMutableArray *policies = [NSMutableArray array];
	if (self.validatesDomainName) {
	    [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
	} else {
	    [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
	}
	```

	+ 如果要验证域名的话，就以域名为参数创建一个 `SecPolicyRef`，否则会创建一个符合 X509 标准的默认 `SecPolicyRef` 对象
3. 验证证书的有效性

	```objectivec
	if (self.SSLPinningMode == AFSSLPinningModeNone) {
	    return self.allowInvalidCertificates || AFServerTrustIsValid(serverTrust);
	} else if (!AFServerTrustIsValid(serverTrust) && !self.allowInvalidCertificates) {
	    return NO;
	}
	```

	+ 如果**只根据信任列表中的证书**进行验证，即 `self.SSLPinningMode == AFSSLPinningModeNone`。如果允许无效的证书的就会直接返回 `YES`。不允许就会对服务端信任进行验证。
	+ 如果服务器信任无效，并且不允许无效证书，就会返回 `NO`
4. 根据 `SSLPinningMode` 对服务器信任进行验证

	```objectivec
	switch (self.SSLPinningMode) {
	    case AFSSLPinningModeNone:
	    default:
	        return NO;
	    case AFSSLPinningModeCertificate: {
			...
	    }
	    case AFSSLPinningModePublicKey: {
			...
	    }
	}
	```

	+ `AFSSLPinningModeNone` 直接返回 `NO`
	+ `AFSSLPinningModeCertificate`

		```objectivec
		NSMutableArray *pinnedCertificates = [NSMutableArray array];
		for (NSData *certificateData in self.pinnedCertificates) {
		    [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
		}
		SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
		
		if (!AFServerTrustIsValid(serverTrust)) {
		    return NO;
		}
		
		// obtain the chain after being validated, which *should* contain the pinned certificate in the last position (if it's the Root CA)
		NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
		
		for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
		    if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
		        return YES;
		    }
		}
		
		return NO;
		```
	
		1. 从 `self.pinnedCertificates` 中获取 DER 表示的数据
		2. 使用 `SecTrustSetAnchorCertificates` 为服务器信任设置证书
		3. 判断服务器信任的有效性
		4. 使用 `AFCertificateTrustChainForServerTrust` 获取服务器信任中的全部 DER 表示的证书
		5. 如果 `pinnedCertificates` 中有相同的证书，就会返回 `YES`

	+ `AFSSLPinningModePublicKey`

		```objectivec
		NSUInteger trustedPublicKeyCount = 0;
		NSArray *publicKeys = AFPublicKeyTrustChainForServerTrust(serverTrust);
		
		for (id trustChainPublicKey in publicKeys) {
		    for (id pinnedPublicKey in self.pinnedPublicKeys) {
		        if (AFSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
		            trustedPublicKeyCount += 1;
		        }
		    }
		}
		return trustedPublicKeyCount > 0;
		```

		+ 这部分的实现和上面的差不多，区别有两点
			1. 会从服务器信任中获取公钥
			2. `pinnedPublicKeys` 中的公钥与服务器信任中的公钥相同的数量大于 0，就会返回真

## 与 AFURLSessionManager 协作

在代理协议 `- URLSession:didReceiveChallenge:completionHandler:` 或者 `- URLSession:task:didReceiveChallenge:completionHandler:` 代理方法被调用时会运行这段代码

```objectivec
if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
    if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
        disposition = NSURLSessionAuthChallengeUseCredential;
        credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
    } else {
        disposition = NSURLSessionAuthChallengeRejectProtectionSpace;
    }
} else {
    disposition = NSURLSessionAuthChallengePerformDefaultHandling;
}
```

`NSURLAuthenticationChallenge` 表示一个认证的挑战，提供了关于这次认证的全部信息。它有一个非常重要的属性 `protectionSpace`，这里保存了需要认证的保护空间, 每一个 `NSURLProtectionSpace` 对象都保存了主机地址，端口和认证方法等重要信息。

在上面的方法中，如果保护空间中的认证方法为 `NSURLAuthenticationMethodServerTrust`，那么就会使用在上一小节中提到的方法 `- [AFSecurityPolicy evaluateServerTrust:forDomain:]` 对保护空间中的 `serverTrust` 以及域名 `host` 进行认证

根据认证的结果，会在 `completionHandler` 中传入不同的 `disposition` 和 `credential` 参数。

## 小结

+ `AFSecurityPolicy` 同样也作为一个即插即用的模块，在 AFNetworking 中作为验证 HTTPS 证书是否有效的模块存在，在 iOS 对 HTTPS 日渐重视的今天，在我看来，使用 HTTPS 会成为今后 API 开发的标配。


## 相关文章

关于其他 AFNetworking 源代码分析的其他文章：

+ [AFNetworking 概述（一）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/AFNetworking%20概述（一）.md)
+ [AFNetworking 的核心 AFURLSessionManager（二）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/AFNetworking%20的核心%20AFURLSessionManager（二）.md)
+ [处理请求和响应 AFURLSerialization（三）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/处理请求和响应%20AFURLSerialization（三）.md)
+ [AFNetworkReachabilityManager 监控网络状态（四）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/AFNetworkReachabilityManager%20监控网络状态（四）.md)
+ [验证 HTTPS 请求的证书（五）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/验证%20HTTPS%20请求的证书（五）.md)


<iframe src="http://ghbtns.com/github-btn.html?user=draveness&type=follow&size=large" height="30" width="240" frameborder="0" scrolling="0" style="width:240px; height: 30px;" allowTransparency="true"></iframe>

Follow: [@Draveness](https://github.com/Draveness)

