# 如何在 Objective-C 的环境下实现 defer

这篇文章会对 [libextobjc](https://github.com/jspahrsummers/libextobjc) 中的一小部分代码进行分析，也是**如何扩展 Objective-C 语言**系列文章的第一篇，笔者会从 libextobjc 中选择一些黑魔法进行介绍。

对 Swift 稍有了解的人都知道，`defer` 在 Swift 语言中是一个关键字；在 `defer` 代码块中的代码，会**在作用域结束时执行**。在这里，我们会使用一些神奇的方法在 Objective-C 中实现 `defer`。

> 如果你已经非常了解 `defer` 的作用，你可以跳过第一部分的内容，直接看 [Variable Attributes](#variable-attributes)。

## 关于 defer

`defer` 是 Swift 在 2.0 时代加入的一个关键字，它提供了一种非常安全并且简单的方法声明一个在作用域结束时执行的代码块。

如果你在 Swift Playground 中输入以下代码：

```objectivec
func hello() {
    defer {
        print("4")
    }
    if true {
        defer {
            print("2")
        }
        defer {
            print("1")
        }
    }
    print("3")
}

hello()
```

控制台的输出会是这样的：

```
1
2
3
4
```

你可以仔细思考一下为什么会有这样的输出，并在 Playground 使用 `defer` 写一些简单的代码，相信你可以很快理解它是如何工作的。

> 如果对 `defer` 的作用仍然不是非常了解，可以看 [guard & defer](http://nshipster.com/guard-and-defer/#defer) 这篇文章的后半部分。

## Variable Attributes

libextobjc 实现的 `defer` 并没有基于 Objective-C 的动态特性，甚至也没有调用已有的任何方法，而是使用了 [Variable Attributes](https://gcc.gnu.org/onlinedocs/gcc/Variable-Attributes.html) 这一特性。

> 同样在 GCC 中也存在用于修饰函数的 [Function Attributes](https://gcc.gnu.org/onlinedocs/gcc/Function-Attributes.html)

Variable Attributes 其实是 GCC 中用于描述变量的一种修饰符。我们可以使用 `__attribute__` 来修饰一些变量来参与静态分析等编译过程；而在 Cocoa Touch 中很多的宏其实都是通过 `__attribute__` 来实现的，例如：

```objectivec
#define NS_ROOT_CLASS __attribute__((objc_root_class))
```

而 [cleanup](https://gcc.gnu.org/onlinedocs/gcc/Common-Variable-Attributes.html#Common-Variable-Attributes#cleanup) 就是在这里会使用的变量属性：

> The cleanup attribute runs a function when the variable goes out of scope. This attribute can only be applied to auto function scope variables; it may not be applied to parameters or variables with static storage duration. The function must take one parameter, a pointer to a type compatible with the variable. The return value of the function (if any) is ignored.

GCC 文档中对 `cleanup` 属性的介绍告诉我们，在 `cleanup` 中必须传入**只有一个参数的函数并且这个参数需要与变量的类型兼容**。

如果上面这句比较绕口的话很难理解，可以通过一个简单的例子理解其使用方法：

```objectivec
void cleanup_block(int *a) {
    printf("%d\n", *a);
}

int variable __attribute__((cleanup(cleanup_block))) = 2;
```

在 `variable` 这个变量离开作用域之后，就会自动将这个变量的**指针**传入 `cleanup_block` 中，调用 `cleanup_block` 方法来进行『清理』工作。

## 实现 defer

到目前为止已经有了实现 `defer` 需要的全部知识，我们可以开始分析 libextobjc 是怎么做的。

在 libextobjc 中并没有使用 `defer` 这个名字，而是使用了 `onExit`（表示代码是在退出作用域时执行）

> 为了使 `onExit` 在使用时更加明显，libextobjc 通过一些其它的手段使得我们在每次使用 `onExit` 时都需要添加一个 `@` 符号。

```objectivec
{
    @onExit {
        NSLog("Log when out of scope.");
    };
    NSLog("Log before out of scope.");
}
```

`onExit` 其实只是一个精心设计的宏：

```objectivec
#define onExit \
    ext_keywordify \
    __strong ext_cleanupBlock_t metamacro_concat(ext_exitBlock_, __LINE__) __attribute__((cleanup(ext_executeCleanupBlock), unused)) = ^
```

既然它只是一个宏，那么上面的代码其实是可以展开的：

```objectivec
autoreleasepool {}
__strong ext_cleanupBlock_t ext_exitBlock_19 __attribute__((cleanup(ext_executeCleanupBlock), unused)) = ^ {
    NSLog("Log when out of scope.");
};
```

这里，我们分几个部分来分析上面的代码片段是如何实现 `defer` 的功能的：

1. `ext_keywordify` 也是一个宏定义，它通过添加在宏之前添加 `autoreleasepool {}` 强迫 `onExit` 前必须加上 `@` 符号。

    ```objectivec
    #define ext_keywordify autoreleasepool {}
    ```

2. `ext_cleanupBlock_t` 是一个类型：

    ```objectivec
    typedef void (^ext_cleanupBlock_t)();
    ```

3. `metamacro_concat(ext_exitBlock_, __LINE__)` 会将 `ext_exitBlock` 和当前行号拼接成一个临时的的变量名，例如：`ext_exitBlock_19`。

4. `__attribute__((cleanup(ext_executeCleanupBlock), unused))` 将 `cleanup` 函数设置为 `ext_executeCleanupBlock`；并将当前变量 `ext_exitBlock_19` 标记为 `unused` 来抑制 `Unused variable` 警告。

5. 变量 `ext_exitBlock_19` 的值为 `^{ NSLog("Log when out of scope."); }`，是一个类型为 `ext_cleanupBlock_t` 的 block。

6. 在这个变量离开作用域时，会把上面的 block 的指针传入 `cleanup` 函数，也就是 `ext_executeCleanupBlock`：

    ```objectivec
    void ext_executeCleanupBlock (__strong ext_cleanupBlock_t *block) {
        (*block)();
    }
    ```

    这个函数的作用只是简单的执行传入的 block，它满足了 GCC 文档中对 `cleanup` 函数的几个要求：

    1. 只能包含一个参数
    2. 参数的类型是一个**指向变量类型的指针**
    3. 函数的返回值是 `void`

## 总结

> 这是分析 libextobjc 框架的第一篇文章，也是比较简短的一篇，因为我们在日常开发中基本上用不到这个框架提供的 API，但是它依然会为我们展示了很多编程上的黑魔法。

libextobjc 将 `cleanup` 这一变量属性，很好地包装成了 `@onExit`，它的实现也是比较有意思的，也激起了笔者学习 GCC 编译命令并且阅读一些文档的想法。

> Follow: [Draveness · Github](https://github.com/Draveness)


