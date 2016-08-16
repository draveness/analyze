# AFNetworking 概述（一）

![afnetworking-logo](../images/afnetworking-logo.png)

Blog: [Draveness](http://draveness.me)

<iframe src="http://ghbtns.com/github-btn.html?user=draveness&type=follow&size=large" height="30" width="240" frameborder="0" scrolling="0" style="width:240px; height: 30px;" allowTransparency="true"></iframe> 

在这一系列的文章中，我会对 AFNetworking 的源代码进行分析，深入了解一下它是如何构建的，如何在日常中完成发送 HTTP 请求、构建网络层这一任务。

[AFNetworking](https://github.com/AFNetworking/AFNetworking) 是如今 iOS 开发中不可缺少的组件之一。它的 github 配置上是如下介绍的：

> Perhaps the most important feature of all, however, is the amazing community of developers who use and contribute to AFNetworking every day. AFNetworking powers some of the most popular and critically-acclaimed apps on the iPhone, iPad, and Mac.

可以说**使用 AFNetworking 的工程师构成的社区**才使得它变得非常重要。

## 概述

我们今天是来深入研究一下这个与我们日常开发密切相关的框架是如何实现的。

这是我对 AFNetworking 整个架构的理解，随后一系列的文章也会逐步分析这些模块。

![afnetworking-arch](../images/afnetworking-arch.png)


在这篇文章中，我们有两个问题需要了解：

1. 如何使用 NSURLSession 发出 HTTP 请求
2. 如何使用 AFNetworking 发出 HTTP 请求

## NSURLSession

`NSURLSession` 以及与它相关的类为我们提供了下载内容的 API，这个 API 提供了一系列的代理方法来支持身份认证，并且支持后台下载。

使用 `NSURLSession` 来进行 HTTP 请求并且获得数据总共有五个步骤：

1. 实例化一个 `NSURLRequest/NSMutableURLRequest`，设置 URL
2. 通过 `- sharedSession` 方法获取 `NSURLSession`
3. 在 session 上调用 `- dataTaskWithRequest:completionHandler:` 方法返回一个 `NSURLSessionDataTask`
4. 向 data task 发送消息 `- resume`，开始执行这个任务
5. 在 completionHandler 中将数据编码，返回字符串

```objectivec
NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[[NSURL alloc] initWithString:@"https://github.com"]];
NSURLSession *session = [NSURLSession sharedSession];
NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                       completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                           NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                           NSLog(@"%@", dataStr);
                                       }];
[task resume];
```

这一段代码可以说是使用 `NSURLSession` 发送请求最简单的一段代码了，当你运行这段代码会在控制台看到一坨 [github](github.com) 首页的 html。

```html
<!DOCTYPE html>
<html lang="en" class="">
  <head prefix="og: http://ogp.me/ns# fb: http://ogp.me/ns/fb# object: http://ogp.me/ns/object# article: http://ogp.me/ns/article# profile: http://ogp.me/ns/profile#">
    <meta charset='utf-8'>
		...
	</head>
	...
</html>
```

## AFNetworking

AFNetworking 的使用也是比较简单的，使用它来发出 HTTP 请求有两个步骤

1. 以服务器的**主机地址或者域名**生成一个 AFHTTPSessionManager 的实例
2. 调用 `- GET:parameters:progress:success:failure:` 方法

```objectivec
AFHTTPSessionManager *manager = [[AFHTTPSessionManager alloc] initWithBaseURL:[[NSURL alloc] initWithString:@"hostname"]];
[manager GET:@"relative_url" parameters:nil progress:nil
    success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSLog(@"%@" ,responseObject);
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"%@", error);
    }];
```

> 注意：在 iOS9 中，苹果默认全局 HTTPs，如果你要发送不安全的 HTTP 请求，需要在 info.plist 中加入如下键值对才能发出不安全的 HTTP 请求

>  ![afnetworking-plist](../images/afnetworking-plist.png)

> 还有一件事情是要注意的是，AFNetworking 默认接收 json 格式的响应（因为这是在 iOS 平台上的框架，一般不需要 text/html），如果想要返回 html，需要设置 `acceptableContentTypes`

## AFNetworking 的调用栈

在这一节中我们要分析一下在上面两个方法的调用栈，首先来看的是 `AFHTTPSessionManager` 的初始化方法 `- initWithBaseURL:`

```objectivec
- [AFHTTPSessionManager initWithBaseURL:]
	- [AFHTTPSessionManager initWithBaseURL:sessionConfiguration:]
		- [AFURLSessionManager initWithSessionConfiguration:]
			- [NSURLSession sessionWithConfiguration:delegate:delegateQueue:]
			- [AFJSONResponseSerializer serializer] // 负责序列化响应
			- [AFSecurityPolicy defaultPolicy] // 负责身份认证
			- [AFNetworkReachabilityManager sharedManager] // 查看网络连接情况
		- [AFHTTPRequestSerializer serializer] // 负责序列化请求
		- [AFJSONResponseSerializer serializer] // 负责序列化响应
```

从这个初始化方法的调用栈，我们可以非常清晰地了解这个框架的结构：

+ 其中 `AFURLSessionManager` 是 `AFHTTPSessionManager` 的父类
+ `AFURLSessionManager` 负责生成 `NSURLSession` 的实例，管理 `AFSecurityPolicy` 和 `AFNetworkReachabilityManager`，来保证请求的安全和查看网络连接情况，它有一个 `AFJSONResponseSerializer` 的实例来序列化 HTTP 响应
+ `AFHTTPSessionManager` 有着**自己的** `AFHTTPRequestSerializer` 和 `AFJSONResponseSerializer` 来管理请求和响应的序列化，同时**依赖父类提供的接口**保证安全、监控网络状态，实现发出 HTTP 请求这一核心功能

初始化方法很好地揭示了 AFNetworking 整个框架的架构，接下来我们要通过分析另一个方法 `- GET:parameters:process:success:failure:` 的调用栈，看一下 HTTP 请求是如何发出的：

```objectivec
- [AFHTTPSessionManager GET:parameters:process:success:failure:]
	- [AFHTTPSessionManager dataTaskWithHTTPMethod:parameters:uploadProgress:downloadProgress:success:failure:] // 返回 NSURLSessionDataTask #1
		- [AFHTTPRequestSerializer requestWithMethod:URLString:parameters:error:] // 返回 NSMutableURLRequest
		- [AFURLSessionManager dataTaskWithRequest:uploadProgress:downloadProgress:completionHandler:] // 返回 NSURLSessionDataTask #2
			- [NSURLSession dataTaskWithRequest:] // 返回 NSURLSessionDataTask #3
			- [AFURLSessionManager addDelegateForDataTask:uploadProgress:downloadProgress:completionHandler:]
				- [AFURLSessionManagerTaskDelegate init]
				- [AFURLSessionManager setDelegate:forTask:]
	- [NSURLSessionDataTask resume]
```

在这里 `#1` `#2` `#3` 处返回的是同一个 data task，我们可以看到，在 `#3` 处调用的方法 `- [NSURLSession dataTaskWithRequest:]` 和只使用 `NSURLSession` 发出 HTTP 请求时调用的方法 `- [NSURLSession dataTaskWithRequest:completionHandler:]` 差不多。在这个地方返回 data task 之后，我们再调用 `- resume` 方法执行请求，并在某些事件执行时通知代理 `AFURLSessionManagerTaskDelegate`

## 小结

AFNetworking 实际上只是对 `NSURLSession` 高度地封装, 提供一些简单易用的 API 方便我们在 iOS 开发中发出网络请求并在其上更快地构建网络层组件并提供合理的接口.

到这里，这一篇文章从上到下对 AFNetworking 是如何调用的进行了一个简单的概述，我会在随后的文章中会具体介绍 AFNetworking 中的每一个模块，了解它们是如何工作，并且如何合理地组织到一起的。

## 相关文章

关于其他 AFNetworking 源代码分析的其他文章：

+ [AFNetworking 概述（一）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/AFNetworking%20概述（一）.md)
+ [AFNetworking 的核心 AFURLSessionManager（二）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/AFNetworking%20的核心%20AFURLSessionManager（二）.md)
+ [处理请求和响应 AFURLSerialization（三）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/处理请求和响应%20AFURLSerialization（三）.md)
+ [AFNetworkReachabilityManager 监控网络状态（四）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/AFNetworkReachabilityManager%20监控网络状态（四）.md)
+ [验证 HTTPS 请求的证书（五）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/验证%20HTTPS%20请求的证书（五）.md)


Follow: [@Draveness](https://github.com/Draveness)


