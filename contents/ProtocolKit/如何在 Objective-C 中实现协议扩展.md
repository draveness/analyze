# 如何在 Objective-C 中实现协议扩展

![protocol-recordings](images/protocol-recordings.jpeg)

Swift 中的协议扩展为 iOS 开发带来了非常多的可能性，它为我们提供了一种类似多重继承的功能，帮助我们减少一切可能导致重复代码的地方。

## 关于 Protocol Extension

在 Swift 中比较出名的 Then 就是使用了协议扩展为所有的 `AnyObject` 添加方法，而且不需要调用 runtime 相关的 API，其实现简直是我见过最简单的开源框架之一：

```swift
public protocol Then {}

extension Then where Self: AnyObject {
	public func then(@noescape block: Self -> Void) -> Self {
		block(self)
		return self
	}
}

extension NSObject: Then {}
```

只有这么几行代码，就能为所有的 `NSObject` 添加下面的功能：

```swift
let titleLabel = UILabel().then {
	$0.textColor = .blackColor()
	$0.textAlignment = .Center
}
```

这里没有调用任何的 runtime 相关 API，也没有在 `NSObject` 中进行任何的方法声明，甚至 `protocol Then {}` 协议本身都只有一个大括号，整个 Then 框架就是基于协议扩展来实现的。

在 Objective-C 中同样有协议，但是这些协议只是相当于接口，遵循某个协议的类只表明实现了这些接口，每个类都需要**对这些接口有单独的实现**，这就很可能会导致重复代码的产生。

而协议扩展可以调用协议中声明的方法，以及 `where Self: AnyObject` 中的 `AnyObject` 的类/实例方法，这就大大提高了可操作性，便于开发者写出一些意想不到的扩展。

> 如果读者对 Protocol Extension 兴趣或者不了解协议扩展，可以阅读最后的 [Reference](#reference) 了解相关内容。

## ProtocolKit

其实协议扩展的强大之处就在于它能为遵循协议的类添加一些方法的实现，而不只是一些接口，而今天为各位读者介绍的 [ProtocolKit]([https://github.com/forkingdog/ProtocolKit]) 就实现了这一功能，为遵循协议的类添加方法。

### ProtocolKit 的使用

我们先来看一下如何使用 ProtocolKit，首先定义一个协议：

```objectivec
@protocol TestProtocol

@required

- (void)fizz;

@optional

- (void)buzz;

@end
```

在协议中定义了两个方法，必须实现的方法 `fizz` 以及可选实现 `buzz`，然后使用 ProtocolKit 提供的接口 `defs` 来定义协议中方法的实现了：

```objectivec
@defs(TestProtocol)

- (void)buzz {
	NSLog(@"Buzz");
}

@end
```

这样所有遵循 `TestProtocol` 协议的对象都可以调用 `buzz` 方法，哪怕它们没有实现：

![protocol-demo](images/protocol-demo.jpeg)

上面的 `XXObject` 虽然没有实现 `buzz` 方法，但是该方法仍然成功执行了。

### ProtocolKit 的实现

ProtocolKit 的主要原理仍然是 runtime 以及宏的；通过宏的使用来**隐藏类的声明以及实现的代码**，然后在 main 函数运行之前，**将类中的方法实现加载到内存**，使用 runtime 将实现**注入到目标类**中。

> 如果你对上面的原理有所疑惑也不是太大的问题，这里只是给你一个 ProtocolKit 原理的简单描述，让你了解它是如何工作的。

ProtocolKit 中有两条重要的执行路线：

+ `_pk_extension_load` 将协议扩展中的方法实现加载到了内存
+ `_pk_extension_inject_entry` 负责将扩展协议注入到实现协议的类

#### 加载实现

首先要解决的问题是如何将方法实现加载到内存中，这里可以先了解一下上面使用到的 `defs` 接口，它其实只是一个调用了其它宏的**超级宏**~~这名字是我编的~~：

```objectivec
#define defs _pk_extension

#define _pk_extension($protocol) _pk_extension_imp($protocol, _pk_get_container_class($protocol))

#define _pk_extension_imp($protocol, $container_class) \
	protocol $protocol; \
	@interface $container_class : NSObject <$protocol> @end \
	@implementation $container_class \
	+ (void)load { \
		_pk_extension_load(@protocol($protocol), $container_class.class); \
	} \

#define _pk_get_container_class($protocol) _pk_get_container_class_imp($protocol, __COUNTER__)
#define _pk_get_container_class_imp($protocol, $counter) _pk_get_container_class_imp_concat(__PKContainer_, $protocol, $counter)
#define _pk_get_container_class_imp_concat($a, $b, $c) $a ## $b ## _ ## $c
```

> 使用 `defs` 作为接口的是因为它是一个保留的 keyword，Xcode 会将它渲染成与 `@property` 等其他关键字相同的颜色。

上面的这一坨宏并不需要一个一个来分析，只需要看一下最后展开会变成什么：

```objectivec
@protocol TestProtocol; 

@interface __PKContainer_TestProtocol_0 : NSObject <TestProtocol>

@end

@implementation __PKContainer_TestProtocol_0

+ (void)load {
	_pk_extension_load(@protocol(TestProtocol), __PKContainer_TestProtocol_0.class); 
}
```

根据上面宏的展开结果，这里可以介绍上面的一坨宏的作用：

+ `defs` 这货没什么好说的，只是 `_pk_extension` 的别名，为了提供一个更加合适的名字作为接口
+ `_pk_extension` 向 `_pk_extension_imp ` 中传入 `$protocol` 和 `_pk_get_container_class($protocol)` 参数
	+ `_pk_get_container_class` 的执行生成一个类名，上面生成的类名就是 `__PKContainer_TestProtocol_0`，这个类名是 `__PKContainer_`、 `$protocol` 和 `__COUNTER__` 拼接而成的（`__COUNTER__` 只是一个计数器，可以理解为每次调用时加一）
+ `_pk_extension_imp` 会以传入的类名生成一个遵循当前 `$protocol` 协议的类，然后在 `+ load` 方法中执行 `_pk_extension_load` 加载扩展协议

通过宏的运用成功隐藏了 `__PKContainer_TestProtocol_0` 类的声明以及实现，还有 `_pk_extension_load` 函数的调用：

```objectivec
void _pk_extension_load(Protocol *protocol, Class containerClass) {
	
	pthread_mutex_lock(&protocolsLoadingLock);
	
	if (extendedProtcolCount >= extendedProtcolCapacity) {
		size_t newCapacity = 0;
		if (extendedProtcolCapacity == 0) {
			newCapacity = 1;
		} else {
			newCapacity = extendedProtcolCapacity << 1;
		}
		allExtendedProtocols = realloc(allExtendedProtocols, sizeof(*allExtendedProtocols) * newCapacity);
		extendedProtcolCapacity = newCapacity;
	}
	
	...

	pthread_mutex_unlock(&protocolsLoadingLock);
}
```

ProtocolKit 使用了 `protocolsLoadingLock` 来保证静态变量 `allExtendedProtocols` 以及 `extendedProtcolCount` `extendedProtcolCapacity` 不会因为线程竞争导致问题：

+ `allExtendedProtocols` 用于保存所有的 `PKExtendedProtocol` 结构体
+ 后面的两个变量确保数组不会越界，并在数组满的时候，将内存占用地址翻倍

方法的后半部分会在静态变量中寻找或创建传入的 `protocol` 对应的 `PKExtendedProtocol` 结构体：

```objectivec
size_t resultIndex = SIZE_T_MAX;
for (size_t index = 0; index < extendedProtcolCount; ++index) {
	if (allExtendedProtocols[index].protocol == protocol) {
		resultIndex = index;
		break;
	}
}

if (resultIndex == SIZE_T_MAX) {
	allExtendedProtocols[extendedProtcolCount] = (PKExtendedProtocol){
		.protocol = protocol,
		.instanceMethods = NULL,
		.instanceMethodCount = 0,
		.classMethods = NULL,
		.classMethodCount = 0,
	};
	resultIndex = extendedProtcolCount;
	extendedProtcolCount++;
}

_pk_extension_merge(&(allExtendedProtocols[resultIndex]), containerClass);
```

这里调用的 `_pk_extension_merge` 方法非常重要，不过在介绍 `_pk_extension_merge` 之前，首先要了解一个用于保存协议扩展信息的私有结构体 `PKExtendedProtocol`：

```objectivec
typedef struct {
	Protocol *__unsafe_unretained protocol;
	Method *instanceMethods;
	unsigned instanceMethodCount;
	Method *classMethods;
	unsigned classMethodCount;
} PKExtendedProtocol;
```

`PKExtendedProtocol` 结构体中保存了协议的指针、实例方法、类方法、实例方法数以及类方法数用于框架记录协议扩展的状态。

回到 `_pk_extension_merge` 方法，它会将新的扩展方法追加到 `PKExtendedProtocol` 结构体的数组 `instanceMethods` 以及 `classMethods` 中：

```objectivec
void _pk_extension_merge(PKExtendedProtocol *extendedProtocol, Class containerClass) {
	// Instance methods
	unsigned appendingInstanceMethodCount = 0;
	Method *appendingInstanceMethods = class_copyMethodList(containerClass, &appendingInstanceMethodCount);
	Method *mergedInstanceMethods = _pk_extension_create_merged(extendedProtocol->instanceMethods,
																extendedProtocol->instanceMethodCount,
																appendingInstanceMethods,
																appendingInstanceMethodCount);
	free(extendedProtocol->instanceMethods);
	extendedProtocol->instanceMethods = mergedInstanceMethods;
	extendedProtocol->instanceMethodCount += appendingInstanceMethodCount;
	
	// Class methods
	...
}
```

> 因为类方法的追加与实例方法几乎完全相同，所以上述代码省略了向结构体中的类方法追加方法的实现代码。

实现中使用 `class_copyMethodList` 从 `containerClass` 拉出方法列表以及方法数量；通过 `_pk_extension_create_merged` 返回一个合并之后的方法列表，最后在更新结构体中的 `instanceMethods` 以及 `instanceMethodCount` 成员变量。

`_pk_extension_create_merged` 只是重新 `malloc` 一块内存地址，然后使用 `memcpy` 将所有的方法都复制到了这块内存地址中，最后返回首地址：

```objectivec
Method *_pk_extension_create_merged(Method *existMethods, unsigned existMethodCount, Method *appendingMethods, unsigned appendingMethodCount) {
	
	if (existMethodCount == 0) {
		return appendingMethods;
	}
	unsigned mergedMethodCount = existMethodCount + appendingMethodCount;
	Method *mergedMethods = malloc(mergedMethodCount * sizeof(Method));
	memcpy(mergedMethods, existMethods, existMethodCount * sizeof(Method));
	memcpy(mergedMethods + existMethodCount, appendingMethods, appendingMethodCount * sizeof(Method));
	return mergedMethods;
}
```

这一节的代码从使用宏生成的类中抽取方法实现，然后以结构体的形式加载到内存中，等待之后的方法注入。

#### 注入方法实现

注入方法的时间点在 main 函数执行之前议实现的注入并不是在 `+ load` 方法 `+ initialize` 方法调用时进行的，而是使用的编译器指令(compiler directive) `__attribute__((constructor))` 实现的：

```objectivec
__attribute__((constructor)) static void _pk_extension_inject_entry(void);
```

使用上述编译器指令的函数会在 shared library 加载的时候执行，也就是 main 函数之前，可以看 StackOverflow 上的这个问题 [How exactly does __attribute__((constructor)) work?](http://stackoverflow.com/questions/2053029/how-exactly-does-attribute-constructor-work)。

```objectivec
__attribute__((constructor)) static void _pk_extension_inject_entry(void) {
	#1：加锁
	unsigned classCount = 0;
	Class *allClasses = objc_copyClassList(&classCount);
	
	@autoreleasepool {
		for (unsigned protocolIndex = 0; protocolIndex < extendedProtcolCount; ++protocolIndex) {
			PKExtendedProtocol extendedProtcol = allExtendedProtocols[protocolIndex];
			for (unsigned classIndex = 0; classIndex < classCount; ++classIndex) {
				Class class = allClasses[classIndex];
				if (!class_conformsToProtocol(class, extendedProtcol.protocol)) {
					continue;
				}
				_pk_extension_inject_class(class, extendedProtcol);
			}
		}
	}
	#2：解锁并释放 allClasses、allExtendedProtocols
}
```

`_pk_extension_inject_entry` 会在 main 执行之前遍历内存中的**所有** `Class`（整个遍历过程都是在一个自动释放池中进行的），如果某个类遵循了`allExtendedProtocols` 中的协议，调用 `_pk_extension_inject_class` 向类中注射（inject）方法实现：

```objectivec
static void _pk_extension_inject_class(Class targetClass, PKExtendedProtocol extendedProtocol) {
	
	for (unsigned methodIndex = 0; methodIndex < extendedProtocol.instanceMethodCount; ++methodIndex) {
		Method method = extendedProtocol.instanceMethods[methodIndex];
		SEL selector = method_getName(method);
		
		if (class_getInstanceMethod(targetClass, selector)) {
			continue;
		}
		
		IMP imp = method_getImplementation(method);
		const char *types = method_getTypeEncoding(method);
		class_addMethod(targetClass, selector, imp, types);
	}
	
	#1: 注射类方法
}
```

如果类中没有实现该实例方法就会通过 runtime 中的 `class_addMethod` 注射该实例方法；而类方法的注射有些不同，因为类方法都是保存在元类中的，而一些类方法由于其特殊地位最好不要改变其原有实现，比如 `+ load` 和 `+ initialize` 这两个类方法就比较特殊，如果想要了解这两个方法的相关信息，可以在 [Reference](#reference) 中查看相关的信息。

```objectivec
Class targetMetaClass = object_getClass(targetClass);
for (unsigned methodIndex = 0; methodIndex < extendedProtocol.classMethodCount; ++methodIndex) {
	Method method = extendedProtocol.classMethods[methodIndex];
	SEL selector = method_getName(method);
	
	if (selector == @selector(load) || selector == @selector(initialize)) {
		continue;
	}
	if (class_getInstanceMethod(targetMetaClass, selector)) {
		continue;
	}
	
	IMP imp = method_getImplementation(method);
	const char *types = method_getTypeEncoding(method);
	class_addMethod(targetMetaClass, selector, imp, types);
}
```

实现上的不同仅仅在获取元类、以及跳过 `+ load` 和 `+ initialize` 方法上。

## 总结

ProtocolKit 通过宏和 runtime 实现了类似协议扩展的功能，其实现代码总共也只有 200 多行，还是非常简洁的；在另一个叫做 [libextobjc](https://github.com/jspahrsummers/libextobjc) 的框架中也实现了类似的功能，有兴趣的读者可以查看 [EXTConcreteProtocol.h · libextobjc]([https://github.com/jspahrsummers/libextobjc/blob/master/contents/extobjc/EXTConcreteProtocol.h]) 这个文件。

## Reference

+ [Protocols · Apple Doc](https://developer.apple.com/library/ios/documentation/Swift/Conceptual/Swift\_Programming\_Language/Extensions.html#//apple\_ref/doc/uid/TP40014097-CH24-ID151)
+ [EXTConcreteProtocol.h · libextobjc](https://github.com/jspahrsummers/libextobjc/blob/master/contents/extobjc/EXTConcreteProtocol.h)
+ [\_\_attribute__ · NSHipster](http://nshipster.com/__attribute__/)
+ [你真的了解 load 方法么？](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/objc/你真的了解%20load%20方法么？.md)
+ [懒惰的 initialize 方法](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/objc/懒惰的%20initialize%20方法.md)


