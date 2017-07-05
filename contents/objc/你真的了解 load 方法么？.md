# 你真的了解 load 方法么？

> 因为 ObjC 的 runtime 只能在 Mac OS 下才能编译，所以文章中的代码都是在 Mac OS，也就是 `x86_64` 架构下运行的，对于在 arm64 中运行的代码会特别说明。

## 写在前面

> 文章的标题与其说是问各位读者，不如说是问笔者自己：**我**真的了解 `+ load` 方法么？

`+ load` 作为 Objective-C 中的一个方法，与其它方法有很大的不同。它只是一个**在整个文件被加载到运行时，在 `main` 函数调用之前被 ObjC 运行时调用的钩子方法**。其中关键字有这么几个：

+ 文件刚加载
+ `main` 函数之前
+ 钩子方法

我在阅读 ObjC 源代码之前，曾经一度感觉自己对 `+ load` 方法的作用非常了解，直到看了源代码中的实现，才知道以前的以为，只是自己的以为罢了。

这篇文章会假设你知道：

+ 使用过 `+ load` 方法
+ 知道 `+ load` 方法的调用顺序（文章中会简单介绍）

在这篇文章中并不会用大篇幅介绍 `+ load` 方法的作用~~其实也没几个作用~~，关注点主要在以下两个问题上：

+ `+ load` 方法是如何被调用的
+ `+ load` 方法为什么会有这种调用顺序

## load 方法的调用栈

首先来通过 `load` 方法的调用栈，分析一下它到底是如何被调用的。

下面是程序的全部代码：

```objectivec
// main.m
#import <Foundation/Foundation.h>

@interface XXObject : NSObject @end

@implementation XXObject

+ (void)load {
    NSLog(@"XXObject load");
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool { }
    return 0;
}
```

代码总共只实现了一个 `XXObject` 的 `+ load` 方法，主函数中也没有任何的东西：

![objc-load-print-load](../images/objc-load-print-load.png)

虽然在主函数中什么方法都没有调用，但是运行之后，依然打印了 `XXObject load` 字符串，也就是说调用了 `+ load` 方法。

### 使用符号断点

使用 Xcode 添加一个符号断点 `+[XXObject load]`：

> 注意这里 `+` 和 `[` 之间没有空格

![objc-load-symbolic-breakpoint](../images/objc-load-symbolic-breakpoint.png)

> 为什么要加一个符号断点呢？因为这样看起来比较高级。

重新运行程序。这时，代码会停在 `NSLog(@"XXObject load");` 这一行的实现上：

![objc-load-break-after-add-breakpoint](../images/objc-load-break-after-add-breakpoint.png)

左侧的调用栈很清楚的告诉我们，哪些方法被调用了：

```objectivec
0  +[XXObject load]
1  call_class_loads()
2  call_load_methods
3  load_images
4  dyld::notifySingle(dyld_image_states, ImageLoader const*)
11 _dyld_start
```

> [dyld](https://developer.apple.com/library/ios/documentation/System/Conceptual/ManPages_iPhoneOS/man3/dyld.3.html) 是 the dynamic link editor 的缩写，它是苹果的*动态链接器*。
> 
> 在系统内核做好程序准备工作之后，交由 dyld 负责余下的工作。本文不会对其进行解释

每当有新的镜像加载之后，都会执行 `3 load_images` 方法进行回调，这里的回调是在整个运行时初始化时 `_objc_init` 注册的（会在之后的文章中具体介绍）：

```objectivec
dyld_register_image_state_change_handler(dyld_image_state_dependents_initialized, 0/*not batch*/, &load_images);
```

有新的镜像被加载到 runtime 时，调用 `load_images` 方法，并传入最新镜像的信息列表 `infoList`：

```objectivec
const char *
load_images(enum dyld_image_states state, uint32_t infoCount,
            const struct dyld_image_info infoList[])
{
    bool found;

    found = false;
    for (uint32_t i = 0; i < infoCount; i++) {
        if (hasLoadMethods((const headerType *)infoList[i].imageLoadAddress)) {
            found = true;
            break;
        }
    }
    if (!found) return nil;

    recursive_mutex_locker_t lock(loadMethodLock);

    {
        rwlock_writer_t lock2(runtimeLock);
        found = load_images_nolock(state, infoCount, infoList);
    }

    if (found) {
        call_load_methods();
    }

    return nil;
}
```

### 什么是镜像

这里就会遇到一个问题：镜像到底是什么，我们用一个断点打印出所有加载的镜像：

![objc-load-print-image-info](../images/objc-load-print-image-info.png)

从控制台输出的结果大概就是这样的，我们可以看到镜像并不是一个 Objective-C 的代码文件，它应该是一个 target 的编译产物。

```objectivec
...
(const dyld_image_info) $52 = {
  imageLoadAddress = 0x00007fff8a144000
  imageFilePath = 0x00007fff8a144168 "/System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices"
  imageFileModDate = 1452737802
}
(const dyld_image_info) $53 = {
  imageLoadAddress = 0x00007fff946d9000
  imageFilePath = 0x00007fff946d9480 "/usr/lib/liblangid.dylib"
  imageFileModDate = 1452737618
}
(const dyld_image_info) $54 = {
  imageLoadAddress = 0x00007fff88016000
  imageFilePath = 0x00007fff88016d40 "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"
  imageFileModDate = 1452737917
}
(const dyld_image_info) $55 = {
  imageLoadAddress = 0x0000000100000000
  imageFilePath = 0x00007fff5fbff8f0 "/Users/apple/Library/Developer/Xcode/DerivedData/objc-dibgivkseuawonexgbqssmdszazo/Build/Products/Debug/debug-objc"
  imageFileModDate = 0
}
```

这里面有很多的动态链接库，还有一些苹果为我们提供的框架，比如 Foundation、 CoreServices 等等，都是在这个 `load_images` 中加载进来的，而这些 `imageFilePath` 都是对应的**二进制文件**的地址。

但是如果进入最下面的这个目录，会发现它是一个**可执行文件**，它的运行结果与 Xcode 中的运行结果相同：

![objc-load-image-binary](../images/objc-load-image-binary.png)

### 准备 + load 方法

我们重新回到 `load_images` 方法，如果在扫描镜像的过程中发现了 `+ load` 符号：

```objectivec
for (uint32_t i = 0; i < infoCount; i++) {
    if (hasLoadMethods((const headerType *)infoList[i].imageLoadAddress)) {
        found = true;
        break;
    }
}
```

就会进入 `load_images_nolock` 来查找 `load` 方法：

```objectivec
bool load_images_nolock(enum dyld_image_states state,uint32_t infoCount,
                   const struct dyld_image_info infoList[])
{
    bool found = NO;
    uint32_t i;

    i = infoCount;
    while (i--) {
        const headerType *mhdr = (headerType*)infoList[i].imageLoadAddress;
        if (!hasLoadMethods(mhdr)) continue;

        prepare_load_methods(mhdr);
        found = YES;
    }

    return found;
}
```

调用 `prepare_load_methods` 对 `load` 方法的调用进行准备（将需要调用 `load` 方法的类添加到一个列表中，后面的小节中会介绍）：

```objectivec
void prepare_load_methods(const headerType *mhdr)
{
    size_t count, i;

    runtimeLock.assertWriting();

    classref_t *classlist = 
        _getObjc2NonlazyClassList(mhdr, &count);
    for (i = 0; i < count; i++) {
        schedule_class_load(remapClass(classlist[i]));
    }

    category_t **categorylist = _getObjc2NonlazyCategoryList(mhdr, &count);
    for (i = 0; i < count; i++) {
        category_t *cat = categorylist[i];
        Class cls = remapClass(cat->cls);
        if (!cls) continue;  // category for ignored weak-linked class
        realizeClass(cls);
        assert(cls->ISA()->isRealized());
        add_category_to_loadable_list(cat);
    }
}
```

通过 `_getObjc2NonlazyClassList` 获取所有的类的列表之后，会通过 `remapClass` 获取类对应的指针，然后调用 `schedule_class_load` **递归地安排当前类和没有调用 `+ load` 父类**进入列表。

```objectivec
static void schedule_class_load(Class cls)
{
    if (!cls) return;
    assert(cls->isRealized());

    if (cls->data()->flags & RW_LOADED) return;

    schedule_class_load(cls->superclass);

    add_class_to_loadable_list(cls);
    cls->setInfo(RW_LOADED); 
}
```

在执行 `add_class_to_loadable_list(cls)` 将当前类加入加载列表之前，会**先把父类加入待加载的列表**，保证父类在子类前调用 `load` 方法。

### 调用 + load 方法

在将镜像加载到运行时、对 `load` 方法的准备就绪之后，执行 `call_load_methods`，开始调用 `load` 方法：

```objectivec
void call_load_methods(void)
{
    ...

    do {
        while (loadable_classes_used > 0) {
            call_class_loads();
        }

        more_categories = call_category_loads();

    } while (loadable_classes_used > 0  ||  more_categories);

    ...
}
```

方法的调用流程大概是这样的：

![objc-load-diagra](../images/objc-load-diagram.png)

其中 `call_class_loads` 会从一个待加载的类列表 `loadable_classes` 中寻找对应的类，然后找到 `@selector(load)` 的实现并执行。

```objectivec
static void call_class_loads(void)
{
    int i;
    
    struct loadable_class *classes = loadable_classes;
    int used = loadable_classes_used;
    loadable_classes = nil;
    loadable_classes_allocated = 0;
    loadable_classes_used = 0;
    
    for (i = 0; i < used; i++) {
        Class cls = classes[i].cls;
        load_method_t load_method = (load_method_t)classes[i].method;
        if (!cls) continue;

        (*load_method)(cls, SEL_load);
    }
    
    if (classes) free(classes);
}
```

这行 `(*load_method)(cls, SEL_load)` 代码就会调用 `+[XXObject load]` 方法。

> 我们会在下面介绍 `loadable_classes` 列表是如何管理的。

到现在，我们回答了第一个问题：

Q：**`load` 方法是如何被调用的？**

A：当 Objective-C 运行时初始化的时候，会通过 `dyld_register_image_state_change_handler` 在每次有新的镜像加入*运行时*的时候，进行回调。执行 `load_images` 将所有包含 `load` 方法的文件加入列表 `loadable_classes` ，然后从这个列表中找到对应的 `load` 方法的实现，调用 `load` 方法。

## 加载的管理

ObjC 对于加载的管理，主要使用了两个列表，分别是 `loadable_classes` 和 `loadable_categories`。

方法的调用过程也分为两个部分，准备 `load` 方法和调用 `load` 方法，我更觉得这两个部分比较像生产者与消费者：

![objc-load-producer-consumer-diagra](../images/objc-load-producer-consumer-diagram.png)


`add_class_to_loadable_list` 方法负责将类加入 `loadable_classes` 集合，而 `call_class_loads` 负责消费集合中的元素。

而对于分类来说，其模型也是类似的，只不过使用了另一个列表 `loadable_categories`。

### “生产” loadable_class

在调用 `load_images -> load_images_nolock -> prepare_load_methods -> schedule_class_load -> add_class_to_loadable_list` 的时候会将未加载的类添加到 `loadable_classes` 数组中：

```objectivec
void add_class_to_loadable_list(Class cls)
{
    IMP method;

    loadMethodLock.assertLocked();

    method = cls->getLoadMethod();
    if (!method) return;

    if (loadable_classes_used == loadable_classes_allocated) {
        loadable_classes_allocated = loadable_classes_allocated*2 + 16;
        loadable_classes = (struct loadable_class *)
            realloc(loadable_classes,
                              loadable_classes_allocated *
                              sizeof(struct loadable_class));
    }
    
    loadable_classes[loadable_classes_used].cls = cls;
    loadable_classes[loadable_classes_used].method = method;
    loadable_classes_used++;
}
```

方法刚被调用时：

1. 会从 `class` 中获取 `load` 方法： `method = cls->getLoadMethod();`
2. 判断当前 `loadable_classes` 这个数组是否已经被全部占用了：`loadable_classes_used == loadable_classes_allocated`
3. 在当前数组的基础上扩大数组的大小：`realloc`
4. 把传入的 `class` 以及对应的方法的实现加到列表中

另外一个用于保存分类的列表 `loadable_categories` 也有一个类似的方法 `add_category_to_loadable_list`。

```objectivec
void add_category_to_loadable_list(Category cat)
{
    IMP method;

    loadMethodLock.assertLocked();

    method = _category_getLoadMethod(cat);

    if (!method) return;
    
    if (loadable_categories_used == loadable_categories_allocated) {
        loadable_categories_allocated = loadable_categories_allocated*2 + 16;
        loadable_categories = (struct loadable_category *)
            realloc(loadable_categories,
                              loadable_categories_allocated *
                              sizeof(struct loadable_category));
    }

    loadable_categories[loadable_categories_used].cat = cat;
    loadable_categories[loadable_categories_used].method = method;
    loadable_categories_used++;
}
```

实现几乎与 `add_class_to_loadable_list` 完全相同。

到这里我们完成了对 `loadable_classes` 以及 `loadable_categories` 的提供，下面会开始消耗列表中的元素。

### “消费” loadable_class

调用 `load` 方法的过程就是“消费” `loadable_classes` 的过程，`load_images -> call_load_methods -> call_class_loads` 会从 `loadable_classes` 中取出对应类和方法，执行 `load`。

```objectivec
void call_load_methods(void)
{
    static bool loading = NO;
    bool more_categories;

    loadMethodLock.assertLocked();

    if (loading) return;
    loading = YES;

    void *pool = objc_autoreleasePoolPush();

    do {
        while (loadable_classes_used > 0) {
            call_class_loads();
        }

        more_categories = call_category_loads();

    } while (loadable_classes_used > 0  ||  more_categories);

    objc_autoreleasePoolPop(pool);

    loading = NO;
}
```

上述方法对所有在 `loadable_classes` 以及 `loadable_categories` 中的类以及分类执行 `load` 方法。

```objectivec
do {
    while (loadable_classes_used > 0) {
        call_class_loads();
    }

    more_categories = call_category_loads();

} while (loadable_classes_used > 0  ||  more_categories);
```

调用顺序如下：

1. 不停调用类的 `+ load` 方法，直到 `loadable_classes` 为空
2. 调用**一次** `call_category_loads` 加载分类
3. 如果有 `loadable_classes` 或者更多的分类，继续调用 `load` 方法

相比于类 `load` 方法的调用，分类中 `load` 方法的调用就有些复杂了：

```objectivec
static bool call_category_loads(void)
{
    int i, shift;
    bool new_categories_added = NO;
    // 1. 获取当前可以加载的分类列表
    struct loadable_category *cats = loadable_categories;
    int used = loadable_categories_used;
    int allocated = loadable_categories_allocated;
    loadable_categories = nil;
    loadable_categories_allocated = 0;
    loadable_categories_used = 0;

    for (i = 0; i < used; i++) {
        Category cat = cats[i].cat;
        load_method_t load_method = (load_method_t)cats[i].method;
        Class cls;
        if (!cat) continue;

        cls = _category_getClass(cat);
        if (cls  &&  cls->isLoadable()) {
            // 2. 如果当前类是可加载的 `cls  &&  cls->isLoadable()` 就会调用分类的 load 方法
            (*load_method)(cls, SEL_load);
            cats[i].cat = nil;
        }
    }

    // 3. 将所有加载过的分类移除 `loadable_categories` 列表
    shift = 0;
    for (i = 0; i < used; i++) {
        if (cats[i].cat) {
            cats[i-shift] = cats[i];
        } else {
            shift++;
        }
    }
    used -= shift;

    // 4. 为 `loadable_categories` 重新分配内存，并重新设置它的值
    new_categories_added = (loadable_categories_used > 0);
    for (i = 0; i < loadable_categories_used; i++) {
        if (used == allocated) {
            allocated = allocated*2 + 16;
            cats = (struct loadable_category *)
                realloc(cats, allocated *
                                  sizeof(struct loadable_category));
        }
        cats[used++] = loadable_categories[i];
    }

    if (loadable_categories) free(loadable_categories);

    if (used) {
        loadable_categories = cats;
        loadable_categories_used = used;
        loadable_categories_allocated = allocated;
    } else {
        if (cats) free(cats);
        loadable_categories = nil;
        loadable_categories_used = 0;
        loadable_categories_allocated = 0;
    }

    return new_categories_added;
}
```

这个方法有些长，我们来分步解释方法的作用：

1. 获取当前可以加载的分类列表
2. 如果当前类是可加载的 `cls  &&  cls->isLoadable()` 就会调用分类的 `load` 方法
3. 将所有加载过的分类移除 `loadable_categories` 列表
4. 为 `loadable_categories` 重新分配内存，并重新设置它的值

## 调用的顺序

你过去可能会听说过，对于 `load` 方法的调用顺序有两条规则：

1. 父类先于子类调用
2. 类先于分类调用

这种现象是非常符合我们的直觉的，我们来分析一下这种现象出现的原因。

第一条规则是由于 `schedule_class_load` 有如下的实现：

```objectivec
static void schedule_class_load(Class cls)
{
    if (!cls) return;
    assert(cls->isRealized());

    if (cls->data()->flags & RW_LOADED) return;

    schedule_class_load(cls->superclass);

    add_class_to_loadable_list(cls);
    cls->setInfo(RW_LOADED); 
}
```

这里通过这行代码 `schedule_class_load(cls->superclass)` 总是能够保证没有调用 `load` 方法的父类先于子类加入 `loadable_classes` 数组，从而确保其调用顺序的正确性。

类与分类中 `load` 方法的调用顺序主要在 `call_load_methods` 中实现：

```objectivec
do {
    while (loadable_classes_used > 0) {
        call_class_loads();
    }

    more_categories = call_category_loads();

} while (loadable_classes_used > 0  ||  more_categories);
```

上面的 `do while` 语句能够在一定程度上确保，类的 `load` 方法会先于分类调用。但是这里不能完全保证调用顺序的正确。

如果**分类的镜像在类的镜像之前加载到运行时**，上面的代码就没法保证顺序的正确了，所以，我们还需要在 `call_category_loads` 中判断类是否已经加载到内存中（调用 `load` 方法）：

```objectivec
if (cls  &&  cls->isLoadable()) {
    (*load_method)(cls, SEL_load);
    cats[i].cat = nil;
}
```

这里，检查了类是否存在并且是否可以加载，如果都为真，那么就可以调用分类的 load 方法了。

## load 的应用

`load` 可以说我们在日常开发中可以接触到的调用时间**最靠前的方法**，在主函数运行之前，`load` 方法就会调用。

由于它的调用不是*惰性*的，且其只会在程序调用期间调用一次，最最重要的是，如果在类与分类中都实现了 `load` 方法，它们都会被调用，不像其它的在分类中实现的方法会被覆盖，这就使 `load` 方法成为了[方法调剂](http://nshipster.com/method-swizzling/)的绝佳时机。

但是由于 `load` 方法的运行时间过早，所以这里可能不是一个理想的环境，因为**某些类可能需要在在其它类之前加载**，但是这是我们无法保证的。不过在这个时间点，所有的 framework 都已经加载到了运行时中，所以调用 framework 中的方法都是安全的。

## 参考资料

+ [NSObject +load and +initialize - What do they do?](http://stackoverflow.com/questions/13326435/nsobject-load-and-initialize-what-do-they-do)
+ [Method Swizzling](http://nshipster.com/method-swizzling/)
+ [Objective-C Class Loading and Initialization](https://www.mikeash.com/pyblog/friday-qa-2009-05-22-objective-c-class-loading-and-initialization.html)

Follow: [@Draveness](https://github.com/Draveness)


