# iOS 源代码分析 --- Alamofire


已经有几个月没有阅读著名开源项目的源代码了, 最近才有时间来做这件事情.

下面是 Github 主页上对 [Alamofire](https://github.com/Alamofire/Alamofire) 的描述

> Elegant HTTP Networking in Swift

为什么这次我选择阅读 Alamofire 的源代码而不是 AFNetworking 呢, 其实有两点原因. 

1. AFNetworking 作为一个有着很多年的历史的框架, 它虽然有着强大的社区, 不过因为时间太久了, 可能有一些历史上的包袱. 而 Alamofire 是在 Swift 诞生之后才开始出现的, 到现在为止也并没有多长时间, 它的源代码都是**新鲜**的.
2. 由于最近在写 Swift 的项目, 所以没有选择 AFNetworking.

在阅读 Alamofire 的源代码之前, 我先粗略的查看了一下 Alamofire 实现的代码行数:

```shell
$ find Source -name "*.swift" | xargs cat |wc -l
> 3363
```

也就是说 Alamofire 在包含注释以及空行的情况下, 只使用了 3000 多行代码就实现了一个用于处理 HTTP 请求的框架.

所以它描述中的 `Elegant` 也可以说是名副其实. 

## 目录结构

首先, 我们来看一下 Alamofire 中的目录结构, 来了解一下它是如何组织各个文件的.

```
- Source
	- Alamore.swift
	- Core
		- Manager.swift
		- ParameterEncoding.swift
		- Request.swift
	- Features
		- Download.swift
		- MultipartFromData.swift
		- ResponseSeriallization.swift
		- Upload.swift
		- Validation.swift
```

框架中最核心并且我们最值得关注的就是 `Alamore.swift` `Manager.swift` 和 `Request.swift` 这三个文件. 也是在这篇 post 中主要介绍的三个文件.

### Alamofire

在 Alamofire 中并没有找到 `Alamofire` 这个类, 相反这仅仅是一个命名空间, 在 `Alamofire.swift` 这个文件中不存在 `class Alamofire` 这种关键字, 这只是为了使得方法名更简洁的一种手段.

我们在使用 Alamofire 时, 往往都会采用这种方式:

```swift
Alamofire.request(.GET, "http://httpbin.org/get")
```

有了 Alamofire 作为命名空间, 就不用担心 `request` 方法与其他同名方法的冲突了.

在 `Alamofire.swift`  文件中为我们提供了三类方法:

* request
* upload
* download

这三种方法都是通过调用 `Manager` 对应的操作来完成请求, 上传和下载的操作, 并返回一个 `Request` 的实例.

下面是 `request` 方法的一个实现:

```swift
public func request(method: Method, URLString: URLStringConvertible, parameters: [String: AnyObject]? = nil, encoding: ParameterEncoding = .URL, headers: [String: String]? = nil) -> Request {
    return Manager.sharedInstance.request(method, URLString, parameters: parameters, encoding: encoding, headers: headers)
}
```

这也就是 `Alamofire.request(.GET, "http://httpbin.org/get")` 所调用的方法. 而这个方法实际上就是通过这些参数调用 `Manager` 的具体方法, 我们所使用的 `request` 也好 `download` 也好, 都是对 `Manager` 方法的一个包装罢了.

### Manager

Alamofire 中的几乎所有操作都是通过 `Manager` 来控制, 而 `Manager` 也可以说是 Alamofire 的核心部分, 它负责与 `Request` 交互完成网络操作:

>  Responsible for creating and managing `Request` objects, as well as their underlying `NSURLSession`.

#### Manager.sharedInstance

`Manager` 在 Alamofire 中有着极其重要的地位, 而在 `Manager` 方法的设计中, 一般也使用 `sharedInstance` 来获取 `Manager` 的单例:

```swift
public static let sharedInstance: Manager = {
    let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
    configuration.HTTPAdditionalHeaders = Manager.defaultHTTPHeaders

    return Manager(configuration: configuration)
}()
```

对于其中 `defaultHTTPHeaders` 和 `Manager` 的初始化方法, 在这里就不多提了, 但是在这里有必要说明一下 `SessionDelegate` 这个类, 在 `Manager` 的初始化方法中, 调用了 `SessionDelegate` 的初始化方法, 返回了一个它的实例.

#### SessionDelegate

> Responsible for handling all delegate callbacks for the underlying session.

这个类的主要作用就是处理对应 session 的所有代理回调, 它持有两个属性:

```swift
private var subdelegates: [Int: Request.TaskDelegate] = [:]
private let subdelegateQueue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)
```

`subdelegates` 以 task 标识符为键, 存储了所有的回调. `subdelegateQueue` 是一个异步的队列, 用于处理任务的回调.

#### Manager.sharedInstace.request

`Manager` 有两个返回 `Request` 实例的 `request` 方法:

* `public func request(method: Method, _ URLString: URLStringConvertible, parameters: [String: AnyObject]? = nil, encoding: ParameterEncoding = .URL, headers: [String: String]? = nil) -> Request`
* `public func request(URLRequest: URLRequestConvertible) -> Request`

第一个方法的实现非常的简单:

```swift
public func request(method: Method, _ URLString: URLStringConvertible, parameters: [String: AnyObject]? = nil, encoding: ParameterEncoding = .URL, headers: [String: String]? = nil) -> Request {
    let mutableURLRequest = URLRequest(method, URLString, headers: headers)
    let encodedURLRequest = encoding.encode(mutableURLRequest, parameters: parameters).0
    return request(encodedURLRequest)
}
```

方法中首先调用了 `URLRequest` 方法:

```swift
func URLRequest(method: Method, URLString: URLStringConvertible, headers: [String: String]? = nil) -> NSMutableURLRequest {
    let mutableURLRequest = NSMutableURLRequest(URL: NSURL(string: URLString.URLString)!)
    mutableURLRequest.HTTPMethod = method.rawValue

    if let headers = headers {
        for (headerField, headerValue) in headers {
        mutableURLRequest.setValue(headerValue, forHTTPHeaderField: headerField)
        }
    }

    return mutableURLRequest
}
```

首先创建一个 `NSMutableURLRequest` 设置它的 HTTP 请求方法和 HTTP header, 然后返回这个请求.

在请求被返回之后, 就进入了下一个环节 `encode`.

```swift
let encodedURLRequest = encoding.encode(mutableURLRequest, parameters: parameters).0
```

#### ParameterEncoding.encoding

`ParameterEncoding` 是一个用来处理一系列的参数是如何被"添加"到 URL 请求上的.

> Used to specify the way in which a set of parameters are applied to a URL request.

`ParameterEncoding` 类型中有四种不同的编码方法:

* URL
* JSON
* PropertyList
* Custom

其中 `encode` 方法就根据 `ParameterEncoding` 类型的不同返回不同的 `NSMutableURLRequest`

如果 `PatameterEncoding` 的类型为 `URL`, 那么就会把这次请求的参数以下面这种形式添加到请求的 `URL` 上

```
foo[]=1&foo[]=2
```

在完成对参数的编码之后, 就会调用另一个同名的 `request` 方法

```swift
request(encodedURLRequest)
```

#### Manager.sharedInstace.request(URLRequestConvertible)

`request` 方法根据指定的 URL 请求返回一个 `Request`

> Creates a request for the specified URL request.

它使用 `dispatch_sync` 把一个 `NSURLRequest` 请求同步加到一个串行队列中, 返回一个 `NSURLSessionDataTask`. 并通过 `session` 和 `dataTask` 生成一个 `Request` 的实例.

```swift
public func request(URLRequest: URLRequestConvertible) -> Request {
    var dataTask: NSURLSessionDataTask!

    dispatch_sync(queue) {
        dataTask = self.session.dataTaskWithRequest(URLRequest.URLRequest)
    }

    let request = Request(session: session, task: dataTask)
    delegate[request.delegate.task] = request.delegate

    if startRequestsImmediately {
        request.resume()
    }

    return request
}
```

这段代码还是很直观的, 它的主要作用就是创建 `Request` 实例, 并发送请求.

#### Request.init

`Request` 这个类的 `init` 方法根据传入的 `task` 类型的不同, 生成了不用类型的 `TaskDelegate`, 可以说是 Swift 中对于反射的运用:

```swift
init(session: NSURLSession, task: NSURLSessionTask) {
    self.session = session

    switch task {
    case is NSURLSessionUploadTask:
        self.delegate = UploadTaskDelegate(task: task)
    case is NSURLSessionDataTask:
        self.delegate = DataTaskDelegate(task: task)
    case is NSURLSessionDownloadTask:
        self.delegate = DownloadTaskDelegate(task: task)
    default:
        self.delegate = TaskDelegate(task: task)
    }
}
```

在 `UploadTaskDelegate` `DataTaskDelegate` `DownloadTaskDelegate` 和 `TaskDelegate` 几个类的作用是处理对应任务的回调, 在 `Request` 实例初始化之后, 会把对应的 `delegate` 添加到 `manager` 持有的 `delegate` 数组中, 方便之后在对应的时间节点通知代理事件的发生.

在最后返回 `request`, 到这里一次网络请求就基本完成了.

### ResponseSerialization

`ResponseSerialization` 是用来对 `Reponse` 返回的值进行序列化显示的一个 extension.

它的设计非常的巧妙, 同时可以处理 `Data` `String` 和 `JSON` 格式的数据, 

#### ResponseSerializer 协议

Alamofire 在这个文件的开头定义了一个所有 responseSerializer 都必须遵循的 `protocol`, 这个 protocol 的内容十分简单, 其中最重要的就是:

```swift
var serializeResponse: (NSURLRequest?, NSHTTPURLResponse?, NSData?) -> Result<SerializedObject> { get }
```

所有的 responseSerializer 都必须包含 `serializeResponse` 这个闭包, 它的作用就是处理 response.

#### GenericResponseSerializer

为了同时处理不同类型的数据, Alamofire 使用泛型创建了 `GenericResponseSerializer<T>`, 这个结构体为处理 `JSON` `XML` 和 `NSData` 等数据的 responseSerializer 提供了一个骨架.

它在结构体中遵循了 `ResponseSerializer` 协议, 然后提供了一个 `init` 方法

```swift
public init(serializeResponse: (NSURLRequest?, NSHTTPURLResponse?, NSData?) -> Result<SerializedObject>) {
    self.serializeResponse = serializeResponse
}
```

#### response 方法

在 Alamofire 中, 如果我们调用了 reponse 方法, 就会在 request 结束时, 添加一个处理器来处理服务器的 reponse.

这个方法有两个版本, 第一个版本是不对返回的数据进行处理:

```swift
public func response(
    queue queue: dispatch_queue_t? = nil,
    completionHandler: (NSURLRequest?, NSHTTPURLResponse?, NSData?, NSError?) -> Void)
    -> Self
{
    delegate.queue.addOperationWithBlock {
        dispatch_async(queue ?? dispatch_get_main_queue()) {
            completionHandler(self.request, self.response, self.delegate.data, self.delegate.error)
        }
    }

    return self
}
```

该方法的实现将一个 block 追加到 request 所在的队列中, 其它的部分过于简单, 在这里就不多说了.

另一个版本的 response 的作用就是处理多种类型的数据.

```swift
public func response<T: ResponseSerializer, V where T.SerializedObject == V>(
    queue queue: dispatch_queue_t? = nil,
    responseSerializer: T,
    completionHandler: (NSURLRequest?, NSHTTPURLResponse?, Result<V>) -> Void)
    -> Self
{
    delegate.queue.addOperationWithBlock {
        var result = responseSerializer.serializeResponse(self.request, self.response, self.delegate.data)

        if let error = self.delegate.error {
            result = .Failure(self.delegate.data, error)
        }

        dispatch_async(queue ?? dispatch_get_main_queue()) {
            completionHandler(self.request, self.response, result)
        }
    }

    return self
}
```

它会直接调用参数中 `responseSerializer` 所持有的闭包 `serializeResponse`, 然后返回对应的数据.

#### 多种类型的 response 数据

有了高级的抽象方法 `response`, 我们现在就可以直接向这个方法中传入不同的 `responseSerializer` 来产生不同数据类型的 `handler`

比如说 `NSData`

```swift
public static func dataResponseSerializer() -> GenericResponseSerializer<NSData> {
    return GenericResponseSerializer { _, _, data in
        guard let validData = data else {
            let failureReason = "Data could not be serialized. Input data was nil."
            let error = Error.errorWithCode(.DataSerializationFailed, failureReason: failureReason)
            return .Failure(data, error)
        }

        return .Success(validData)
    }
}

public func responseData(completionHandler: (NSURLRequest?, NSHTTPURLResponse?, Result<NSData>) -> Void) -> Self {
    return response(responseSerializer: Request.dataResponseSerializer(), completionHandler: completionHandler)
}
```

在 `ResponseSerialization.swift` 这个文件中, 你还可以看到其中对于 `String` `JSON` `propertyList` 数据处理的 `responseSerializer`.

### URLStringConvertible

在 ALamofire 的实现中还有一些我们可以学习的地方. 因为 Alamofire 是一个 Swift 的框架, 而且 Swift 是静态语言, 所以有一些坑是必须要解决的, 比如说 `NSURL` 和 `String` 之间的相互转换. 在 Alamofire 中用了一种非常优雅的解决方案, 我相信能够给很多人带来一定的启发.

首先我们先定义了一个 `protocol` `URLStringConvertible` (注释部分已经省略) :

```swift
public protocol URLStringConvertible {
    var URLString: String { get }
}
```

这个 `protocol` 只定义了一个 `var`, 遵循这个协议的类必须实现 `URLString` 返回 `String` 的这个**功能**.

接下来让所有可以转化为 `String` 的类全部遵循这个协议, 这个方法虽然我以前知道, 不过我还是第一次见到在实际中的使用, 真的非常的优雅:

```swift
extension String: URLStringConvertible {
    public var URLString: String {
        return self
    }
}

extension NSURL: URLStringConvertible {
    public var URLString: String {
        return absoluteString!
    }
}

extension NSURLComponents: URLStringConvertible {
    public var URLString: String {
        return URL!.URLString
    }
}

extension NSURLRequest: URLStringConvertible {
    public var URLString: String {
        return URL!.URLString
    }
}
```

这样 `String` `NSURL` `NSURLComponents` 和 `NSURLRequest` 都可以调用 `URLString` 方法了. 我们也就可以**直接在方法的签名中使用 `URLStringConvertible` 类型**.

## End

到目前为止关于 Alamofire 这个框架就大致介绍完了, 框架的实现还是非常简洁和优雅的, 这篇 post 从开始写到现在也过去了好久, 写的也不是十分的详细具体. 如果你对这个框架的实现有兴趣, 那么看一看这个框架的源代码也未尝不可.

<iframe src="http://ghbtns.com/github-btn.html?user=draveness&type=follow&size=large" height="30" width="240" frameborder="0" scrolling="0" style="width:240px; height: 30px;" allowTransparency="true"></iframe>

Blog: [draveness.me](http://draveness.me)


