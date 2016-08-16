# 对象是如何初始化的（iOS）

在之前，我们已经讨论了非常多的问题了，关于 objc 源代码系列的文章也快结束了，其实关于对象是如何初始化的这篇文章本来是我要写的第一篇文章，但是由于有很多前置内容不得不说，所以留到了这里。

`+ alloc` 和 `- init` 这一对我们在 iOS 开发中每天都要用到的初始化方法一直困扰着我, 于是笔者仔细研究了一下 objc 源码中 `NSObject` 如何进行初始化。

在具体分析对象的初始化过程之前，我想先放出结论，以免文章中的细枝末节对读者的理解有所影响；整个对象的初始化过程其实只是**为一个分配内存空间，并且初始化 isa_t 结构体的过程**。

## alloc 方法分析

先来看一下 `+ alloc` 方法的调用栈(在调用栈中省略了很多不必要的方法的调用):

```objectivec
id _objc_rootAlloc(Class cls)
└── static id callAlloc(Class cls, bool checkNil, bool allocWithZone=false)
    └── id class_createInstance(Class cls, size_t extraBytes)
    	└── id _class_createInstanceFromZone(Class cls, size_t extraBytes, void *zone, bool cxxConstruct, size_t *outAllocatedSize)
            ├── size_t instanceSize(size_t extraBytes)
            ├── void	*calloc(size_t, size_t)
            └── inline void objc_object::initInstanceIsa(Class cls, bool hasCxxDtor)
```

这个调用栈中的方法涉及了多个文件中的代码，在下面的章节中会对调用的方法逐步进行分析，如果这个调用栈让你觉得很头疼，也不是什么问题。

### alloc 的实现

```objectivec
+ (id)alloc {
    return _objc_rootAlloc(self);
}
```

`alloc` 方法的实现真的是非常的简单, 它直接调用了另一个私有方法 `id _objc_rootAlloc(Class cls)`

```objectivec
id _objc_rootAlloc(Class cls) {
    return callAlloc(cls, false/*checkNil*/, true/*allocWithZone*/);
}
```

这就是上帝类 `NSObject` 对 `callAlloc` 的实现，我们省略了非常多的代码，展示了最常见的执行路径：

```objectivec
static id callAlloc(Class cls, bool checkNil, bool allocWithZone=false) {
    id obj = class_createInstance(cls, 0);
    return obj;
}

id class_createInstance(Class cls, size_t extraBytes) {
    return _class_createInstanceFromZone(cls, extraBytes, nil);
}
```

对象初始化中最重要的操作都在 `_class_createInstanceFromZone` 方法中执行：

```objectivec
static id _class_createInstanceFromZone(Class cls, size_t extraBytes, void *zone, bool cxxConstruct = true, size_t *outAllocatedSize = nil) {
    size_t size = cls->instanceSize(extraBytes);

    id obj = (id)calloc(1, size);
    if (!obj) return nil;
    obj->initInstanceIsa(cls, hasCxxDtor);

    return obj;
}
```

### 对象的大小

在使用 `calloc` 为对象分配一块内存空间之前，我们要先获取对象在内存的大小：

```objectivec
size_t instanceSize(size_t extraBytes) {
    size_t size = alignedInstanceSize() + extraBytes;
    if (size < 16) size = 16;
    return size;
}

uint32_t alignedInstanceSize() {
    return word_align(unalignedInstanceSize());
}

uint32_t unalignedInstanceSize() {
    assert(isRealized());
    return data()->ro->instanceSize;
}
```

实例大小 `instanceSize` 会存储在类的 `isa_t` 结构体中，然后经过对齐最后返回。

> Core Foundation 需要所有的对象的大小都必须大于或等于 16 字节。

在获取对象大小之后，直接调用 `calloc` 函数就可以为对象分配内存空间了。

### isa 的初始化

在对象的初始化过程中除了使用 `calloc` 来分配内存之外，还需要根据类初始化 `isa_t` 结构体：

```objectivec
inline void objc_object::initIsa(Class cls, bool indexed, bool hasCxxDtor) { 
    if (!indexed) {
        isa.cls = cls;
    } else {
        isa.bits = ISA_MAGIC_VALUE;
        isa.has_cxx_dtor = hasCxxDtor;
        isa.shiftcls = (uintptr_t)cls >> 3;
    }
}
```

上面的代码只是对 `isa_t` 结构体进行初始化而已：

```objectivec
union isa_t {
   isa_t() { }
   isa_t(uintptr_t value) : bits(value) { }
    
   Class cls;
   uintptr_t bits;
    
   struct {
       uintptr_t indexed           : 1;
       uintptr_t has_assoc         : 1;
       uintptr_t has_cxx_dtor      : 1;
       uintptr_t shiftcls          : 44;
       uintptr_t magic             : 6;
       uintptr_t weakly_referenced : 1;
       uintptr_t deallocating      : 1;
       uintptr_t has_sidetable_rc  : 1;
       uintptr_t extra_rc          : 8;
   };
};
```

> 在这里并不想过多介绍关于 `isa_t` 结构体的内容，你可以看[从 NSObject 的初始化了解 isa](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/objc/从%20NSObject%20的初始化了解%20isa.md) 来了解你想知道的关于 `isa_t` 的全部内容。

## init 方法

`NSObject` 的 `- init` 方法只是调用了 `_objc_rootInit` 并返回了当前对象：

```objectivec
- (id)init {
    return _objc_rootInit(self);
}

id _objc_rootInit(id obj) {
    return obj;
}
```

## 总结

在 iOS 中一个对象的初始化过程很符合直觉，只是分配内存空间、然后初始化 `isa_t` 结构体，其实现也并不复杂，这篇文章也是这个系列文章中较为简单并且简短的一篇。

> Follow: [Draveness · Github](https://github.com/Draveness)


