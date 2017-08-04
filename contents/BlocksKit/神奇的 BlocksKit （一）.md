# 神奇的 BlocksKit （一）

Blog: [Draveness](http://draveness.me)

<iframe src="http://ghbtns.com/github-btn.html?user=draveness&type=follow&size=large" height="30" width="240" frameborder="0" scrolling="0" style="width:240px; height: 30px;" allowTransparency="true"></iframe> 

**高能预警：本篇文章非常长，因为 BlocksKit 的实现还是比较复杂和有意的。这篇文章不是为了剖析 iOS 开发中的 block 的实现以及它是如何组成甚至使用的，如果你想通过这篇文章来了解 block 的实现，它并不能帮到你。**

Block 到底是什么？这可能是困扰很多 iOS 初学者的一个问题。如果你在 Google 上搜索类似的问题时，可以查找到几十万条结果，block 在 iOS 开发中有着非常重要的地位，而且它的作用也越来越重要。

****

## 概述

这篇文章仅对 [BlocksKit](https://github.com/zwaldowski/BlocksKit) v2.2.5 的源代码进行分析，从框架的内部理解下面的功能是如何实现的：

+ 为 `NSArray`、 `NSDictionary` 和 `NSSet` 等集合类型以及对应的可变集合类型 `NSMutableArray`、 `NSMutableDictionary` 和 `NSMutableSet` 添加 `bk_each:` 等方法完成对集合中元素的**快速遍历**
+ 使用 block 对 `NSObject` 对象 KVO
+ 为 `UIView` 对象添加 `bk_whenTapped:` 等方法快速添加手势
+ 使用 block 替换 `UIKit` 中的 `delegate` ，涉及到核心模块 `DynamicDelegate`。

BlocksKit 框架中包括但不仅限于上述的功能，这篇文章是对 *v2.2.5* 版本源代码的分析，其它版本的功能不会在本篇文章中具体讨论。

## 如何提供简洁的遍历方法

BlocksKit 实现的最简单的功能就是为集合类型添加方法遍历集合中的元素。

```objectivec
[@[@1,@2,@3] bk_each:^(id obj) {
    NSLog(@"%@"，obj);
}];
```

这段代码非常简单，我们可以使用 `enumerateObjectsUsingBlock:` 方法替代 `bk_each:` 方法：

```objectivec
[@[@1,@2,@3] enumerateObjectsUsingBlock:^(id obj，NSUInteger idx，BOOL *stop) {
    NSLog(@"%@"，obj);
}];

2016-03-05 16:02:57.295 Draveness[10725:453402] 1
2016-03-05 16:02:57.296 Draveness[10725:453402] 2
2016-03-05 16:02:57.297 Draveness[10725:453402] 3
```

这部分代码的实现也没什么难度：

```objectivec
- (void)bk_each:(void (^)(id obj))block
{
	NSParameterAssert(block != nil);

	[self enumerateObjectsUsingBlock:^(id obj，NSUInteger idx，BOOL *stop) {
		block(obj);
	}];
}
```

它在 block 执行前会判断传进来的 block 是否为空，然后就是调用遍历方法，把数组中的每一个 `obj` 传给 block。

BlocksKit 在这些集合类中所添加的一些方法在 Ruby、Haskell 等语言中也同样存在。如果你接触过上面的语言，理解这里方法的功能也就更容易了，不过这不是这篇文章关注的主要内容。

```objectivec
// NSArray+BlocksKit.h

- (void)bk_each:(void (^)(id obj))block;
- (void)bk_apply:(void (^)(id obj))block;
- (id)bk_match:(BOOL (^)(id obj))block;
- (NSArray *)bk_select:(BOOL (^)(id obj))block;
- (NSArray *)bk_reject:(BOOL (^)(id obj))block;
- (NSArray *)bk_map:(id (^)(id obj))block;
- (id)bk_reduce:(id)initial withBlock:(id (^)(id sum，id obj))block;
- (NSInteger)bk_reduceInteger:(NSInteger)initial withBlock:(NSInteger(^)(NSInteger result，id obj))block;
- (CGFloat)bk_reduceFloat:(CGFloat)inital withBlock:(CGFloat(^)(CGFloat result，id obj))block;
- (BOOL)bk_any:(BOOL (^)(id obj))block;
- (BOOL)bk_none:(BOOL (^)(id obj))block;
- (BOOL)bk_all:(BOOL (^)(id obj))block;
- (BOOL)bk_corresponds:(NSArray *)list withBlock:(BOOL (^)(id obj1，id obj2))block;
```

## NSObject 上的魔法

> `NSObject` 是 iOS 中的『上帝类』。

在 `NSObject` 上添加的方法几乎会添加到 Cocoa Touch 中的所有类上，关于 `NSObject` 的讨论和总共分为以下三部分进行：

1. AssociatedObject
2. BlockExecution
3. BlockObservation

### 添加 AssociatedObject

经常跟 runtime 打交道的人不可能不知道 [AssociatedObject](http://nshipster.cn/associated-objects/) ，当我们想要为一个已经存在的类添加属性时，就需要用到 AssociatedObject 为类添加属性，而  BlocksKit 提供了更简单的方法来实现，不需要新建一个分类。

```objectivec
NSObject *test = [[NSObject alloc] init];
[test bk_associateValue:@"Draveness" withKey:@"name"];
NSLog(@"%@"，[test bk_associatedValueForKey:@"name"]);

2016-03-05 16:02:25.761 Draveness[10699:452125] Draveness
```

这里我们使用了 `bk_associateValue:withKey:` 和 `bk_associatedValueForKey:` 两个方法设置和获取 `name` 对应的值 `Draveness`.

```objectivec
- (void)bk_associateValue:(id)value withKey:(const void *)key
{
	objc_setAssociatedObject(self，key，value，OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
```

这里的 `OBJC_ASSOCIATION_RETAIN_NONATOMIC` 表示当前属性为 `retain` `nonatomic` 的，还有其它的参数如下：

```objectivec
/**
 * Policies related to associative references.
 * These are options to objc_setAssociatedObject()
 */
typedef OBJC_ENUM(uintptr_t，objc_AssociationPolicy) {
    OBJC_ASSOCIATION_ASSIGN = 0，          /**< Specifies a weak reference to the associated object. */
    OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1，/**< Specifies a strong reference to the associated object. 
                                            *   The association is not made atomically. */
    OBJC_ASSOCIATION_COPY_NONATOMIC = 3，  /**< Specifies that the associated object is copied. 
                                            *   The association is not made atomically. */
    OBJC_ASSOCIATION_RETAIN = 01401，      /**< Specifies a strong reference to the associated object.
                                            *   The association is made atomically. */
    OBJC_ASSOCIATION_COPY = 01403          /**< Specifies that the associated object is copied.
                                            *   The association is made atomically. */
};
```

上面的这个 NS_ENUM 也没什么好说的，需要注意的是这里没有 `weak` 属性。

BlocksKit 通过另一种方式实现了『弱属性』：

```objectivec
- (void)bk_weaklyAssociateValue:(__autoreleasing id)value withKey:(const void *)key
{
	_BKWeakAssociatedObject *assoc = objc_getAssociatedObject(self，key);
	if (!assoc) {
		assoc = [_BKWeakAssociatedObject new];
		[self bk_associateValue:assoc withKey:key];
	}
	assoc.value = value;
}
```

在这里先获取了一个 `_BKWeakAssociatedObject` 对象 `assoc`，然后更新这个对象的属性 `value`。

因为直接使用 AssociatedObject 不能为对象添加弱属性，所以在这里添加了一个对象，然后让这个对象持有一个弱属性：

```objectivec
@interface _BKWeakAssociatedObject : NSObject

@property (nonatomic，weak) id value;

@end

@implementation _BKWeakAssociatedObject

@end
```

这就是 BlocksKit 实现弱属性的方法，我觉得这个实现的方法还是比较简洁的。

getter 方法的实现也非常类似：

```objectivec
- (id)bk_associatedValueForKey:(const void *)key
{
	id value = objc_getAssociatedObject(self，key);
	if (value && [value isKindOfClass:[_BKWeakAssociatedObject class]]) {
		return [(_BKWeakAssociatedObject *)value value];
	}
	return value;
}
```

### 在任意对象上执行 block

通过这个类提供的一些接口，可以在任意对象上快速执行线程安全、异步的 block，而且这些 block 也可以在执行之前取消。

```objectivec
- (id <NSObject，NSCopying>)bk_performOnQueue:(dispatch_queue_t)queue afterDelay:(NSTimeInterval)delay usingBlock:(void (^)(id obj))block
{
    NSParameterAssert(block != nil);
    
    return BKDispatchCancellableBlock(queue，delay，^{
        block(self);
    });
}
```

判断 block 是否为空在这里都是细枝末节，这个方法中最关键的也就是它返回了一个可以取消的 block，而这个 block 就是用静态函数 `BKDispatchCancellableBlock` 生成的。

```objectivec
static id <NSObject，NSCopying> BKDispatchCancellableBlock(dispatch_queue_t queue，NSTimeInterval delay，void(^block)(void)) {
    dispatch_time_t time = BKTimeDelay(delay);
    
#if DISPATCH_CANCELLATION_SUPPORTED
    if (BKSupportsDispatchCancellation()) {
        dispatch_block_t ret = dispatch_block_create(0，block);
        dispatch_after(time，queue，ret);
        return ret;
    }
#endif
    
    __block BOOL cancelled = NO;
    void (^wrapper)(BOOL) = ^(BOOL cancel) {
        if (cancel) {
            cancelled = YES;
            return;
        }
        if (!cancelled) block();
    };
    
    dispatch_after(time，queue，^{
        wrapper(NO);
    });
    
    return wrapper;
}
```

这个函数首先会执行 `BKSupportsDispatchCancellation` 来判断当前平台和版本是否支持使用 GCD 取消 block，当然一般都是支持的：

+ 函数返回的是 `YES`，那么在 block 被派发到指定队列之后就会返回这个 `dispatch_block_t` 类型的 block
+ 函数返回的是 `NO`，那么就会就会手动包装一个可以取消的 block，具体实现的部分如下：

```objectivec
__block BOOL cancelled = NO;
void (^wrapper)(BOOL) = ^(BOOL cancel) {
    if (cancel) {
        cancelled = YES;
        return;
    }
    if (!cancelled) block();
};
	
dispatch_after(time，queue，^{
    wrapper(NO);
});
	
return wrapper;
```

上面这部分代码就先创建一个 `wrapper` block，然后派发到指定队列，派发到指定队列的这个 block 是一定会执行的，但是怎么取消这个 block 呢？

如果当前 block 没有执行，我们在外面调用一次 `wrapper(YES)` 时，block 内部的 `cancelled` 变量就会被设置为 `YES`，所以 block 就不会执行。

1. `dispatch_after  --- cancelled = NO`
2. **`wrapper(YES) --- cancelled = YES`**
3. `wrapper(NO) --- cancelled = YES` block 不会执行

这是实现取消的关键部分：

```objectivec
+ (void)bk_cancelBlock:(id <NSObject，NSCopying>)block
{
    NSParameterAssert(block != nil);
    
#if DISPATCH_CANCELLATION_SUPPORTED
    if (BKSupportsDispatchCancellation()) {
        dispatch_block_cancel((dispatch_block_t)block);
        return;
    }
#endif
    
    void (^wrapper)(BOOL) = (void(^)(BOOL))block;
    wrapper(YES);
}
```

+ GCD 支持取消 block，那么直接调用 `dispatch_block_cancel` 函数取消 block
+ GCD 不支持取消 block 那么调用一次 `wrapper(YES)`


### 使用 Block 封装 KVO

BlocksKit 对 KVO 的封装由两部分组成：

1. `NSObject` 的分类负责提供便利方法
2. 私有类 `_BKObserver` 具体实现原生的 KVO 功能

#### 提供接口并在 `dealloc` 时停止 BlockObservation

`NSObject+BKBlockObservation` 这个分类中的大部分接口都会调用这个方法:

```objectivec
- (void)bk_addObserverForKeyPaths:(NSArray *)keyPaths identifier:(NSString *)identifier options:(NSKeyValueObservingOptions)options context:(BKObserverContext)context task:(id)task
{
	#1: 检查参数，省略
	
	#2: 使用神奇的方法在分类中覆写 dealloc

	NSMutableDictionary *dict;
	_BKObserver *observer = [[_BKObserver alloc] initWithObservee:self keyPaths:keyPaths context:context task:task];
	[observer startObservingWithOptions:options];
	
	#3: 惰性初始化 bk_observerBlocks 也就是下面的 dict，省略

	dict[identifier] = observer;
}
```

我们不会在这里讨论 `#1`、`#3` 部分，再详细阅读 `#2` 部分代码之前，先来看一下这个省略了绝大部分细节的核心方法。

使用传入方法的参数创建了一个 `_BKObserver` 对象，然后调用 `startObservingWithOptions:` 方法开始 KVO 观测相应的属性，然后以 `{identifier，obeserver}` 的形式存到字典中保存。

这里实在没什么新意，我们在下一小节中会介绍 `startObservingWithOptions:` 这一方法。

#### 在分类中调剂 dealloc 方法

这个问题我觉得是非常值得讨论的一个问题，也是我最近在写框架时遇到很棘手的一个问题。

> 当我们在分类中注册一些通知或者使用 KVO 时，很有可能会找不到注销这些通知的时机。

因为在**分类中是无法直接实现 `dealloc` 方法的**。 在 iOS8 以及之前的版本，如果某个对象被释放了，但是刚对象的注册的通知没有被移除，那么当事件再次发生，就会*向已经释放的对象发出通知*，整个程序就会崩溃。

这里解决的办法就十分的巧妙:

```objectivec
Class classToSwizzle = self.class;
// 获取所有修改过 dealloc 方法的类
NSMutableSet *classes = self.class.bk_observedClassesHash;

// 保证互斥避免 classes 出现难以预测的结果
@synchronized (classes) {

   // 获取当前类名，并判断是否修改过 dealloc 方法以减少这部分代码的调用次数
   NSString *className = NSStringFromClass(classToSwizzle);
   if (![classes containsObject:className]) {
       // 这里的 sel_registerName 方法会返回 dealloc 的 selector，因为 dealloc 已经注册过
       SEL deallocSelector = sel_registerName("dealloc");
       
		__block void (*originalDealloc)(__unsafe_unretained id，SEL) = NULL;

       // 实现新的 dealloc 方法
		id newDealloc = ^(__unsafe_unretained id objSelf) {
           //在方法 dealloc 之前移除所有 observer
           [objSelf bk_removeAllBlockObservers];
           
           if (originalDealloc == NULL) {
               // 如果原有的 dealloc 方法没有被找到就会查找父类的 dealloc 方法，调用父类的 dealloc 方法
               struct objc_super superInfo = {
                   .receiver = objSelf,
                   .super_class = class_getSuperclass(classToSwizzle)
               };
               
               void (*msgSend)(struct objc_super *，SEL) = (__typeof__(msgSend))objc_msgSendSuper;
               msgSend(&superInfo，deallocSelector);
           } else {
               // 如果 dealloc 方法被找到就会直接调用该方法，并传入参数
               originalDealloc(objSelf，deallocSelector);
           }
       };

       // 构建选择子实现 IMP
       IMP newDeallocIMP = imp_implementationWithBlock(newDealloc);

       // 向当前类添加方法，但是多半不会成功，因为类已经有 dealloc 方法
       if (!class_addMethod(classToSwizzle，deallocSelector，newDeallocIMP，"v@:")) {
           // 获取原有 dealloc 实例方法
           Method deallocMethod = class_getInstanceMethod(classToSwizzle，deallocSelector);
           
           // 存储 dealloc 方法实现防止在 set 的过程中调用该方法
           originalDealloc = (void(*)(__unsafe_unretained id，SEL))method_getImplementation(deallocMethod);
           
           // 重新设置 dealloc 方法的实现，并存储到 originalDealloc 防止方法实现改变
           originalDealloc = (void(*)(__unsafe_unretained id，SEL))method_setImplementation(deallocMethod，newDeallocIMP);
       }

       // 将当前类名添加到已经改变的类的集合中
       [classes addObject:className];
   }
}
```

这部分代码的执行顺序如下:

1. 首先调用 `bk_observedClassesHash` 类方法获取所有修改过 `dealloc` 方法的类的集合 `classes`
2. 使用 `@synchronized (classes)` 保证互斥，避免同时修改 `classes` 集合的类过多出现意料之外的结果
3. 判断即将调剂方法的类 `classToSwizzle` 是否调剂过 `dealloc` 方法
4. 如果 `dealloc` 方法没有调剂过，就会通过 `sel_registerName("dealloc")` 方法获取选择子，这行代码并不会真正注册 `dealloc` 选择子而是会获取 `dealloc` 的选择子，具体原因可以看这个方法的实现 [sel_registerName](https://developer.apple.com/library/prerelease/ios/documentation/Cocoa/Reference/ObjCRuntimeRef/index.html#//apple_ref/c/func/sel_registerName)
5. 在新的 `dealloc` 中**添加移除 Observer 的方法**， 再调用原有的 `dealloc`


	    id newDealloc = ^(__unsafe_unretained id objSelf) {
	    	[objSelf bk_removeAllBlockObservers];
      
		   if (originalDealloc == NULL) {
		    	struct objc_super superInfo = {
		     		.receiver = objSelf,
		    		.super_class = class_getSuperclass(classToSwizzle)
		    	};
			    void (*msgSend)(struct objc_super *，SEL) = (__typeof__(msgSend))objc_msgSendSuper;
			    msgSend(&superInfo，deallocSelector);
		    } else {
			    originalDealloc(objSelf，deallocSelector);
		    }
	    };
	    IMP newDeallocIMP = imp_implementationWithBlock(newDealloc);

	
	1. 调用 `bk_removeAllBlockObservers` 方法移除所有观察者，也就是这段代码的最终目的
	2. 根据 `originalDealloc` 是否为空，决定是向父类发送消息，还是直接调用 `originalDealloc` 并传入 `objSelf，deallocSelector` 作为参数

6. 在我们获得了新 `dealloc` 方法的选择子和 `IMP` 时，就要改变原有的 `dealloc` 的实现了

	    if (!class_addMethod(classToSwizzle，deallocSelector，newDeallocIMP，"v@:")) {
	        // The class already contains a method implementation.
	        Method deallocMethod = class_getInstanceMethod(classToSwizzle，deallocSelector);

	       // We need to store original implementation before setting new implementation
	        // in case method is called at the time of setting.
	        originalDealloc = (void(*)(__unsafe_unretained id，SEL))method_getImplementation(deallocMethod);
	    
	       // We need to store original implementation again，in case it just changed.
	        originalDealloc = (void(*)(__unsafe_unretained id，SEL))method_setImplementation(deallocMethod，newDeallocIMP);
	    }

	1. 调用 `class_addMethod` 方法为当前类添加选择子为 `dealloc` 的方法（当然 99.99% 的可能不会成功）
	2. 获取原有的 `dealloc` 实例方法
	3. 将原有的实现保存到 `originalDealloc` 中，防止使用 `method_setImplementation` 重新设置该方法的过程中调用 `dealloc` 导致无方法可用
	4. 重新设置 `dealloc` 方法的实现。同样，将实现存储到 `originalDealloc` 中防止实现改变

关于在分类中调剂 `dealloc` 方法的这部分到这里就结束了，下一节将继续分析私有类 `_BKObserver`。

#### 私有类 `_BKObserver`

`_BKObserver` 是用来观测属性的对象，它在接口中定义了 4 个属性：

```objectivec
@property (nonatomic，readonly，unsafe_unretained) id observee;
@property (nonatomic，readonly) NSMutableArray *keyPaths;
@property (nonatomic，readonly) id task;
@property (nonatomic，readonly) BKObserverContext context;
```

上面四个属性的具体作用在这里不说了，上面的 `bk_addObserverForKeyPaths:identifier:options:context:` 方法中调用 `_BKObserver` 的初始化方法 `initWithObservee:keyPaths:context:task:` 太简单了也不说了。

```objectivec
_BKObserver *observer = [[_BKObserver alloc] initWithObservee:self keyPaths:keyPaths context:context task:task];
[observer startObservingWithOptions:options];
```

上面的第一行代码生成一个 `observer` 实例之后立刻调用了 `startObservingWithOptions:` 方法开始观测对应的 `keyPath`：

```objectivec
- (void)startObservingWithOptions:(NSKeyValueObservingOptions)options
{
	@synchronized(self) {
		if (_isObserving) return;
		
		#1：遍历 keyPaths 实现 KVO

		_isObserving = YES;
	}
}
```

`startObservingWithOptions:` 方法最重要的就是第 `#1` 部分：

```objectivec
[self.keyPaths bk_each:^(NSString *keyPath) {
	[self.observee addObserver:self forKeyPath:keyPath options:options context:BKBlockObservationContext];
}];
```

遍历自己的 `keyPaths` 然后让 `_BKObserver` 作观察者观察自己，然后传入对应的 `keyPath`。

关于 `_stopObservingLocked` 方法的实现也十分的相似，这里就不说了。

```objectivec
[keyPaths bk_each:^(NSString *keyPath) {
	[observee removeObserver:self forKeyPath:keyPath context:BKBlockObservationContext];
}];
```

到目前为止，我们还没有看到实现 KVO 所必须的方法 `observeValueForKeyPath:ofObject:change:context`，这个方法就是每次属性改变之后的回调：

```objectivec
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context != BKBlockObservationContext) return;

	@synchronized(self) {
		switch (self.context) {
			case BKObserverContextKey: {
				void (^task)(id) = self.task;
				task(object);
				break;
			}
			case BKObserverContextKeyWithChange: {
				void (^task)(id，NSDictionary *) = self.task;
				task(object，change);
				break;
			}
			case BKObserverContextManyKeys: {
				void (^task)(id，NSString *) = self.task;
				task(object，keyPath);
				break;
			}
			case BKObserverContextManyKeysWithChange: {
				void (^task)(id，NSString *，NSDictionary *) = self.task;
				task(object，keyPath，change);
				break;
			}
		}
	}
}
```

这个方法的实现也很简单，根据传入的 `context` 值，对 `task` 类型转换，并传入具体的值。

这个模块倒着就介绍完了，在下一节会介绍 BlocksKit 对 UIKit 组件一些简单的改造。

## 改造 UIKit

在这个小结会具体介绍 BlocksKit 是如何对一些简单的控件进行改造的，本节大约有两部分内容：

+ UIGestureRecongizer + UIBarButtonItem + UIControl
+ UIView

### 改造 UIGestureRecongizer，UIBarButtonItem 和 UIControl

先来看一个 `UITapGestureRecognizer` 使用的例子

```objectivec
 UITapGestureRecognizer *singleTap = [UITapGestureRecognizer bk_recognizerWithHandler:^(id sender) {
     NSLog(@"Single tap.");
 } delay:0.18];
 [self addGestureRecognizer:singleTap];
```

代码中的 `bk_recognizerWithHandler:delay:` 方法在最后都会调用初始化方法 `bk_initWithHandler:delay:` 生成一个 `UIGestureRecongizer` 的实例

```objectivec
- (instancetype)bk_initWithHandler:(void (^)(UIGestureRecognizer *sender，UIGestureRecognizerState state，CGPoint location))block delay:(NSTimeInterval)delay
{
	self = [self initWithTarget:self action:@selector(bk_handleAction:)];
	if (!self) return nil;

	self.bk_handler = block;
	self.bk_handlerDelay = delay;

	return self;
}
```

它会在这个方法中传入 `target` 和 `selector`。 其中 `target` 就是 `self`，而 `selector` 也会在这个分类中实现：

```objectivec
- (void)bk_handleAction:(UIGestureRecognizer *)recognizer
{
	void (^handler)(UIGestureRecognizer *sender，UIGestureRecognizerState state，CGPoint location) = recognizer.bk_handler;
	if (!handler) return;
	
	NSTimeInterval delay = self.bk_handlerDelay;
	
	#1: 封装 block 并控制 block 是否可以执行

	self.bk_shouldHandleAction = YES;

    [NSObject bk_performAfterDelay:delay usingBlock:block];
}
```

因为在初始化方法 `bk_initWithHandler:delay:` 中保存了当前手势的 `bk_handler`，所以直接调用在 Block Execution 一节中提到过的 `bk_performAfterDelay:usingBlock:` 方法，将 block 派发到指定的队列中，最终完成对 block 的调用。

#### 封装 block 并控制 block 是否可以执行

这部分代码和前面的部分有些相似，因为这里也用到了一个属性 `bk_shouldHandleAction` 来控制 block 是否会被执行：

```objectivec
CGPoint location = [self locationInView:self.view];
void (^block)(void) = ^{
	if (!self.bk_shouldHandleAction) return;
	handler(self，self.state，location);
};
```

====

同样 `UIBarButtonItem` 和 `UIControl` 也是用了几乎相同的机制，把 `target` 设置为 `self`，让后在分类的方法中调用指定的 block。

#### UIControlWrapper

稍微有些不同的是 `UIControl`。因为 `UIControl` 有多种 `UIControlEvents`，所以使用另一个类 `BKControlWrapper` 来封装 `handler` 和 `controlEvents`

```objectivec
@property (nonatomic) UIControlEvents controlEvents;
@property (nonatomic，copy) void (^handler)(id sender);
```

其中 `UIControlWrapper` 对象以 `{controlEvents，wrapper}` 的形式作为 `UIControl` 的属性存入字典。

### 改造 UIView

因为在上面已经改造过了 `UIGestureRecognizer`，在这里改造 `UIView` 就变得很容易了：

```objectivec
- (void)bk_whenTouches:(NSUInteger)numberOfTouches tapped:(NSUInteger)numberOfTaps handler:(void (^)(void))block
{
	if (!block) return;
	
	UITapGestureRecognizer *gesture = [UITapGestureRecognizer bk_recognizerWithHandler:^(UIGestureRecognizer *sender，UIGestureRecognizerState state，CGPoint location) {
		if (state == UIGestureRecognizerStateRecognized) block();
	}];
	
	gesture.numberOfTouchesRequired = numberOfTouches;
	gesture.numberOfTapsRequired = numberOfTaps;

	[self.gestureRecognizers enumerateObjectsUsingBlock:^(id obj，NSUInteger idx，BOOL *stop) {
		if (![obj isKindOfClass:[UITapGestureRecognizer class]]) return;

		UITapGestureRecognizer *tap = obj;
		BOOL rightTouches = (tap.numberOfTouchesRequired == numberOfTouches);
		BOOL rightTaps = (tap.numberOfTapsRequired == numberOfTaps);
		if (rightTouches && rightTaps) {
			[gesture requireGestureRecognizerToFail:tap];
		}
	}];

	[self addGestureRecognizer:gesture];
}
```

`UIView` 分类只有这一个核心方法，其它的方法都是向这个方法传入不同的参数，这里需要注意的就是。它会遍历所有的 `gestureRecognizers`，然后把对所有有冲突的手势调用 `requireGestureRecognizerToFail:` 方法，保证添加的手势能够正常的执行。

由于这篇文章中的内容较多，所以内容分成了两个部分，下一部分介绍的是 BlocksKit 中的最重要的部分动态代理：

+ [神奇的 BlocksKit（一）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/BlocksKit/神奇的%20BlocksKit%20（一）.md)
+ [神奇的 BlocksKit（二）](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/BlocksKit/神奇的%20BlocksKit%20（二）.md)

<iframe src="http://ghbtns.com/github-btn.html?user=draveness&type=follow&size=large" height="30" width="240" frameborder="0" scrolling="0" style="width:240px; height: 30px;" allowTransparency="true"></iframe>

Follow: [@Draveness](https://github.com/Draveness)


