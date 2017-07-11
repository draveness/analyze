# 谈谈 MVX 中的 View

+ [谈谈 MVX 中的 Model](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/architecture/mvx-model.md)
+ [谈谈 MVX 中的 View](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/architecture/mvx-view.md) 
+ [谈谈 MVX 中的 Controller](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/architecture/mvx-controller.md)
+ [浅谈 MVC、MVP 和 MVVM 架构模式](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/architecture/mvx.md)

> Follow GitHub: [Draveness](https://github.com/Draveness)

这是谈谈 MVX 系列的第二篇文章，上一篇文章中对 iOS 中 Model 层的设计进行了简要的分析；而在这里，我们会对 MVC 中的视图层进行讨论，谈一谈现有的视图层有着什么样的问题，如何在框架的层面上去改进，同时与服务端的视图层进行对比，分析它们的差异。

## UIKit

UIKit 是 Cocoa Touch 中用于构建和管理应用的用户界面的框架，其中几乎包含着与 UI 相关的全部功能，而我们今天想要介绍的其实是 UIKit 中与视图相关的一部分，也就是 `UIView` 以及相关类。

`UIView` 可以说是 iOS 中用于渲染和展示内容的最小单元，作为开发者能够接触到的大多数属性和方法也都由 `UIView` 所提供，比如最基本的布局方式 frame 就是通过 `UIView` 的属性所控制，在 Cocoa Touch 中的所有布局系统最终都会转化为 CFRect 并通过 frame 的方式完成最终的布局。

![Frame-And-Components](images/view/Frame-And-Components.jpg)

`UIView` 作为 UIKit 中极为重要的类，它的 API 以及设计理念决定了整个 iOS 的视图层该如何工作，这也是理解视图层之前必须要先理解 `UIView` 的原因。

### UIView

在 UIKit 中，除了极少数用于展示的类不继承自 `UIView` 之外，几乎所有类的父类或者或者祖先链中一定会存在 `UIView`。

![UIView-And-Subclasses](images/view/UIView-And-Subclasses.jpg)

我们暂且抛开不继承自 `UIView` 的 `UIBarItem` 类簇不提，先通过一段代码分析一下 `UIView` 具有哪些特性。

```objectivec
UIImageView *backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"backgoundImage"]];
UIImageView *logoView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo"]];

UIButton *loginButton = [[UIButton alloc] init];
[loginButton setTitle:@"登录" forState:UIControlStateNormal];
[loginButton setTitleColor:UIColorFromRGB(0xFFFFFF) forState:UIControlStateNormal];
[loginButton.titleLabel setFont:[UIFont boldSystemFontOfSize:18]];
[loginButton setBackgroundColor:UIColorFromRGB(0x00C3F3)];

[self.view addSubview:backgroundView];
[backgroundView addSubview:logoView];
[backgroundView addSubview:loginButton];
```

`UIView` 作为视图层大部分元素的根类，提供了两个非常重要的特性：

+ 由于 `UIView` 具有 `frame` 属性，所以为所有继承自 `UIView` 的类提供了绝对布局相关的功能，也就是在 Cocoa Touch 中，所有的视图元素都可以通过 `frame` 设置自己在父视图中的绝对布局；
+ `UIView` 在接口中提供了操作和管理视图层级的属性和方法，比如 `superview`、`subviews` 以及 `-addSubview:` 等方法；

    ```objectivec
    @interface UIView (UIViewHierarchy)
    
    @property (nullable, nonatomic, readonly) UIView       *superview;
    @property (nonatomic, readonly, copy) NSArray<__kindof UIView *> *subviews;
    
    - (void)addSubview:(UIView *)view;
    
    ...
    
    @end
    ```

    也就是说 **UIView 和它所有的子类都可以拥有子视图，成为容器并包含其他 UIView 的实例**。

    ```objectivec
    [self.view addSubview:backgroundView];
    [backgroundView addSubview:logoView];
    [backgroundView addSubview:loginButton];
    ```

这种使用 `UIView` 同时为子类提供默认的 `frame` 布局以及子视图支持的方式在一定程度上能够降低视图模型的复杂度：因为所有的视图都是一个容器，所以在开发时不需要区分视图和容器，但是这种方式虽然带来了一些方便，但是也不可避免地带来了一些问题。

### UIView 与布局

在早期的 Cocoa Touch 中，整个视图层的布局都只是通过 `frame` 属性来完成的（绝对布局），一方面是因为在 iPhone5 之前，iOS 应用需要适配的屏幕尺寸非常单一，完全没有适配的兼容问题，所以使用单一的 `frame` 布局方式完全是可行的。

但是在目前各种屏幕尺寸的种类暴增的情况下，就很难使用 `frame` 对所有的屏幕进行适配，在这时苹果就引入了 Auto Layout 采用相对距离为视图层的元素进行布局。

![AutoLayout](images/view/AutoLayout.jpg)

不过，这算是苹果比较失败的一次性尝试，主要是因为使用 Auto Layout 对视图进行布局实在太过复杂，所以刚出来的时候也不温不火，很少有人使用，直到 Masonry 的出现使得编写 Auto Layout 代码没有那么麻烦和痛苦才普及起来。

但是由于 Auto Layout 的工作原理实际上是解 N 元一次方程组，所以在遇到复杂视图时，会遇到非常严重的性能问题，如果想要了解相关的问题的话，可以阅读 [从 Auto Layout 的布局算法谈性能](http://draveness.me/layout-performance.html) 这篇文章，在这里就不再赘述了。

然而 Auto Layout 的相对布局虽然能够在*一定程度上*解决适配**屏幕大小和尺寸接近的**适配问题，比如 iPhone4s、iPhone5、iPhone6 Plus 等移动设备，或者iPad 等平板设备。但是，Auto Layout 不能通过一套代码打通 iPhone 和 iPad 之间布局方式的差异，只能通过代码中的 if 和 else 进行判断。

在这种背景下，苹果做了很多的尝试，比如说 [Size-Class-Specific Layout](https://developer.apple.com/library/content/documentation/UserExperience/Conceptual/AutolayoutPG/Size-ClassSpecificLayout.html)，Size Class 将屏幕的长宽分为三种：

+ Compact
+ Regular
+ Any

这样就出现了最多 3 x 3 的组合，比如屏幕宽度为 Compact 高度为 Regular 等等，它与 Auto Layout 一起工作省去了一些 if 和 else 的条件判断，但是从实际效果上来说，它的用处并不是特别大，而且使用代码来做 Size Class 的相关工作依然非常困难。

除了 Auto Layout 和 Size Class 之外，苹果在 iOS9 还推出了 `UIStackView` 来增加 iOS 中的布局方式和手段，这是一种类似 flexbox 的布局方式。

虽然 `UIStackView` 可以起到一定的作用，但是由于大多数 iOS 应用都要求对设计稿进行严格还原并且其 API 设计相对啰嗦，开发者同时也习惯了使用 Auto Layout 的开发方式，在惯性的驱动下，`UIStackView` 应用的也不是非常广泛。

![UIStackVie](images/view/UIStackView.jpg)

不过现在很多跨平台的框架都是用类似 `UIStackView` 的方式进行布局，比如 React Native、Weex 等，其内部都使用 Facebook 开源的 Yoga。

> 由于 flexbox 以及类似的布局方式在其他平台上都有类似的实现，并且其应用确实非常广泛，笔者认为随着工具的完善，这种布局方式会逐渐进入 iOS 开发者的工具箱中。

三种布局方式 `frame`、Auto Layout 以及 `UIStackView` 其实最终布局都会使用 `frame`，其他两种方式 Auto Layout 和 `UIStackView` 都会将代码*描述*的布局转换成 `frame` 进行。

#### 布局机制的混用

Auto Layout 和 `UIStackView` 的出现虽然为布局提供了一些方便，但是也增加了布局系统的复杂性。

因为在 iOS 中几乎所有的视图都继承自 `UIView`，这样也同时继承了 `frame` 属性，在使用 Auto Layout 和 `UIStackView` 时，并没有禁用 `frame` 布局，所以在混用却没有掌握技巧时可能会有一些比较奇怪的问题。

其实，在混用 Auto Layout 和 `frame` 时遇到的大部分奇怪的问题都是因为 [translatesAutoresizingMaskIntoConstraints](https://developer.apple.com/reference/uikit/uiview/1622572-translatesautoresizingmaskintoco) 属性没有被正确设置的原因。

> If this property’s value is true, the system creates a set of constraints that duplicate the behavior specified by the view’s autoresizing mask. This also lets you modify the view’s size and location using the view’s frame, bounds, or center properties, allowing you to create a static, frame-based layout within Auto Layout.

在这里就不详细解释该属性的作用和使用方法了。

#### 对动画的影响

在 Auto Layout 出现之前，由于一切布局都是使用 `frame` 工作的，所以在 iOS 中完成对动画的编写十分容易。

```objectivec
UIView.animate(withDuration: 1.0) { 
    view.frame = CGRect(x: 10, y: 10, width: 200, height: 200)
}
```

而当大部分的 iOS 应用都转而使用 Auto Layout 之后，对于视图大小、位置有关的动画就比较麻烦了：

```objectivec
topConstraint.constant = 10
leftConstraint.constant = 10
heightConstraint.constant = 200
widthConstraint.constant = 200
UIView.animate(withDuration: 1.0) {
    view.layoutIfNeeded()
}
```

我们需要对视图上的约束对象一一修改并在最后调用 `layoutIfNeeded` 方法才可以完成相同的动画。由于 Auto Layout 对动画的支持并不是特别的优秀，所以在很多时候笔者在使用 Auto Layout 的视图上，都会使用 `transform` 属性来改变视图的位置，这样虽然也没有那么的优雅，不过也是一个比较方便的解决方案。

![lottie](images/view/lottie.jpg)

### frame 的问题

每一个 `UIView` 的 `frame` 属性其实都是一个 `CGRect` 结构体，这个结构体展开之后有四个组成部分：

+ origin
    + x
    + y
+ size
    + width
    + height

当我们设置一个 `UIView` 对象的 `frame` 属性时，其实是同时设置了它在父视图中的位置和它的大小，从这里可以获得一条比较重要的信息：

> iOS 中所有的 `UIView` 对象都是使用 `frame` 布局的，否则 `frame` 中的 `origin` 部分就失去了意义。

但是如果为 `UIStackView` 中的视图设置 `frame` 的话，这个属性就完全没什么作用了，比如下面的代码：

```objectivec
UIStackView *stackView = [[UIStackView alloc] init];
stackView.frame = self.view.frame;
[self.view addSubview:stackView];

UIView *greenView = [[UIView alloc] init];
greenView.backgroundColor = [UIColor greenColor];
greenView.frame = CGRectMake(0, 0, 100, 100);
[stackView addArrangedSubview:greenView];

UIView *redView = [[UIView alloc] init];
redView.backgroundColor = [UIColor redColor];
redView.frame = CGRectMake(0, 0, 100, 100);
[stackView addArrangedSubview:redView];
```

`frame` 属性在 `UIStackView` 上基本上就完全失效了，我们还需要使用约束来控制 `UIStackView` 中视图的大小，不过如果你要使用 `frame` 属性来查看视图在父视图的位置和大小，在恰当的时机下是可行的。

#### 谈谈 origin

但是 `frame` 的不正确使用会导致视图之间的耦合，如果内部视图设置了自己在父视图中的 `origin`，但是父视图其实并不会使用直接 `frame` 布局该怎么办？比如，父视图是一个 `UIStackView`，它就会重写子视图的 `origin` 甚至是没有正确设置的 `size` 属性。

最重要的是 `UIView` 上 `frame` 的设计导致了视图之间可能会有较强的耦合，因为**子视图不应该知道自己在父视图中的位置**，它应该只关心自己的大小。

也就是作为一个简单的 `UIView` 它应该只能设置自己的 `size` 而不是 `origin`，因为父视图可能是一个 `UIStackView` 也可能是一个 `UITableView` 甚至是一个扇形的视图也不是不可能，所以**位置这一信息并不是子视图应该关心的**。

如果视图设置了自己的 `origin` 其实也就默认了自己的父视图一定是使用 `frame` 进行布局的，而一旦依赖于外部的信息，它就很难进行复用了。

#### 再谈 size

关于视图大小的确认，其实也是有一些问题的，因为视图在布局时确实可能依赖于父视图的大小，或者更确切的说是需要父视图提供一个可供布局的大小，然后让子视图通过这个 `CGSize` 返回一个自己需要的大小给父视图。

![texture](images/view/texture.png)

这种计算视图大小的方式，其实比较像 [Texture](https://github.com/TextureGroup/Texture) 也就是原来的 AsyncDisplayKit 中对于布局系统的实现。

父视图通过调用子视图的 `-layoutSpecThatFits:` 方法获取子视图布局所需要的大小，而子视图通过父视图传入的 `CGSizeRange` 来设置自己的大小。

```objectivec
- (ASLayoutSpec *)layoutSpecThatFits:(ASSizeRange)constrainedSize
    ...
}
```

通过这种方式，子视图对父视图一无所知，它不知道父视图的任何属性，只通过 `-layoutSpecThatFits:` 方法传入的参数进行布局，实现了解耦以及代码复用。

### 小结

由于确实需要对多尺寸的屏幕进行适配，苹果推出 Auto Layout 和 `UIStackView` 的初衷也没有错，但是在笔者看来，因为绝大部分视图都继承自 `UIView`，所以在很多情况下并没有对开发者进行强限制，比如在使用 `UIStackView` 时只能使用 flexbox 式的布局，在使用 Auto Layout 时也只能使用约束对视图进行布局等等，所以在很多时候会带来一些不必要的问题。

同时 `UIView` 中的 `frame` 属性虽然在一开始能够很好的解决的布局的问题，但是随着布局系统变得越来越复杂，使得很多 UI 组件在与非 `frame` 布局的容器同时使用时产生了冲突，最终破坏了良好的封装性。

到目前为止 iOS 中的视图层的问题主要就是 `UIView` 作为视图层中的上帝类，提供的 `frame` 布局系统不能良好的和其他布局系统工作，在一些时候 `frame` 属性完全成为了摆设。

## 其他平台对视图层的设计

在接下来的文章中，我们会介绍和分析其他平台 Android、Web 前端以及后端是如何对视图层进行设计的。

### Android 与 View

与 iOS 上使用命令式的风格生成界面不同，Android 使用声明式的 XML 对界面进行描述，在这里举一个最简单的例子：

```xml
<android.support.constraint.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context="com.example.draveness.myapplication.DisplayMessageActivity">

    <TextView
        android:id="@+id/textView"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:text="TextView"
        app:layout_constraintLeft_toLeftOf="parent"
        app:layout_constraintRight_toRightOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</android.support.constraint.ConstraintLayout>
```

> 整个 XML 文件同时描述了视图的结构和样式，而这也是 Android 对于视图层的设计方式，将结构和样式混合在一个文件中。

我们首先来分析一下上述代码的结构，整个 XML 文件中只有两个元素，如果我们去掉其中所有的属性，整个界面的元素就是这样的：

```xml
<ConstraintLayout>
    <TextView/>
</ConstraintLayout>
```

由一个 `ConstraintLayout` 节点包含一个 `TextView` 节点。

#### View 和 ViewGroup

我们再来看一个 Android 中稍微复杂的视图结构：

```xml
<LinearLayout>
    <RelativeLayout>
        <ImageView/>
        <LinearLayout>
            <TextView/>
            <TextView/>
        </LinearLayout>
    </RelativeLayout>
    <View/>
</LinearLayout>
```

上面的 XML 代码描述了一个更加复杂的视图树，这里通过一张图更清晰地展示该视图表示的结构：

![Android-View-Tree](images/view/Android-View-Tree.jpg)

我们可以发现，Android 的视图其实分为两类：

+ 一类是不能有子节点的视图，比如 `View`、`ImageView` 和 `TextView` 等；
+ 另一类是可以有子节点的视图，比如 `LinearLayout` 和 `RelativeLayout` 等；

在 Android 中，这两类的前者都是 `View` 的子类，也就是视图；后者是 `ViewGroup` 的子类，它主要充当视图的容器，与它的子节点以树形的结构形成了一个层次结构。

这种分离视图和容器的方式很好的分离了职责，将管理和控制子视图的功能划分给了 `ViewGroup`，将显示内容的职责抛给了 `View` 对各个功能进行了合理的拆分。

子视图的布局属性只有在父视图为特定 `ViewGroup` 时才会激活，否则就会忽略在 XML 中声明的属性。

#### 混合的结构与样式

在使用 XML 或者类 XML 的这种文本来描述视图层的内容时，总会遇到一种无法避免的争论：样式到底应该放在哪里？上面的例子显然说明了 Android 对于这一问题的选择，也就是将样式放在 XML 结构中。

这一章节中并不会讨论样式到底应该放在哪里这一问题，我们会在后面的章节中具体讨论，将样式放在 XML 结构中和单独使用各自的优缺点。

### Web 前端

随着 Web 前端应用变得越来越复杂，在目前的大多数 Web 前端项目的实践中，我们已经会使用前后端分离方式开发 Web 应用，而 Web 前端也同时包含 Model、View 以及 Controller 三部分，不再通过服务端直接生成前端的 HTML 代码了。

![html-css](images/view/html-css.jpg)

现在最流行的 Web 前端框架有三个，分别是 React、Vue 和 Angular。不过，这篇文章会以最根本的 HTML 和 CSS 为例，简单介绍 Web 前端中的视图层是如何工作的。

```html
<div>
  <h1 class="text-center">Header</h1>
</div>

.text-center {
  text-align: center;
}
```

在 HTML 中其实并没有视图和容器这种概念的划分，绝大多数的元素节点都可以包含子节点，只有少数的无内容标签，比如说 `br`、`hr`、`img`、`input`、`link` 以及 `meta` 才不会**解析**自己的子节点。

#### 分离的结构与样式

与 Android 在定义视图时，使用混合的结构与样式不同，Web 前端在视图层中，采用 HTML 与 CSS 分离，即结构与样式分离的方式进行设计；虽然在 HTML 中，我们也可以使用 `style` 将 CSS 代码写在视图层的结构中，不过在一般情况下，我们并不会这么做。

```html
<body style="background-color:powderblue;">
</body>
```

### 结构与样式

在这一章节中，我们会对结构与样式组织方式之间的优劣进行简单的讨论。

Android 和 Web 前端使用不同的方式对视图层的结构和样式进行组织，前者使用混合的方式，后者使用分离的结构和样式。

相比于分离的组织方式，混合的组织方式有以下的几个优点：

+ 不需要实现元素选择器，降低视图层解析器实现的复杂性；
+ 元素的样式是内联的，对于元素的样式的定义一目了然，不需要考虑样式的继承等复杂特性；

分离的组织方式却正相反：

+ 元素选择器的实现，增加了 CSS 样式代码的复用性，不需要多次定义相同的样式；
+ 将 CSS 代码从结构中抽离能够增强 HTML 的可读性，可以非常清晰、直观的了解 HTML 的层级结构；

对于结构与样式，不同的组织方式能够带来不同的收益，这也是在设计视图层时需要考虑的事情，我们没有办法在使用一种组织方式时获得两种方式的优点，只能尽可能权衡利弊，选择最合适的方法。

### 后端的视图层

这一章节将会研究一下后端视图层的设计，不过在真正开始分析其视图层设计之前，我们需要考虑一个问题，后端的视图层到底是什么？它有客户端或者 Web 前端中的**用于展示内容**视图层么？

这其实是一个比较难以回答的问题，不过严格意义上的后端是没有用于展示内容的视图层的，也就是为客户端提供 API 接口的后端，它们的视图层，其实就是用于返回 JSON 的模板。

```ruby
json.extract! user, :id, :mobile, :nickname, :gender, :created_at, :updated_at
json.url user_url user, format: :json
```

在 Ruby on Rails 中一般都是类似于上面的 jbuilder 代码。拥有视图层的后端应用大多都是使用了模板引擎技术，直接为 HTTP 请求返回渲染之后的 HTML 和 CSS 等前端代码。

总而言是，使用了模板引擎的后端应用其实是混合了 Web 前端和后端，整个服务的视图层其实就是 Web 前端的代码；而现在的大多数 Web 应用，由于遵循了前后端分离的设计，两者之间的通信都使用约定好的 API 接口，所以后端的视图层其实就是单纯的用于渲染 JSON 的代码，比如 Rails 中的 jbuilder。

## 理想中的视图层

iOS 中理想的视图层需要解决两个最关键的问题：

1. 细分 `UIView` 的职责，将其分为视图和容器两类，前者负责展示内容，后者负责对子视图进行布局；
2. 去除整个视图层对于 `frame` 属性的依赖，不对外提供 `frame` 接口，每个视图只能知道自己的大小；

解决上述两个问题的办法就是封装原有的 `UIView` 类，使用组合模式为外界提供合适的接口。

![Node-Delegate-UIVie](images/view/Node-Delegate-UIView.jpg)

### 细分 UIView 的职责

`Node` 会作为 `UIView` 的代理，同时也作为整个视图层新的根类，它将屏蔽掉外界与 `UIView` 层级操作的有关方法，比如说：`-addSubview:` 等，同时，它也会屏蔽掉 `frame` 属性，这样每一个 `Node` 类的实例就只能设置自己的大小了。

```swift
public class Node: Buildable {
    public typealias Element = Node
    public let view: UIView = UIView()
    
    @discardableResult 
    public func size(_ size: CGSize) -> Element {
        view.size = size
        return self
    }    
}
```

上面的代码简单说明了这一设计的实现原理，我们可以理解为 `Node` 作为 `UIView` 的透明代理，它不提供任何与视图层级相关的方法以及 `frame` 属性。

![Node-Delegate-Filte](images/view/Node-Delegate-Filter.jpg)

### 容器的实现

除了添加一个用于展示内容的 `Node` 类，我们还需要一个 `Container` 的概念，提供为管理子视图的 API 和方法，在这里，我们添加了一个空的 `Container` 协议：

```swift
public protocol Container { }
```

利用这个协议，我们构建一个 iOS 中最简单的容器 `AbsoluteContainer`，内部使用 `frame` 对子视图进行布局，它应该为外界提供添加子视图的接口，在这里就是 `build(closure:)` 方法：

```swift
public class AbsoluteContainer: Node, Container {
    typealias Element = AbsoluteContainer
    @discardableResult 
    public func build(closure: () -> Node) -> Relation<AbsoluteContainer> {
        let node = closure()
        view.addSubview(node.view)
        return Relation<AbsoluteContainer>(container: self, node: node)
    }
}
```

该方法会在调用后返回一个 `Relation` 对象，这主要是因为在这种设计下的 `origin` 或者 `center` 等属性不再是 `Node` 的一个接口，它应该是 `Node` 节点出现在 `AbsoluteContainer` 时的产物，也就是说，只有在这两者同时出现时，才可以使用这些属性更新 `Node` 节点的位置：

```swift
public class Relation<Container> {
    public let container: Container
    public let node: Node

    public init(container: Container, node: Node) {
        self.container = container
        self.node = node
    }
}

public extension Relation where Container == AbsoluteContainer {
    @discardableResult 
    public func origin(_ origin: CGPoint) -> Relation {
        node.view.origin = origin
        return self
    }
}
```

这样就完成了对于 `UIView` 中视图层级和位置功能的剥离，同时使用透明代理以及 `Relation` 为 `Node` 提供其他用于设置视图位置的接口。

> 这一章节中的代码都来自于 [Mineral](https://github.com/Draveness/Mineral)，如果对代码有兴趣的读者，可以下载自行查看。

## 总结

Cocoa Touch 中的 UIKit 对视图层的设计在一开始确实是没有问题的，主要原因是在 iOS 早期的布局方式并不复杂，只有单一的 `frame` 布局，而这种方式也恰好能够满足整个平台对于 iOS 应用开发的需要，但是随着屏幕尺寸的增多，苹果逐渐引入的其它布局方式与原有的体系发生了一些冲突，导致在开发时可能遇到奇怪的问题，而这也是本文想要解决的，将原有属于 `UIView` 的职责抽离出来，提供更合理的抽象。

## References

+ [从 Auto Layout 的布局算法谈性能](http://draveness.me/layout-performance.html)
+ [Understanding Auto Layout](https://developer.apple.com/library/content/documentation/UserExperience/Conceptual/AutolayoutPG/index.html#//apple_ref/doc/uid/TP40010853-CH7-SW1)
+ [Size-Class-Specific Layout](https://developer.apple.com/library/content/documentation/UserExperience/Conceptual/AutolayoutPG/Size-ClassSpecificLayout.html)
+ [translatesAutoresizingMaskIntoConstraints](https://developer.apple.com/reference/uikit/uiview/1622572-translatesautoresizingmaskintoco)

