# AFNetworking 的核心 AFURLSessionManager（二）

Blog: [Draveness](http://draveness.me)

<iframe src="http://ghbtns.com/github-btn.html?user=draveness&type=follow&size=large" height="30" width="240" frameborder="0" scrolling="0" style="width:240px; height: 30px;" allowTransparency="true"></iframe>


`AFURLSessionManager` 绝对可以称得上是 AFNetworking 的核心。

1. [负责创建和管理 `NSURLSession`](#NSURLSession)
2. [管理 `NSURLSessionTask`](#NSURLSessionTask)
3. [实现 `NSURLSessionDelegate` 等协议中的代理方法](#NSURLSessionDelegate)
4. [使用 `AFURLSessionManagerTaskDelegate` 管理进度](#AFURLSessionManagerTaskDelegate)
5. [使用 `_AFURLSessionTaskSwizzling` 调剂方法](#_AFURLSessionTaskSwizzling)
6. [引入 `AFSecurityPolicy` 保证请求的安全](#AFSecurityPolocy)
7. [引入 `AFNetworkReachabilityManager` 监控网络状态](#AFNetworkReachabilityManager)

我们会在这里着重介绍上面七个功能中的前五个，分析它是如何包装 `NSURLSession` 以及众多代理方法的。

## <a id="NSURLSession"></a>创建和管理 `NSURLSession`

在使用 `AFURLSessionManager` 时，第一件要做的事情一定是初始化：

```objectivec
- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    self = [super init];
    if (!self) {
        return nil;
    }

    if (!configuration) {
        configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    }

    self.sessionConfiguration = configuration;

    self.operationQueue = [[NSOperationQueue alloc] init];
    self.operationQueue.maxConcurrentOperationCount = 1;

    self.session = [NSURLSession sessionWithConfiguration:self.sessionConfiguration delegate:self delegateQueue:self.operationQueue];

    self.responseSerializer = [AFJSONResponseSerializer serializer];

    self.securityPolicy = [AFSecurityPolicy defaultPolicy];

    self.reachabilityManager = [AFNetworkReachabilityManager sharedManager];

    self.mutableTaskDelegatesKeyedByTaskIdentifier = [[NSMutableDictionary alloc] init];

    self.lock = [[NSLock alloc] init];
    self.lock.name = AFURLSessionManagerLockName;
    
    #1: 为已有的 task 设置代理, 略

    return self;
}
```

在初始化方法中，需要完成初始化一些自己持有的实例：

1. 初始化**会话配置**（NSURLSessionConfiguration），默认为 `defaultSessionConfiguration`
2. 初始化会话（session），并设置会话的代理以及代理队列
3. 初始化管理**响应序列化**（AFJSONResponseSerializer），**安全认证**（AFSecurityPolicy）以及**监控网络状态**（AFNetworkReachabilityManager）的实例
4. 初始化保存 data task 的字典（mutableTaskDelegatesKeyedByTaskIdentifier）

## <a id="NSURLSessionTask"></a>管理 `NSURLSessionTask`

接下来，在获得了 `AFURLSessionManager` 的实例之后，我们可以通过以下方法创建 `NSURLSessionDataTask` 的实例：

```objectivec
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               uploadProgress:(nullable void (^)(NSProgress *uploadProgress)) uploadProgressBlock
                             downloadProgress:(nullable void (^)(NSProgress *downloadProgress)) downloadProgressBlock
                            completionHandler:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject,  NSError * _Nullable error))completionHandler;

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL
                                         progress:(nullable void (^)(NSProgress *uploadProgress)) uploadProgressBlock
                                completionHandler:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject, NSError  * _Nullable error))completionHandler;

...

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                             progress:(nullable void (^)(NSProgress *downloadProgress)) downloadProgressBlock
                                          destination:(nullable NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
                                    completionHandler:(nullable void (^)(NSURLResponse *response, NSURL * _Nullable filePath, NSError * _Nullable error))completionHandler;

...

```

这里省略了一些返回 `NSURLSessionTask` 的方法，因为这些接口的形式都是差不多的。

<a id="dataTaskWithRequest:uploadProgress:downloadProgress:completionHandler:"></id>我们将以 `- [AFURLSessionManager dataTaskWithRequest:uploadProgress:downloadProgress:completionHandler:]` 方法的实现为例，分析它是如何实例化并返回一个 `NSURLSessionTask` 的实例的：

```objectivec
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               uploadProgress:(nullable void (^)(NSProgress *uploadProgress)) uploadProgressBlock
                             downloadProgress:(nullable void (^)(NSProgress *downloadProgress)) downloadProgressBlock
                            completionHandler:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject,  NSError * _Nullable error))completionHandler {

    __block NSURLSessionDataTask *dataTask = nil;
    url_session_manager_create_task_safely(^{
        dataTask = [self.session dataTaskWithRequest:request];
    });

    [self addDelegateForDataTask:dataTask uploadProgress:uploadProgressBlock downloadProgress:downloadProgressBlock completionHandler:completionHandler];

    return dataTask;
}
```

> `url_session_manager_create_task_safely` 的调用是因为苹果框架中的一个 bug [#2093](https://github.com/AFNetworking/AFNetworking/issues/2093)，如果有兴趣可以看一下，在这里就不说明了

1. 调用 `- [NSURLSession dataTaskWithRequest:]` 方法传入 `NSURLRequest`
2. 调用 `- [AFURLSessionManager addDelegateForDataTask:uploadProgress:downloadProgress:completionHandler:]` 方法创建一个 `AFURLSessionManagerTaskDelegate` 对象
3. 将 `completionHandler` `uploadProgressBlock` 和 `downloadProgressBlock` 传入该对象并在相应事件发生时进行回调

```objectivec
- (void)addDelegateForDataTask:(NSURLSessionDataTask *)dataTask
                uploadProgress:(nullable void (^)(NSProgress *uploadProgress)) uploadProgressBlock
              downloadProgress:(nullable void (^)(NSProgress *downloadProgress)) downloadProgressBlock
             completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    AFURLSessionManagerTaskDelegate *delegate = [[AFURLSessionManagerTaskDelegate alloc] init];
    delegate.manager = self;
    delegate.completionHandler = completionHandler;

    dataTask.taskDescription = self.taskDescriptionForSessionTasks;
    [self setDelegate:delegate forTask:dataTask];

    delegate.uploadProgressBlock = uploadProgressBlock;
    delegate.downloadProgressBlock = downloadProgressBlock;
}
```

在这个方法中同时调用了另一个方法 `- [AFURLSessionManager setDelegate:forTask:]` 来设置代理：

```objectivec
- (void)setDelegate:(AFURLSessionManagerTaskDelegate *)delegate
            forTask:(NSURLSessionTask *)task
{
		
	#1: 检查参数, 略

    [self.lock lock];
    self.mutableTaskDelegatesKeyedByTaskIdentifier[@(task.taskIdentifier)] = delegate;
    [delegate setupProgressForTask:task];
    [self addNotificationObserverForTask:task];
    [self.lock unlock];
}
```

正如上面所提到的，`AFURLSessionManager` 就是通过字典 `mutableTaskDelegatesKeyedByTaskIdentifier` 来存储并管理每一个 `NSURLSessionTask`，它以 `taskIdentifier` 为键存储 task。

该方法使用 `NSLock` 来保证不同线程使用 `mutableTaskDelegatesKeyedByTaskIdentifier` 时，不会出现**线程竞争**的问题。

同时调用 [- setupProgressForTask:](#setupProgressForTask)，我们会在下面具体介绍这个方法。

## <a id="NSURLSessionDelegate"></a>实现 `NSURLSessionDelegate` 等协议中的代理方法

在 `AFURLSessionManager` 的头文件中可以看到，它遵循了多个协议，其中包括：

+ `NSURLSessionDelegate`
+ `NSURLSessionTaskDelegate`
+ `NSURLSessionDataDelegate`
+ `NSURLSessionDownloadDelegate`

它在初始化方法 `- [AFURLSessionManager initWithSessionConfiguration:]` 将 `NSURLSession` 的代理指向 `self`，然后**实现这些方法**，提供更简洁的 block 的接口：

```objectivec
- (void)setSessionDidBecomeInvalidBlock:(nullable void (^)(NSURLSession *session, NSError *error))block;
- (void)setSessionDidReceiveAuthenticationChallengeBlock:(nullable NSURLSessionAuthChallengeDisposition (^)(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential * _Nullable __autoreleasing * _Nullable credential))block;
...
```

它为所有的代理协议都提供了对应的 block 接口，方法实现的思路都是相似的，我们以 `- [AFNRLSessionManager setSessionDidBecomeInvalidBlock:]` 为例。

首先调用 setter 方法，将 block 存入 `sessionDidBecomeInvalid` 属性中：

```objectivec
- (void)setSessionDidBecomeInvalidBlock:(void (^)(NSURLSession *session, NSError *error))block {
    self.sessionDidBecomeInvalid = block;
}
```

当代理方法调用时，如果存在对应的 block，会执行对应的 block：

```objectivec
- (void)URLSession:(NSURLSession *)session
didBecomeInvalidWithError:(NSError *)error
{
    if (self.sessionDidBecomeInvalid) {
        self.sessionDidBecomeInvalid(session, error);
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDidInvalidateNotification object:session];
}
```

其他相似的接口实现也都差不多，这里直接跳过了。

## <a id="AFURLSessionManagerTaskDelegate"></a>使用 `AFURLSessionManagerTaskDelegate` 管理进度

在上面我们提到过 `AFURLSessionManagerTaskDelegate` 类，它主要为 task 提供**进度管理**功能，并在 task 结束时**回调**， 也就是调用在 `- [AFURLSessionManager dataTaskWithRequest:uploadProgress:downloadProgress:completionHandler:]` 等方法中传入的 `completionHandler`。

<a id="setupProgressForTask"></a>我们首先分析一下 `AFURLSessionManagerTaskDelegate` 是如何对进度进行跟踪的：

```objectivec
- (void)setupProgressForTask:(NSURLSessionTask *)task {

	#1：设置在上传进度或者下载进度状态改变时的回调
	
	#2：KVO

}
```

该方法的实现有两个部分，一部分是对代理持有的两个属性 `uploadProgress` 和 `downloadProgress` 设置回调

```objectivec
__weak __typeof__(task) weakTask = task;

self.uploadProgress.totalUnitCount = task.countOfBytesExpectedToSend;
[self.uploadProgress setCancellable:YES];
[self.uploadProgress setCancellationHandler:^{
   __typeof__(weakTask) strongTask = weakTask;
   [strongTask cancel];
}];
[self.uploadProgress setPausable:YES];
[self.uploadProgress setPausingHandler:^{
   __typeof__(weakTask) strongTask = weakTask;
   [strongTask suspend];
}];
if ([self.uploadProgress respondsToSelector:@selector(setResumingHandler:)]) {
   [self.uploadProgress setResumingHandler:^{
       __typeof__(weakTask) strongTask = weakTask;
       [strongTask resume];
   }];
}
```

这里只有对 `uploadProgress` 设置回调的代码，设置 `downloadProgress` 与这里完全相同

> 主要目的是在对应 `NSProgress` 的状态改变时，调用 `resume` `suspend` 等方法改变 task 的状态。

第二部分是对 task 和 `NSProgress` 属性进行键值观测：

```objectivec
[task addObserver:self
      forKeyPath:NSStringFromSelector(@selector(countOfBytesReceived))
         options:NSKeyValueObservingOptionNew
         context:NULL];
[task addObserver:self
      forKeyPath:NSStringFromSelector(@selector(countOfBytesExpectedToReceive))
         options:NSKeyValueObservingOptionNew
         context:NULL];

[task addObserver:self
      forKeyPath:NSStringFromSelector(@selector(countOfBytesSent))
         options:NSKeyValueObservingOptionNew
         context:NULL];
[task addObserver:self
      forKeyPath:NSStringFromSelector(@selector(countOfBytesExpectedToSend))
         options:NSKeyValueObservingOptionNew
         context:NULL];

[self.downloadProgress addObserver:self
                       forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                          options:NSKeyValueObservingOptionNew
                          context:NULL];
[self.uploadProgress addObserver:self
                     forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                        options:NSKeyValueObservingOptionNew
                        context:NULL];
```

在 `observeValueForKeypath:ofObject:change:context:` 方法中改变进度，并调用 block

```objectivec
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if ([object isKindOfClass:[NSURLSessionTask class]]) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesReceived))]) {
            self.downloadProgress.completedUnitCount = [change[@"new"] longLongValue];
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesExpectedToReceive))]) {
            self.downloadProgress.totalUnitCount = [change[@"new"] longLongValue];
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesSent))]) {
            self.uploadProgress.completedUnitCount = [change[@"new"] longLongValue];
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesExpectedToSend))]) {
            self.uploadProgress.totalUnitCount = [change[@"new"] longLongValue];
        }
    }
    else if ([object isEqual:self.downloadProgress]) {
        if (self.downloadProgressBlock) {
            self.downloadProgressBlock(object);
        }
    }
    else if ([object isEqual:self.uploadProgress]) {
        if (self.uploadProgressBlock) {
            self.uploadProgressBlock(object);
        }
    }
}
```

对象的某些属性改变时更新 `NSProgress` 对象或使用 block 传递 `NSProgress` 对象 `self.uploadProgressBlock(object)`。

### 代理方法 `URLSession:task:didCompleteWithError:`

在每一个 `NSURLSessionTask` 结束时，都会在代理方法 `URLSession:task:didCompleteWithError:` 中：

1. 调用传入的 `completionHander` block
2. 发出 `AFNetworkingTaskDidCompleteNotification` 通知

```objectivec
- (void)URLSession:(__unused NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    #1：获取数据, 存储 `responseSerializer` 和 `downloadFileURL`

    if (error) {
    	#2：在存在错误时调用 `completionHandler`
    } else {
		#3：调用 `completionHandler`
    }
}
```

这是整个代理方法的骨架，先看一下最简单的第一部分代码：

```objectivec
__block NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
userInfo[AFNetworkingTaskDidCompleteResponseSerializerKey] = manager.responseSerializer;

//Performance Improvement from #2672
NSData *data = nil;
if (self.mutableData) {
   data = [self.mutableData copy];
   //We no longer need the reference, so nil it out to gain back some memory.
   self.mutableData = nil;
}

if (self.downloadFileURL) {
   userInfo[AFNetworkingTaskDidCompleteAssetPathKey] = self.downloadFileURL;
} else if (data) {
   userInfo[AFNetworkingTaskDidCompleteResponseDataKey] = data;
}
```

这部分代码从 `mutableData` 中取出了数据，设置了 `userInfo`。

```objectivec
userInfo[AFNetworkingTaskDidCompleteErrorKey] = error;

dispatch_group_async(manager.completionGroup ?: url_session_manager_completion_group(), manager.completionQueue ?: dispatch_get_main_queue(), ^{
    if (self.completionHandler) {
        self.completionHandler(task.response, responseObject, error);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidCompleteNotification object:task userInfo:userInfo];
    });
});
```

如果当前 `manager` 持有 `completionGroup` 或者 `completionQueue` 就使用它们。否则会创建一个 `dispatch_group_t` 并在主线程中调用 `completionHandler` 并发送通知(在主线程中)。

如果在执行当前 task 时没有遇到错误，那么先**对数据进行序列化**，然后同样调用 block 并发送通知。

```objectivec
dispatch_async(url_session_manager_processing_queue(), ^{
    NSError *serializationError = nil;
    responseObject = [manager.responseSerializer responseObjectForResponse:task.response data:data error:&serializationError];

    if (self.downloadFileURL) {
        responseObject = self.downloadFileURL;
    }

    if (responseObject) {
        userInfo[AFNetworkingTaskDidCompleteSerializedResponseKey] = responseObject;
    }

    if (serializationError) {
        userInfo[AFNetworkingTaskDidCompleteErrorKey] = serializationError;
    }

    dispatch_group_async(manager.completionGroup ?: url_session_manager_completion_group(), manager.completionQueue ?: dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(task.response, responseObject, serializationError);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidCompleteNotification object:task userInfo:userInfo];
        });
    });
});
```

### 代理方法 `URLSession:dataTask:didReceiveData:` 和 `- URLSession:downloadTask:didFinishDownloadingToURL:`

这两个代理方法分别会在收到数据或者完成下载对应文件时调用，作用分别是为 `mutableData` 追加数据和处理下载的文件：

```objectivec
- (void)URLSession:(__unused NSURLSession *)session
          dataTask:(__unused NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    [self.mutableData appendData:data];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    NSError *fileManagerError = nil;
    self.downloadFileURL = nil;

    if (self.downloadTaskDidFinishDownloading) {
        self.downloadFileURL = self.downloadTaskDidFinishDownloading(session, downloadTask, location);
        if (self.downloadFileURL) {
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:self.downloadFileURL error:&fileManagerError];

            if (fileManagerError) {
                [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDownloadTaskDidFailToMoveFileNotification object:downloadTask userInfo:fileManagerError.userInfo];
            }
        }
    }
}
```

## <a id="_AFURLSessionTaskSwizzling"></a>使用 `_AFURLSessionTaskSwizzling` 调剂方法

`_AFURLSessionTaskSwizzling` 的唯一功能就是修改 `NSURLSessionTask` 的 `resume` 和 `suspend` 方法，使用下面的方法替换原有的实现

```objectivec
- (void)af_resume {
    NSAssert([self respondsToSelector:@selector(state)], @"Does not respond to state");
    NSURLSessionTaskState state = [self state];
    [self af_resume];
    
    if (state != NSURLSessionTaskStateRunning) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AFNSURLSessionTaskDidResumeNotification object:self];
    }
}

- (void)af_suspend {
    NSAssert([self respondsToSelector:@selector(state)], @"Does not respond to state");
    NSURLSessionTaskState state = [self state];
    [self af_suspend];
    
    if (state != NSURLSessionTaskStateSuspended) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AFNSURLSessionTaskDidSuspendNotification object:self];
    }
}
```

这样做的目的是为了在方法 `resume` 或者 `suspend` 被调用时发出通知。

具体方法调剂的过程是在 `+ load` 方法中进行的

> `load` 方法只会在整个文件被引入时调用一次

```objectivec
+ (void)load {
    if (NSClassFromString(@"NSURLSessionTask")) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession * session = [NSURLSession sessionWithConfiguration:configuration];
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wnonnull"
        NSURLSessionDataTask *localDataTask = [session dataTaskWithURL:nil];
#pragma clang diagnostic pop
        IMP originalAFResumeIMP = method_getImplementation(class_getInstanceMethod([self class], @selector(af_resume)));
        Class currentClass = [localDataTask class];
        
        while (class_getInstanceMethod(currentClass, @selector(resume))) {
            Class superClass = [currentClass superclass];
            IMP classResumeIMP = method_getImplementation(class_getInstanceMethod(currentClass, @selector(resume)));
            IMP superclassResumeIMP = method_getImplementation(class_getInstanceMethod(superClass, @selector(resume)));
            if (classResumeIMP != superclassResumeIMP &&
                originalAFResumeIMP != classResumeIMP) {
                [self swizzleResumeAndSuspendMethodForClass:currentClass];
            }
            currentClass = [currentClass superclass];
        }
        
        [localDataTask cancel];
        [session finishTasksAndInvalidate];
    }
}
```

1. 首先用 `NSClassFromString(@"NSURLSessionTask")` 判断当前部署的 iOS 版本是否含有类 `NSURLSessionTask`
2. 因为 iOS7 和 iOS8 上对于 `NSURLSessionTask` 的实现不同，所以会通过 `- [NSURLSession dataTaskWithURL:]` 方法返回一个 `NSURLSessionTask` 实例
3. 取得当前类 `_AFURLSessionTaskSwizzling` 中的实现 `af_resume`
4. 如果当前类 `currentClass` 有 `resume` 方法
	+ 真：5
	+ 假：6
5. 使用 `swizzleResumeAndSuspendMethodForClass:` 调剂该类的 `resume` 和 `suspend` 方法
6. `currentClass = [currentClass superclass]` 

> 这里复杂的实现是为了解决 bug [#2702](https://github.com/AFNetworking/AFNetworking/pull/2702)

## <a id='AFSecurityPolicy'></a>引入 `AFSecurityPolicy` 保证请求的安全

`AFSecurityPolicy` 是 `AFNetworking` 用来保证 HTTP 请求安全的类，它被 `AFURLSessionManager` 持有，如果你在 `AFURLSessionManager` 的实现文件中搜索 *self.securityPolicy*，你只会得到三条结果：

1. 初始化 `self.securityPolicy = [AFSecurityPolicy defaultPolicy]`
2. 收到连接层的验证请求时
3. 任务接收到验证请求时

在 API 调用上，后两者都调用了 `- [AFSecurityPolicy evaluateServerTrust:forDomain:]` 方法来判断**当前服务器是否被信任**，我们会在接下来的文章中具体介绍这个方法的实现的作用。

```objectivec
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;

    if (self.taskDidReceiveAuthenticationChallenge) {
        disposition = self.taskDidReceiveAuthenticationChallenge(session, task, challenge, &credential);
    } else {
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
    }

    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}
```

如果没有传入 `taskDidReceiveAuthenticationChallenge` block，只有在上述方法返回 `YES` 时，才会获得认证凭证 `credential`。


## <a id='AFNetworkReachabilityManager'></a>引入 `AFNetworkReachabilityManager` 监控网络状态

与 `AFSecurityPolicy` 相同，`AFURLSessionManager` 对网络状态的监控是由 `AFNetworkReachabilityManager` 来负责的，它仅仅是持有一个 `AFNetworkReachabilityManager` 的对象。

> 真正需要判断网络状态时，仍然**需要开发者调用对应的 API 获取网络状态**。

## 小结

1. `AFURLSessionManager` 是对 `NSURLSession` 的封装
2. 它通过 `- [AFURLSessionManager dataTaskWithRequest:completionHandler:]` 等接口创建 `NSURLSessionDataTask` 的实例
3. 持有一个字典 `mutableTaskDelegatesKeyedByTaskIdentifier` 管理这些 data task 实例
4. 引入 `AFURLSessionManagerTaskDelegate` 来对传入的 `uploadProgressBlock` `downloadProgressBlock` `completionHandler` 在合适的时间进行调用
5. 实现了全部的代理方法来提供 block 接口
6. 通过方法调剂在 data task 状态改变时，发出通知

## 相关文章

关于其他 AFNetworking 源代码分析的其他文章：

+ [AFNetworking 概述（一）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/AFNetworking%20概述（一）.md)
+ [AFNetworking 的核心 AFURLSessionManager（二）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/AFNetworking%20的核心%20AFURLSessionManager（二）.md)
+ [处理请求和响应 AFURLSerialization（三）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/处理请求和响应%20AFURLSerialization（三）.md)
+ [AFNetworkReachabilityManager 监控网络状态（四）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/AFNetworking/AFNetworkReachabilityManager%20监控网络状态（四）.md)


<iframe src="http://ghbtns.com/github-btn.html?user=draveness&type=follow&size=large" height="30" width="240" frameborder="0" scrolling="0" style="width:240px; height: 30px;" allowTransparency="true"></iframe>

Follow: [@Draveness](https://github.com/Draveness)

