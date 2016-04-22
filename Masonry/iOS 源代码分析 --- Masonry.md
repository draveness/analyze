# iOS 源代码分析 --- Masonry

[Masonry](https://github.com/SnapKit/Masonry) 是 Objective-C 中用于自动布局的第三方框架, 我们一般使用它来代替冗长, 繁琐的 AutoLayout 代码. 

Masonry 的使用还是很简洁的:

```objectivec
[button mas_makeConstraints:^(MASConstraintMaker *make) {
	make.centerX.equalTo(self.view);
	make.top.equalTo(self.view).with.offset(40);
	make.width.equalTo(@185);
	make.height.equalTo(@38);
}];
```

## 从 mas_makeConstraints: 开始

其中最常用的方法就是 

```objectivec
// View+MASAdditions.h

- (NSArray *)mas_makeConstraints:(void(^)(MASConstraintMaker *make))block;
```

同样, 也有用于**更新和重新构建**约束的分类方法:

```objectivec
// View+MASAdditions.h

- (NSArray *)mas_updateConstraints:(void(^)(MASConstraintMaker *make))block;
- (NSArray *)mas_remakeConstraints:(void(^)(MASConstraintMaker *make))block;
```

## Constraint Maker Block

我们以 `mas_makeConstraints:` 方法为入口来分析一下 Masonry 以及类似的框架(SnapKit)是如何工作的. `mas_makeConstraints:` 方法位于 `UIView` 的分类 `MASAdditions` 中.

> 	Provides constraint maker block and convience methods for creating MASViewAttribute which are view + NSLayoutAttribute pairs.

这个分类为我们提供一种非常便捷的方法来配置 `MASConstraintMaker`, 并为视图添加 `mas_left` `mas_right` 等属性.

方法的实现如下:

```objectivec
// View+MASAdditions.m

- (NSArray *)mas_makeConstraints:(void(^)(MASConstraintMaker *))block {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    MASConstraintMaker *constraintMaker = [[MASConstraintMaker alloc] initWithView:self];
    block(constraintMaker);
    return [constraintMaker install];
}
```

因为 Masonry 是封装的苹果的 AutoLayout 框架, 所以我们要在为视图添加约束前将 `translatesAutoresizingMaskIntoConstraints` 属性设置为 `NO`. 如果这个属性没有被正确设置, 那么视图的约束不会被成功添加.

在设置 `translatesAutoresizingMaskIntoConstraints` 属性之后, 

* 我们会初始化一个 `MASConstraintMaker` 的实例.
* 然后将 maker 传入 block 配置其属性.
* 最后调用 maker 的 `install` 方法为视图添加约束.

## MASConstraintMaker

`MASConstraintMaker` 为我们提供了工厂方法来创建 `MASConstraint`. 所有的约束都会被收集直到它们最后调用 `install` 方法添加到视图上.

> Provides factory methods for creating MASConstraints. Constraints are collected until they are ready to be installed

在初始化 `MASConstraintMaker` 的实例时, 它会**持有一个对应 view 的弱引用**, 并初始化一个  `constraints` 的空可变数组用来之后配置属性时持有所有的约束.

```objectivec
// MASConstraintMaker.m

- (id)initWithView:(MAS_VIEW *)view {
    self = [super init];
    if (!self) return nil;
    
    self.view = view;
    self.constraints = NSMutableArray.new;
    
    return self;
}
```

这里的 `MAS_VIEW` 是一个宏, 是 `UIView` 的 alias.

```c
// MASUtilities.h

#define MAS_VIEW UIView
```

## Setup MASConstraintMaker

在调用 `block(constraintMaker)` 时, 实际上是对 `constraintMaker` 的配置.

```objectivec
make.centerX.equalTo(self.view);
make.top.equalTo(self.view).with.offset(40);
make.width.equalTo(@185);
make.height.equalTo(@38);
```

### make.left

访问 `make` 的 `left` `right` `top` `bottom`  等属性时, 会调用 `constraint:addConstraintWithLayoutAttribute:` 方法.

```objectivec
// MASViewConstraint.m

- (MASConstraint *)left {
    return [self addConstraintWithLayoutAttribute:NSLayoutAttributeLeft];
}

- (MASConstraint *)addConstraintWithLayoutAttribute:(NSLayoutAttribute)layoutAttribute {
    return [self constraint:nil addConstraintWithLayoutAttribute:layoutAttribute];
}

- (MASConstraint *)constraint:(MASConstraint *)constraint addConstraintWithLayoutAttribute:(NSLayoutAttribute)layoutAttribute {
    MASViewAttribute *viewAttribute = [[MASViewAttribute alloc] initWithView:self.view layoutAttribute:layoutAttribute];
    MASViewConstraint *newConstraint = [[MASViewConstraint alloc] initWithFirstViewAttribute:viewAttribute];
    if ([constraint isKindOfClass:MASViewConstraint.class]) { ... }
    if (!constraint) {
        newConstraint.delegate = self;
        [self.constraints addObject:newConstraint];
    }
    return newConstraint;
}
```

在调用链上最终会达到 `constraint:addConstraintWithLayoutAttribute:` 这一方法, 在这里省略了一些暂时不需要了解的问题. 因为在这个类中传入该方法的第一个参数一直为 `nil`, 所以这里省略的代码不会执行.

这部分代码会先以布局属性 `left` 和视图本身初始化一个 `MASViewAttribute` 的实例, 之后使用 `MASViewAttribute` 的实例初始化一个 `constraint` 并设置它的代理, 加入数组, 然后返回.

这些工作就是你在输入 `make.left` 进行的全部工作, 它会返回一个 `MASConstraint`, 用于之后的继续配置.

### make.left.equalTo(@80)

在 `make.left` 返回 `MASConstraint` 之后, 我们会继续在这个链式的语法中调用下一个方法来指定约束的关系.

```objectivec
// MASConstraint.h

- (MASConstraint * (^)(id attr))equalTo;
- (MASConstraint * (^)(id attr))greaterThanOrEqualTo;
- (MASConstraint * (^)(id attr))lessThanOrEqualTo;
```

这三个方法是在 `MASViewConstraint` 的父类, `MASConstraint` 中定义的.

`MASConstraint` 是一个抽象类, 其中有很多的方法都**必须在子类中覆写**的. Masonry 中有两个 `MASConstraint` 的子类, 分别是 `MASViewConstraint` 和 `MASCompositeConstraint`. 后者实际上是一些**约束的集合**. 这么设计的原因我们会在 post 的最后解释.

先来看一下这三个方法是怎么实现的:

```objectivec
// MASConstraint.m

- (MASConstraint * (^)(id))equalTo {
    return ^id(id attribute) {
        return self.equalToWithRelation(attribute, NSLayoutRelationEqual);
    };
}
```

该方法会导致 `self.equalToWithRelation` 的执行, 而这个方法是定义在子类中的, 因为父类作为抽象类没有提供这个方法的具体实现.

```objectivec
// MASConstraint.m

- (MASConstraint * (^)(id, NSLayoutRelation))equalToWithRelation { MASMethodNotImplemented(); }
```

`MASMethodNotImplemented` 也是一个宏定义, 用于在**子类未继承这个方法**或者**直接使用这个类**时抛出异常.

```c
// MASConstraint.m

#define MASMethodNotImplemented() \
    @throw [NSException exceptionWithName:NSInternalInconsistencyException \
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass.", NSStringFromSelector(_cmd)] \
                                 userInfo:nil]

```

因为我们为 `equalTo` 提供了参数 `attribute` 和布局关系 `NSLayoutRelationEqual`, 这两个参数会传递到 `equalToWithRelation` 中, 设置 `constraint` 的布局关系和 `secondViewAttribute` 属性, 为即将 maker 的 `install` 做准备.

```objectivec
// MASViewConstraint.m

- (MASConstraint * (^)(id, NSLayoutRelation))equalToWithRelation {
    return ^id(id attribute, NSLayoutRelation relation) {
        if ([attribute isKindOfClass:NSArray.class]) { ... } 
        else {
            ...
            self.layoutRelation = relation;
            self.secondViewAttribute = attribute;
            return self;
        }
    };
}
```

我们不得不提一下 `setSecondViewAttribute:` 方法, 它并不只是一个简单的 setter 方法, 它会根据你传入的值的种类赋值.

```objectivec
// MASConstraintMaker.m

- (void)setSecondViewAttribute:(id)secondViewAttribute {
    if ([secondViewAttribute isKindOfClass:NSValue.class]) {
        [self setLayoutConstantWithValue:secondViewAttribute];
    } else if ([secondViewAttribute isKindOfClass:MAS_VIEW.class]) {
        _secondViewAttribute = [[MASViewAttribute alloc] initWithView:secondViewAttribute layoutAttribute:self.firstViewAttribute.layoutAttribute];
    } else if ([secondViewAttribute isKindOfClass:MASViewAttribute.class]) {
        _secondViewAttribute = secondViewAttribute;
    } else {
        NSAssert(NO, @"attempting to add unsupported attribute: %@", secondViewAttribute);
    }
}
```

第一种情况对应的就是:

```objectivec
make.left.equalTo(@40);
```

传入 `NSValue` 的时, 会直接设置 `constraint` 的 `offset`, `centerOffset`, `sizeOffset`, 或者 `insets`

第二种情况一般会直接传入一个视图:

```objectivec
make.left.equalTo(view);
```

这时, 就会初始化一个 `layoutAttribute` 属性与 `firstViewArribute` 相同的 `MASViewAttribute`, 上面的代码就会使视图与 `view` 左对齐.

第三种情况会传入一个视图的 `MASViewAttribute`:

```objectivec
make.left.equalTo(view.mas_right);
```

使用这种写法时, 一般是因为约束的方向不同. 这行代码会使视图的左侧与 `view` 的右侧对齐.

到这里我们就基本完成了对**一个**约束的配置, 接下来可以使用相同的语法完成对一个视图上所有约束进行配置, 然后进入了最后一个环节.

## Install MASConstraintMaker

我们会在 `mas_makeConstraints:` 方法的最后调用 `[constraintMaker install]` 方法来安装所有存储在 `self.constraints` 数组中的所有约束.

```objectivec
// MASConstraintMaker.m

- (NSArray *)install {
    if (self.removeExisting) {
        NSArray *installedConstraints = [MASViewConstraint installedConstraintsForView:self.view];
        for (MASConstraint *constraint in installedConstraints) {
            [constraint uninstall];
        }
    }
    NSArray *constraints = self.constraints.copy;
    for (MASConstraint *constraint in constraints) {
        constraint.updateExisting = self.updateExisting;
        [constraint install];
    }
    [self.constraints removeAllObjects];
    return constraints;
}
```

在这个方法会先判断当前的视图的约束是否应该要被 `uninstall`, 如果我们在最开始调用 `mas_remakeConstraints:` 方法时, 视图中原来的约束就会全部被 `uninstall`.

然后就会遍历 `constraints` 数组, 发送 `install` 消息.

### MASViewConstraint install

MASViewConstraint 的 `install` 方法就是最后为当前视图添加约束的最后的方法, 首先这个方法会先获取即将用于初始化 `NSLayoutConstraint` 的子类的几个属性.

```objectivec
// MASViewConstraint.m

MAS_VIEW *firstLayoutItem = self.firstViewAttribute.view;
NSLayoutAttribute firstLayoutAttribute = self.firstViewAttribute.layoutAttribute;
MAS_VIEW *secondLayoutItem = self.secondViewAttribute.view;
NSLayoutAttribute secondLayoutAttribute = self.secondViewAttribute.layoutAttribute;
```

Masonry 之后会判断当前即将添加的约束是否是 size 类型的约束

```objectivec
// MASViewConstraint.m

if (!self.firstViewAttribute.isSizeAttribute && !self.secondViewAttribute) {
   secondLayoutItem = firstLayoutItem.superview;
   secondLayoutAttribute = firstLayoutAttribute;
}
```

如果不是 size 类型并且没有提供第二个 `viewAttribute`, (e.g. `make.left.equalTo(@10);`) 会自动将约束添加到 `superview` 上. 它等价于:

```objectivec
make.left.equalTo(superView.mas_left).with.offset(10);
```

然后就会初始化 `NSLayoutConstraint` 的子类 `MASLayoutConstraint`:

```objectivec
// MASViewConstraint.m

MASLayoutConstraint *layoutConstraint
   = [MASLayoutConstraint constraintWithItem:firstLayoutItem
                                   attribute:firstLayoutAttribute
                                   relatedBy:self.layoutRelation
                                      toItem:secondLayoutItem
                                   attribute:secondLayoutAttribute
                                  multiplier:self.layoutMultiplier
                                    constant:self.layoutConstant];
layoutConstraint.priority = self.layoutPriority;                                    
```

接下来它会寻找 `firstLayoutItem` 和 `secondLayoutItem` 两个视图的公共 `superview`, 相当于求两个数的最小公倍数. 

```objectivec
// View+MASAdditions.m

- (instancetype)mas_closestCommonSuperview:(MAS_VIEW *)view {
    MAS_VIEW *closestCommonSuperview = nil;

    MAS_VIEW *secondViewSuperview = view;
    while (!closestCommonSuperview && secondViewSuperview) {
        MAS_VIEW *firstViewSuperview = self;
        while (!closestCommonSuperview && firstViewSuperview) {
            if (secondViewSuperview == firstViewSuperview) {
                closestCommonSuperview = secondViewSuperview;
            }
            firstViewSuperview = firstViewSuperview.superview;
        }
        secondViewSuperview = secondViewSuperview.superview;
    }
    return closestCommonSuperview;
}
```

如果需要升级当前的约束就会获取原有的约束, 并替换为新的约束, 这样就不需要再次为 `view` 安装约束.

```objectivec
// MASViewConstraint.m

MASLayoutConstraint *existingConstraint = nil;
if (self.updateExisting) {
   existingConstraint = [self layoutConstraintSimilarTo:layoutConstraint];
}
if (existingConstraint) {
   // just update the constant
   existingConstraint.constant = layoutConstraint.constant;
   self.layoutConstraint = existingConstraint;
} else {
   [self.installedView addConstraint:layoutConstraint];
   self.layoutConstraint = layoutConstraint;
}
    
[firstLayoutItem.mas_installedConstraints addObject:self];
```

如果原来的 `view` 中不存在可以升级的约束, 或者没有调用 `mas_updateConstraint:` 方法, 那么就会在上一步寻找到的 `installedView` 上面添加约束. 

```objectivec
[self.installedView addConstraint:layoutConstraint];
```

## 其他问题

到现在为止整个 Masonry 为视图添加约束的过程就已经完成了, 然而我们还有一些待解决的其它问题.

###  make.left.equal(view).with.offset(30)

我们在前面的讨论中已经讨论了这个链式语法的前半部分, 但是在使用中也会"延长"这个链式语句, 比如添加 `with` `offset`.

其实在 Masonry 中使用 `with` 并不是必须的, 它的作用仅仅是使代码更加的易读.

> Optional semantic property which has no effect but improves the readability of constraint

```objectivec
// MASConstraint.m
- (MASConstraint *)with {
    return self;
}

- (MASConstraint *)and {
    return self;
}
```

与 `with` 有着相同作用的还有 `and`, 这两个方法都会直接返回 `MASConstraint`, 方法本身不做任何的修改.

而 `offset` 方法其实是修改 `layoutConstraint` 中的常量, 因为 `self.layoutConstant` 在初始化时会被设置为 0, 我们可以通过修改 `offset` 属性来改变它.

```objectivec
// MASViewConstraint.m

- (void)setOffset:(CGFloat)offset {
    self.layoutConstant = offset;
}
```

### MASCompositeConstraint

`MASCompositeConstraint` 是一些 `MASConstraint` 的集合, 它能够提供一种更加便捷的方法同时为一个视图来添加多个约束.

> A group of MASConstraint objects

通过 `make` 直接调用 `edges` `size` `center` 时, 就会产生一个 `MASCompositeConstraint` 的实例, 而这个实例会初始化所有对应的单独的约束.

```objectivec
// MASConstraintMaker.m

- (MASConstraint *)edges {
    return [self addConstraintWithAttributes:MASAttributeTop | MASAttributeLeft | MASAttributeRight | MASAttributeBottom];
}

- (MASConstraint *)size {
    return [self addConstraintWithAttributes:MASAttributeWidth | MASAttributeHeight];
}

- (MASConstraint *)center {
    return [self addConstraintWithAttributes:MASAttributeCenterX | MASAttributeCenterY];
}
```

这些属性都会调用 `addConstraintWithAttributes:` 方法, 生成多个属于 `MASCompositeConstraint` 的实例.

```objectivec
// MASConstraintMaker.m

NSMutableArray *children = [NSMutableArray arrayWithCapacity:attributes.count];
    
for (MASViewAttribute *a in attributes) {
   [children addObject:[[MASViewConstraint alloc] initWithFirstViewAttribute:a]];
}
    
MASCompositeConstraint *constraint = [[MASCompositeConstraint alloc] initWithChildren:children];
constraint.delegate = self;
[self.constraints addObject:constraint];
return constraint;
```

### mas_equalTo

Masonry 中还有一个类似与 magic 的宏, 这个宏将 C 和 Objective-C 语言中的一些基本数据结构比如说 `double` `CGPoint` `CGSize` 这些值用 `NSValue` 进行包装.

这是一种非常简洁的使用方式, 如果你对这个非常感兴趣, 可以看一下 `MASUtilities.h` 中的源代码, 在这里就不对这个做出解释了.

## Masonry 如何为视图添加约束(面试回答)

Masonry 与其它的第三方开源框架一样选择了使用分类的方式为 UIKit 添加一个方法 `mas_makeConstraint`, 这个方法接受了一个 block, 这个 block 有一个 `MASConstraintMaker` 类型的参数, 这个 maker 会持有一个**约束的数组**, 这里保存着所有将被加入到视图中的约束.

我们通过链式的语法配置 maker, 设置它的 `left` `right` 等属性, 比如说 `make.left.equalTo(view)`, 其实这个 `left` `equalTo` 还有像 `with` `offset` 之类的方法都会返回一个 `MASConstraint` 的实例, 所以在这里才可以用类似 Ruby 中链式的语法. 

在配置结束后, 首先会调用 maker 的 `install` 方法, 而这个 maker 的 `install` 方法会遍历其持有的约束数组, 对其中的每一个约束发送 `install` 消息. 在这里就会使用到在上一步中配置的属性, 初始化 `NSLayoutConstraint` 的子类 `MASLayoutConstraint` 并添加到合适的视图上.

视图的选择会通过调用一个方法 `mas_closestCommonSuperview:` 来返回两个视图的**最近公共父视图**.

## 总结

虽然 Masonry 这个框架中的代码并不是非常的多, 只有 1,2 万行的代码, 但是感觉这个项目阅读起来十分的困难, 没有 SDWebImage 清晰, 因为代码中类的属性非常的多, 而且有很多相似的属性会干扰我们对这个项目的阅读, 整个框架运用了大量的 block 语法进行回调. 

虽然代码十分整洁不过我觉得却降低了可读性, 但是还是那句话, 把简洁留给别人复杂留给自己, 只要为开发者提供简洁的接口就可以了.

