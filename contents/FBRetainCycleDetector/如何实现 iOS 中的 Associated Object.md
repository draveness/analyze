# 如何实现 iOS 中的 Associated Object

这一篇文章是对 [FBRetainCycleDetector]([https://github.com/facebook/FBRetainCycleDetector]) 中实现的关联对象机制的分析；因为追踪的需要， FBRetainCycleDetector 重新实现了关联对象，本文主要就是对其实现关联对象的方法进行分析。

文章中涉及的类主要就是 `FBAssociationManager`：

> FBAssociationManager is a tracker of object associations. For given object it can return all objects that are being retained by this object with objc_setAssociatedObject & retain policy.

FBRetainCycleDetector 在对关联对象进行追踪时，修改了底层处理关联对象的两个 C 函数，`objc_setAssociatedObject` 和 `objc_removeAssociatedObjects`，在这里不会分析它是如何修改底层 C 语言函数实现的，如果想要了解相关的内容，可以阅读下面的文章。

> 关于如何动态修改 C 语言函数实现可以看[动态修改 C 语言函数的实现]([https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/fishhook/动态修改%20C%20语言函数的实现.md])这篇文章，使用的第三方框架是 [fishhook]([https://github.com/facebook/fishhook])。

## FBAssociationManager

在 `FBAssociationManager` 的类方法 `+ hook` 调用时，fishhook 会修改 `objc_setAssociatedObject` 和 `objc_removeAssociatedObjects` 方法：

```objectivec
+ (void)hook {
#if _INTERNAL_RCD_ENABLED
	std::lock_guard<std::mutex> l(*FB::AssociationManager::hookMutex);
	rcd_rebind_symbols((struct rcd_rebinding[2]){
		{
			"objc_setAssociatedObject",
			(void *)FB::AssociationManager::fb_objc_setAssociatedObject,
			(void **)&FB::AssociationManager::fb_orig_objc_setAssociatedObject
		},
		{
			"objc_removeAssociatedObjects",
			(void *)FB::AssociationManager::fb_objc_removeAssociatedObjects,
			(void **)&FB::AssociationManager::fb_orig_objc_removeAssociatedObjects
		}}, 2);
	FB::AssociationManager::hookTaken = true;
#endif //_INTERNAL_RCD_ENABLED
}
```

将它们的实现替换为 `FB::AssociationManager:: fb_objc_setAssociatedObject` 以及 `FB::AssociationManager::fb_objc_removeAssociatedObjects` 这两个 Cpp 静态方法。

上面的两个方法实现都位于 `FB::AssociationManager` 的命名空间中：

```objectivec
namespace FB { namespace AssociationManager {
	using ObjectAssociationSet = std::unordered_set<void *>;
	using AssociationMap = std::unordered_map<id, ObjectAssociationSet *>;
	
	static auto _associationMap = new AssociationMap();
	static auto _associationMutex = new std::mutex;
	
	static std::mutex *hookMutex(new std::mutex);
	static bool hookTaken = false;

	...
}
```

命名空间中有两个用于存储关联对象的数据结构：

+ `AssociationMap` 用于存储从对象到 `ObjectAssociationSet *` 指针的映射
+ `ObjectAssociationSet` 用于存储某对象所有关联对象的集合

其中还有几个比较重要的成员变量：

+ `_associationMap` 就是 `AssociationMap` 的实例，是一个用于存储所有关联对象的数据结构
+ `_associationMutex` 用于在修改关联对象时加锁，防止出现线程竞争等问题，导致不可预知的情况发生
+ `hookMutex` 以及 `hookTaken` 都是在类方法 `+ hook` 调用时使用的，用于保证 hook 只会执行一次并保证线程安全

用于追踪关联对象的静态方法 `fb_objc_setAssociatedObject` 只会追踪强引用：

```objectivec
static void fb_objc_setAssociatedObject(id object, void *key, id value, objc_AssociationPolicy policy) {
	{
		std::lock_guard<std::mutex> l(*_associationMutex);
		if (policy == OBJC_ASSOCIATION_RETAIN ||
			policy == OBJC_ASSOCIATION_RETAIN_NONATOMIC) {
			_threadUnsafeSetStrongAssociation(object, key, value);
		} else {
			// We can change the policy, we need to clear out the key
			_threadUnsafeResetAssociationAtKey(object, key);
		}
	}
	
	fb_orig_objc_setAssociatedObject(object, key, value, policy);
}
```

`std::lock_guard<std::mutex> l(*_associationMutex)` 对 `fb_objc_setAssociatedObject` 过程加锁，防止死锁问题，不过 `_associationMutex` 会在作用域之外被释放。

通过输入的 `policy` 我们可以判断哪些是强引用对象，然后调用 `_threadUnsafeSetStrongAssociation` 追踪它们，如果不是强引用对象，通过 `_threadUnsafeResetAssociationAtKey` 将 `key` 对应的 `value` 删除，保证追踪的正确性：

```objectivec
void _threadUnsafeSetStrongAssociation(id object, void *key, id value) {
	if (value) {
		auto i = _associationMap->find(object);
		ObjectAssociationSet *refs;
		if (i != _associationMap->end()) {
			refs = i->second;
		} else {
			refs = new ObjectAssociationSet;
			(*_associationMap)[object] = refs;
		}
		refs->insert(key);
	} else {
		_threadUnsafeResetAssociationAtKey(object, key);
	}
}
```

`_threadUnsafeSetStrongAssociation` 会以 object 作为键，查找或者创建一个 `ObjectAssociationSet *` 集合，将新的 `key` 插入到集合中，当然，如果 `value == nil` 或者上面 `fb_objc_setAssociatedObject` 方法中传入的 `policy` 是非 `retain` 的就会调用 `_threadUnsafeResetAssociationAtKey ` 重置 `ObjectAssociationSet` 中的关联对象：

```objectivec
void _threadUnsafeResetAssociationAtKey(id object, void *key) {
	auto i = _associationMap->find(object);
	
	if (i == _associationMap->end()) {
		return;
	}
	
	auto *refs = i->second;
	auto j = refs->find(key);
	if (j != refs->end()) {
		refs->erase(j);
	}
}
```

同样在查找到对应的 `ObjectAssociationSet` 之后会擦除 `key` 对应的值，`_threadUnsafeRemoveAssociations` 的实现与这个方法也差不多，相较于 reset 方法移除某一个对象的**所有**关联对象，该方法仅仅移除了某一个 `key` 对应的值。

```objectivec
void _threadUnsafeRemoveAssociations(id object) {
	if (_associationMap->size() == 0 ){
		return;
	}

	auto i = _associationMap->find(object);
	if (i == _associationMap->end()) {
		return;
	}

	auto *refs = i->second;
	delete refs;
	_associationMap->erase(i);
}
```


调用 `_threadUnsafeRemoveAssociations` 的方法 `fb_objc_removeAssociatedObjects` 的实现也很简单，利用了上面的方法，并在执行结束后，使用原 `obj_removeAssociatedObjects` 方法对应的函数指针 `fb_orig_objc_removeAssociatedObjects` 移除关联对象：

```objectivec
static void fb_objc_removeAssociatedObjects(id object) {
	{
		std::lock_guard<std::mutex> l(*_associationMutex);
		_threadUnsafeRemoveAssociations(object);
	}

	fb_orig_objc_removeAssociatedObjects(object);
}
```

## FBObjectiveCGraphElement 获取关联对象

因为在获取某一个对象持有的所有强引用时，不可避免地需要获取其强引用的关联对象；因此我们也就需要使用 `FBAssociationManager` 提供的 `+ associationsForObject:` 接口获取所有**强引用**关联对象：

```objectivec
- (NSSet *)allRetainedObjects {
	NSArray *retainedObjectsNotWrapped = [FBAssociationManager associationsForObject:_object];
	NSMutableSet *retainedObjects = [NSMutableSet new];

	for (id obj in retainedObjectsNotWrapped) {
		FBObjectiveCGraphElement *element = FBWrapObjectGraphElementWithContext(self, obj, _configuration, @[@"__associated_object"]);
		if (element) {
			[retainedObjects addObject:element];
		}
	}

	return retainedObjects;
}
```

这个接口调用我们在上一节中介绍的 `_associationMap`，最后得到某一个对象的所有关联对象的强引用：

```objectivec
+ (NSArray *)associationsForObject:(id)object {
	return FB::AssociationManager::associations(object);
}

NSArray *associations(id object) {
	std::lock_guard<std::mutex> l(*_associationMutex);
	if (_associationMap->size() == 0 ){
		return nil;
	}

	auto i = _associationMap->find(object);
	if (i == _associationMap->end()) {
		return nil;
	}

	auto *refs = i->second;

	NSMutableArray *array = [NSMutableArray array];
	for (auto &key: *refs) {
		id value = objc_getAssociatedObject(object, key);
		if (value) {
			[array addObject:value];
		}
	}

	return array;
}
```

这部分的代码没什么好解释的，遍历所有的 `key`，检测是否真的存在关联对象，然后加入可变数组，最后返回。

## 总结

FBRetainCycleDetector 为了追踪某一 `NSObject` 对关联对象的引用，重新实现了关联对象模块，不过其实现与 ObjC 运行时中对关联对象的实现其实所差无几，如果对运行时中的关联对象实现原理有兴趣的话，可以看[关联对象 AssociatedObject 完全解析](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/objc/关联对象%20AssociatedObject%20完全解析.md)这篇文章，它介绍了底层运行时中的关联对象的实现。

这是 FBRetainCycleDetector 系列文章中的第三篇，第四篇也是最后一篇文章会介绍 FBRetainCycleDetector 是如何获取 block 持有的强引用的，这也是我觉得整个框架中实现最精彩的一部分。

> Follow: [Draveness · Github](https://github.com/Draveness)


