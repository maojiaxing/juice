# Jai tagged union / sum type 表达力研究（Stage_State）

> 研究问题：Jai（beta 0.2.009 / 0.2.9）能否表达带异构 payload 的 tagged union（sum type），供 lifecycle hook 安全访问 `Stage_State`？原生 `union` / `Any` / 手写 tag + `*void` / 共享 typed records 四种候选的语法、读取、样板、类型安全与生成代码代价如何，应推荐哪一种？
> 日期：2026-10-22 | 环境：Jai beta 0.2.009（2025-02-06），Windows 11 + Git Bash，编译器 `C:/Users/maojiaxing/DevTools/jai/bin/jai.exe`
> 证据标注：【实验】= 本机用该编译器编译并运行验证（探针源码见各节，临时目录已清理） | 【源码】= 发行版/本仓库源码逐行阅读 | 【官方文档】= 发行版 `how_to/`、模块注释原文 | 【推断】= 基于事实的推理，非直接证据
> 相关票：[063](../implementation/tickets/063-jai-tagged-union.md)（本票）、[065](../implementation/tickets/065-stage-state-tagged-union.md)（消费方）

## 结论摘要

| 问题 | 判定 |
| --- | --- |
| Jai 有原生 sum type / tagged union 吗？ | 没有【源码】。语言无 `sum` / `tagged` / ADT 关键字；`union` 是 C 式无标签联合；`Any` 是 16 字节的 boxed **非持有**引用（`*Type_Info` + `*void`），不是 sum type |
| 原生 `union` 的运行期 tag / 模式匹配 | 无【实验+源码】。成员全部 offset 0；`Type_Info.textual_flags = UNION` 但不记录 active member；`if case` 只能匹配值（enum / `Type`），不能匹配 union 分支；官方 Print 明确拒绝打印 union（"we don't know what is actually in there"） |
| 官方承认的 tagged union 表达方式 | 用户级模式，有两个一手先例：① `modules/Tagged_Union.jai`（`tag: Type` + inline bytes + `set`/`isa`，demo 级）；② `how_to/008`、`how_to/120` 的 **Type tag + `#as using base` 记录层次**，官方用同一形状演示运行期动态派发 |
| 推荐给 `Stage_State` 的形状 | **Type tag + `#as using base` 的共享 typed records**：`Stage_State { kind: Type; }` 作基记录，各 stage 记录首字段 `#as using base: Stage_State` 并由构造器自盖章 `base.kind = <自身类型>`；context 存 `*Stage_State`，hook 先比对 `kind` 再做一次 `cast` |
| 与现状 `*void` 槽的关系 | 槽类型从 `*void` 改为 `*Stage_State`；构造点仍是 `lctx.views = *tstage`（隐式 `#as` 上转，**零改动**）；读取点保留 `cast(*Test_Transpile_Stage) ctx.views`（**零改动**），建议前置一次 `kind` 检查；hook 签名 `(ctx: *Lifecycle_Context, state: *void) -> bool` 不变 |
| 生成代码 / 闭包影响 | Jai 无闭包【官方文档】，hook = 非多态过程指针；所有候选都无堆分配。inline union / `Any` / tag+`*void` 会放大 `Lifecycle_Context` 并随 context 复制拷贝 payload；Type-base 只占一个 8 字节指针，payload 留在 host-owned 存储 |
| 落选的候选 | 原生 union（无 tag、读写不设防）、`Any`（非持有、值/指针 boxing 语义陷阱、生命周期无检查）、tag+`*void`（tag 与 payload 两处写、可 desync、违反 otter `*void` 纪律）；官方 `Tagged_Union` 模块可用但为 demo 且 inline 拷贝，不符合 host-owned 现状 |

---

## 1. 语言事实（一手）

### 1.1 版本

`CHANGELOG.txt:1`：`Version: beta 0.2.009, 6 February 2025`。本研究的全部实验都跑在该发行版的 `bin/jai.exe` 上【源码+实验】。

### 1.2 原生 `union`：C 式无标签联合

发行版模块里的 `union` 全部是 C 互操作/位重解释用途，例如：

- `modules/Basic/string_to_float.jai:1009-1012`：`HexDouble :: union { _u64: u64; _float64: float64; }`【源码】
- `modules/Compiler/Compiler.jai:990-995,1021-1031`：`Code_Pointer_Literal_Info` / `Code_Literal` 用 union 重叠存储【源码】
- `modules/X11/module.jai:2103`、`modules/Windows.jai:64`、Vulkan/D3D 绑定等【源码】

语言本身**不提供 active-member tag**。官方 `modules/Tagged_Union.jai:3-8` 的原话【官方文档】：

> This language, like C, has a built-in union type, designated by the keyword 'union'. But, when using a union, you have to know which type is stored inside it, so that you know how to interpret the memory stored in the union. Usually this is done using some kind of enum-based type tag.

`modules/Basic/Print.jai:408`【源码】："Don't try to print unions, since we don't know what is actually in there!"

**实验**（`union_basics.jai`，编译运行通过）：

```jai
U :: union {
    a: s64;
    b: float64;
    c: [16] u8;
}

main :: () {
    u: U;
    print("size_of(U) = %\n", size_of(U));   // 16
    u.a = 42;
    print("u.b reinterpreted = %\n", u.b);   // 0（按 float64 重解释 42 的位模式）
    print("u.c = %\n", u.c);                 // [42, 0, ...]
    ti := type_info(U);
    print("Type_Info flags = %\n", ti.textual_flags);  // UNION
}
```

输出要点：`size_of(U) = 16`；`Type_Info` 的三个成员 `offset_in_bytes` 全为 0；`textual_flags = UNION`；读取非活动成员不报错、不检查，直接重解释内存【实验】。

复制语义：union 是值类型，赋值复制整个 union 存储；含 union 的 struct 复制时同样按字节复制，两个副本独立。实验 `union_copy.jai`：`u.b = [1,2,3]; v := u; v.b[0] = 99;` 后 `u.b = [1,2,3]`、`v.b = [99,2,3]`【实验】。

### 1.3 `Any`：boxed 非持有引用，不是 sum type

`how_to/030_any.jai:55-64`【官方文档】给出定义：

```jai
Any :: struct {
    type : *Type_Info;
    value_pointer : *void;
}
```

关键语义（`how_to/030_any.jai:89-107,159-191`）【官方文档】：

- `x = a` **不复制 payload**；`value_pointer` 指向 `a` 的地址，改 `a` 后 `x` 看到新值。
- `Any` 赋给 `Any` 只复制 `type` + `value_pointer` 两个字段，不重新 boxing。
- 生命周期由调用者负责："if you create an Any pointing to a value on the stack, then return the Any, the value_pointer will be pointing at memory that is no longer valid … for now there are no safeties on this."

**实验**（`any_basics.jai`）【实验】：

```jai
a: Record_A = .{ 7 };
x: Any = a;                                  // 值 -> type = Record_A，指针指向 a
print(x.type == type_info(Record_A));        // true
print(x.value_pointer == *a);                // true
a.value = 99;
print(<<cast(*Record_A) x.value_pointer);    // {99}：看到源变量修改

show(*b);   // 传指针 -> type 是 *Record_B（与 Record_B 是不同的 tag）
```

输出：`size_of(Any) = 16`；`type_info(*Record_B)` 与 `type_info(Record_B)` 是两个不同 tag。第一次探针在未校验 tag 的情况下把 `*Record_B` 的 boxing 按 `Record_B` 值读取，运行时 access violation 崩溃——这正是官方文档"先看 `Any.type` 再决定怎么解释"的原因【实验+官方文档】。

结论：`Any` 的 `type` 字段确实是一个运行期类型 tag，但 `Any` 是**非持有视图**：它不拥有 payload、不复制 payload、不能保证指针寿命，且"存值"与"存指针"得到不同 tag（`Record_B` vs `*Record_B`）。它适合 `print` 这类短寿命泛型读取，不适合作为 host-owned `Stage_State` 的存储。

### 1.4 没有 sum type 语法，也没有 union 模式匹配

- `modules/Jai_Lexer/module.jai:80-122` 的关键字表包含 `KEYWORD_UNION`、`KEYWORD_INTERFACE`，没有 `sum` / `tagged` / `variant` 类型关键字【源码】。
- Jai 文档中的 "variant" 指 `#type,isa` / `#type,distinct` 类型变体（`how_to/180_type_variants.jai`），与代数数据类型无关【官方文档】。
- `if ... == { case ... }` 是唯一的多分支形式（`how_to/027_if_case.jai:47-74`），它匹配的是**值**（enum 成员、`Type` 值、整数等），不是 union 的活动成员；`case;` 是可选的兜底，**不要求穷尽**【官方文档+实验】。

实验 `if_case_no_fallback.jai`【实验】：覆盖全部 enum 成员的 `if case` 不写 `case;` 也能编译运行；只写部分 `Type` case 也能编译运行——漏掉的 tag 静默落空。因此任何 tag 派发都必须自己写兜底并把它变成 ERROR 诊断，不能指望编译器穷尽检查。

官方 `modules/Tagged_Union.jai:26-27` 也明说类型切换宏尚未完成【官方文档】：

> @Incomplete: We haven't yet done some kind of macro for switching on the type.

### 1.5 官方给出的两个用户级 tagged union 先例

#### 先例 A：`modules/Tagged_Union.jai`（demo 模块）

`modules/Tagged_Union.jai:34-71`【源码】：

```jai
Tagged_Union :: struct (value_types: .. Type) {
    tag: Type;
    bytes: [NUM_VALUE_BYTES] u8;
    NUM_VALUE_BYTES : s64 : #run get_biggest_size(value_types);
}

set :: (using u: *Tagged_Union, value: $T) {
    #if DEBUG == true {
        #run {
            found := false;
            for value_types  if it == T { found = true; break; }
            assert(found);
        }
    }
    tag = T;
    pointer := cast(*T) bytes.data;
    <<pointer = value;
}

isa :: (using u: *Tagged_Union, $T: Type) -> *T {
    if tag == T  return cast(*T) bytes.data;
    return null;
}
```

它是**用户级库**，不是语言特性：`tag: Type` 由 `set` 自动盖章，`isa(u, T)` 返回 `*T` 或 null，`DEBUG=true` 时 `set` 在编译期断言 `T` 属于声明时的 `value_types` 列表。

**实验**（`first_party_tagged_union.jai`，`#import "Tagged_Union"(DEBUG=true)`）【实验】：

```jai
Stage_State :: Tagged_Union(Build_Transpile_Stage, Test_Transpile_Stage);

s: Stage_State;
set(*s, b);
p := isa(s, Build_Transpile_Stage);
if p { print("build, source_count = %\n", p.source_count); }
```

输出：`build, source_count = 3`、`test, test_count = 5`、`size_of(Stage_State) = 16`（`Type` 8 + 8 字节 bytes）。把未列入的类型传给 `set` 会在编译期失败：`modules/Tagged_Union.jai:55,13: Assertion failed!`【实验】。

代价与限制：payload 被**按值拷入** inline bytes（host 原有记录的地址失效，后续变更要走 `isa` 指针）；模块注释自标 `@Incomplete`，没有 tag 切换宏；`#module_parameters (DEBUG := false)` 默认关闭编译期成员检查。对"编排器拥有 stage 记录、hook 拿指针原地读写"的 otter 现状是形状错配。

#### 先例 B：Type tag + `#as using base` 记录层次（官方 how_to）

`how_to/008_types.jai:98-149` 用 `Document { type: Type; filename: string; }` 作基记录，`Video_File` / `Audio_File` 以 `#as using base: Document` 开头，`full_report` 在 `doc.type == { case Video_File; cast(*Video_File) doc; ... }` 中动态派发（`:244-257`）【官方文档】。

`how_to/120_polymorphic_structs.jai:340-411` 用同一形状做运行期动态派发【官方文档】：

```jai
Holder_Base :: struct { type: Type; size: s64; }
Holder :: struct ($X: Type) {
    #as using base: Holder_Base;
    base.type = X;
    base.size = size_of(X);
    instance: X;
}

inspect :: (base: *Holder_Base) {
    if base.type == {
      case u8;     casted := cast(*Holder(u8)) base;     ...
      case string; casted := cast(*Holder(string)) base; ...
      case;        print("Error: Unknown type in Holder_Base!\n");
    }
}
```

`how_to/008_types.jai:299-302` 还给出 Type tag 的取舍【官方文档】：

> One disadvantage to tagging structs with Type instead of an enum is that with an enum you can control size easily … A Type right now is 8 bytes … You could automate enum generation from Types using compile-time execution.

即：**Type tag = 开放、自解释、8 字节；enum tag = 紧凑、封闭、需手工维护映射**。两者都是合法的用户级 tagged union 表达。

### 1.6 闭包与过程指针

`how_to/080_scopes.jai:77-80`【官方文档】：

> (There are currently no closures or other forms of automatic local variable capture in the language. It's vaguely on the roadmap to add closures, but … )

因此 lifecycle 的"无闭包、所有通道都是 context 里的显式数据"（`src/lifecycle.jai:32-36`）不是妥协，而是语言现状；hook 只能是普通（非多态）过程指针。`how_to/120_polymorphic_structs.jai:401-411` 证明非多态过程可以赋给运行期变量、多态过程不行【官方文档】：

```jai
a1 := print_type_and_size;  // ok
a2 := inspect;              // ok
// a3 := set;               // Error: This declaration has a polymorphic type...
```

所以 hook 签名不能写成 `#type (ctx, state: *$T) -> bool`；任何 payload 访问都必须经过运行期 tag + cast。这是所有候选的共同前提。

---

## 2. 候选形状

以下 A-E 均在 beta 0.2.009 上编译运行验证。对比维度：语法、hook 读取、样板、类型安全、复制/生命周期、生成代码。

### 候选 A：原生 `union` + 手写 enum tag（inline）

```jai
Stage_Kind :: enum u8 { NONE; BUILD_TRANSPILE; TEST_TRANSPILE; }

Stage_State :: struct {
    kind: Stage_Kind;
    payload: union {
        build_transpile: Build_Transpile_Stage;
        test_transpile:  Test_Transpile_Stage;
    }
}

// 设置点：两个字段分别写，可 desync
s.kind = .BUILD_TRANSPILE;
s.payload.build_transpile = .{ source_count = 3, label = "build" };

// hook 读取
if s.kind == {
    case .BUILD_TRANSPILE;
        print("%\n", s.payload.build_transpile.source_count);
    case .TEST_TRANSPILE;
        print("%\n", s.payload.test_transpile.test_count);
    case;
        // 兜底
}
```

**实验**（`tagged_inline.jai`）输出：`size_of(Stage_State) = 32`（payload 最大成员 `s64 + string` = 24，加 enum + padding）；`s.payload.test_transpile` 在 `kind = .BUILD_TRANSPILE` 时仍可读（打印 `{3}`）【实验】。

- 语法：需要 enum + union 两层声明。
- 读取：一次 tag 分支 + 零 cast（直接成员访问）。
- 样板：设置点两次写；新增 payload 类型要同时改 enum 与 union。
- 类型安全：tag 与 payload 分离，编译器不校验配对；读写错成员静默重解释。
- 复制：值复制整个 union；context 若按值复制会复制 payload。
- 生成代码：inline 存储，context 大小 = max(payload) + tag。

### 候选 B：`Any` payload

```jai
Stage_State :: struct {
    payload: Any;   // payload.type 就是运行期 tag
}

// 设置：注意存值/存指针 tag 不同
state.payload = *record;   // tag = *Build_Transpile_Stage
// 或 state.payload = record;  // tag = Build_Transpile_Stage，但需 record 地址稳定

// 读取
if state.payload.type == type_info(Build_Transpile_Stage) {
    b := cast(*Build_Transpile_Stage) state.payload.value_pointer;
    ...
}
```

**实验**（`any_basics.jai`）：`size_of(Any) = 16`；`Any` 存值指向源变量并随源变量变化；存指针与存值得到不同 tag；未校验 tag 的错误读取导致运行时崩溃【实验】。

- 语法：最少（赋值即 boxing）。
- 读取：一次 `type` 比较 + 一次 `*void` cast。
- 样板：设置一行；但必须保证被 box 的对象地址在 context 生命周期内稳定（临时值/函数返回值会悬垂）。
- 类型安全：tag 是 `*Type_Info`，不是封闭集合；值/指针 boxing 语义是隐蔽陷阱；cast 前不检查会崩溃。
- 复制：`Any` 复制两个字段，payload 共享（非持有）。
- 生成代码：16 字节 inline；无堆分配；payload 寿命不受控。

### 候选 C：手写 tag + `*void` payload（现状的泛化）

```jai
Stage_Kind :: enum u8 { NONE; BUILD_TRANSPILE; TEST_TRANSPILE; }

Stage_State :: struct {
    kind:    Stage_Kind;
    payload: *void;
}

s.kind = .BUILD_TRANSPILE;
s.payload = stage_record;

// hook 读取
if s.kind == .BUILD_TRANSPILE {
    b := cast(*Build_Transpile_Stage) s.payload;
    ...
}
```

**实验**（`tag_void.jai`）：`size_of(Stage_State) = 16`；读取正确；tag 与 payload 两次写，可 desync；payload 寿命由 host 负责【实验】。

- 语法：一个 enum + 一个指针。
- 读取：tag 比较 + 一次 cast。
- 样板：设置两次写；无类型化的 context 字段（调用点可读性差）。
- 类型安全：与 A 相同的 desync 风险；`*void` 丢弃类型，违反 otter `CLAUDE.md` 的 "*void 仅在严格必要时" 纪律。
- 复制：16 字节，payload 共享；host-owned。
- 生成代码：最小（16 字节）；无堆分配。

### 候选 D：共享 typed records + `Type` tag + `#as using base`（推荐）

```jai
// 共享模块（如 src/lifecycle.jai，只依赖 Basic）
Stage_State :: struct {
    kind: Type;   // 具体 stage 记录类型，由记录构造器自盖章
}

// 记录留在各自文件，只需嵌入基记录（文件本来就能 import lifecycle）
Build_Transpile_Stage :: struct {
    #as using base: Stage_State;
    base.kind = Build_Transpile_Stage;   // 默认构造与 .{} 字面量都会执行

    prepared: *Juice.Prepared_Workspace;
    pipeline: [] Transpile_Plugin;
    prestep:  *Prestep_Stage;
    entries:  [..] string;
}

// context 槽：类型化，不再是 *void
Lifecycle_Context :: struct {
    stage: Lifecycle_Stage;
    views: *Stage_State;   // 或收敛为单个 state: *Stage_State（065 决定）
    ...
}

// 构造点：隐式 #as 上转，零改动
lctx.views = *tstage;

// hook 读取：先比对 tag，再 cast
build_hook :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    if ctx.views == null || ctx.views.kind != Build_Transpile_Stage {
        array_add(ctx.diagnostics, .{ level = .ERROR, message = "wrong stage state type" });
        return false;
    }
    stage := cast(*Build_Transpile_Stage) ctx.views;
    ...
}
```

**实验**（`base_as.jai`、`base_as_literals.jai`、`base_as_no_init.jai`、`hook_abi.jai`、`miscast.jai`）【实验】：

- `size_of(Stage_State) = 8`；`size_of(Build_Transpile_Stage) = 16`（base 8 + s64 8）；base 在 offset 0。
- 默认构造与 `.{}` / `Type.{}` 字面量都会执行 `base.kind = ...`，构造出的记录天生带正确 tag；`---` 构造会跳过 initializer（实验确认 `kind` 未盖章），因此 stage 记录**禁止用 `---` 构造**。
- `slot: *Stage_State = *b;` 隐式上转成功；`cast(*Build_Transpile_Stage) slot` 下转成功。
- 现有 hook ABI 完全兼容：`ctx.state = *b` + `hook(*ctx, null)` 正常运行，hook 通过 typed 指针原地修改 payload。
- cast 不做运行期校验：故意把 `*Unrelated` cast 成 `*Build_Transpile_Stage` 可以编译运行并读到错误字段（`source_count` 读到 `Unrelated.number`），同时 `kind` 比较仍为 false——所以 **tag 检查必须写在 cast 之前**。
- `Stage_State = derived_value` 只复制 base（payload 丢失）——状态一律按指针传递，不按 base 值传递。

- 语法：基记录 3 行 + 每个变体记录 3 行（`#as using base` + 盖章 + 原有字段）。
- 读取：一次 `kind` 比较 + 一次 cast；tag 就是 payload 类型，无需维护 enum。
- 样板：设置点零额外写（构造器盖章）；新增 stage 记录不改任何中央枚举。
- 类型安全：正常构造不可能 tag/payload desync（tag 由记录自己的 initializer 产生）；唯一残余风险是手工 cast 撒谎，与所有 Jai 方案相同，因此每次读取都先检查 `kind`。
- 复制：context 只存 8 字节指针；payload 在 host-owned 记录里，原地读写。
- 生成代码：context 不随 payload 变大；无堆分配；`Type` tag 会让每个记录类型的 `Type_Info` 进入二进制（`Type` 值即 `*Type_Info`，`how_to/180_type_variants.jai:185-193` 的 re-interpret 可证），7 个阶段记录的成本可忽略；若极端在意二进制体积，可退回 enum tag（见 §3 权衡）。
- 与官方先例一致：`how_to/008_types.jai:98-149,244-257` 与 `how_to/120_polymorphic_structs.jai:340-411` 用的就是这一形状【官方文档】。

### 候选 E：官方 `modules/Tagged_Union.jai` 泛型

见 §1.5 先例 A。`set(*s, value)` + `isa(s, T)` 的 API 最省样板，且 `DEBUG=true` 时 `set` 有编译期成员检查。但它把 payload **按值拷入 inline bytes**：

- 与 otter 现状（编排器构造记录、hook 拿 `*T` 原地修改、`Prestep_Stage` 内有 `[..]` 可增长数组）冲突：`set` 之后原记录与 union 内副本是两个对象，后续所有访问必须走 `isa` 指针。
- 模块自标 `@Incomplete`（无 tag 切换宏）、默认 `DEBUG := false`、属于 demo 而非稳定 API。
- `bytes: [NUM_VALUE_BYTES] u8` 的对齐上限来自 struct 的 8 字节对齐；需要 16 字节对齐的类型不安全（otter 当前 payload 不需要，但这是隐藏限制）。

### 2.6 对比表

| 维度 | A 原生 union + enum | B `Any` | C tag + `*void` | D Type + `#as` base（推荐） | E Tagged_Union 模块 |
| --- | --- | --- | --- | --- | --- |
| 语言级支持 | 原生 union（无 tag） | 原生 `Any`（非持有） | 全手写 | 官方 how_to 模式 | 官方 demo 模块 |
| 运行期 tag | 手写 enum | `*Type_Info`（赋值产生） | 手写 enum | `Type`（构造器自盖章） | `Type`（`set` 盖章） |
| hook 读取 | 分支 + 成员访问 | tag 比较 + cast | tag 比较 + cast | tag 比较 + cast | `isa` 返回 `*T` |
| 设置点样板 | 2 写 | 1 写（有地址寿命约束） | 2 写 | 0 额外写 | 1 次 `set`（拷贝） |
| tag/payload desync | 可能 | 不会（但值/指针 tag 不同） | 可能 | 正常构造不会 | 不会 |
| 未检查误读的后果 | 静默重解释 | 运行时崩溃 | 静默重解释/崩溃 | 静默误读（必须先查 kind） | `isa` 返回 null（安全） |
| payload 存储 | inline 拷贝 | 非持有指针 | 指针 | 指针（host-owned） | inline 拷贝 |
| context 增量 | max(payload)+tag | 16B | 16B | 8B/槽 | tag+max(payload) |
| 复制语义 | 值复制 payload | 共享 payload | 共享 payload | 共享 payload（指针） | 值复制 payload |
| 与现有 `*void` 槽迁移 | 改槽类型 + 全改构造 | 全改构造 | 保留 `*void` | 槽改 `*Stage_State`，构造/读取零改 | 全改构造 |
| otter 适用性 | 差（无 tag 检查、context 膨胀） | 差（寿命/boxing 陷阱） | 中（违反 *void 纪律、可 desync） | **最佳** | 中（拷贝语义错配、demo 级） |

---

## 3. 推荐

### 3.1 结论

**Jai 没有原生 sum type / tagged union。** 对 `Stage_State`，推荐用语言官方 how_to 演示的**用户级 Type-tag 记录层次**：

1. 在共享模块（`src/lifecycle.jai`，保持只依赖 `Basic`）声明基记录 `Stage_State :: struct { kind: Type; }`。
2. 每个 stage payload 记录（`Prestep_Stage`、`Build_Transpile_Stage`、`Test_Transpile_Stage`、`Build_Compile_Stage`、`Test_Compile_Stage` 等）首字段写 `#as using base: Stage_State;`，并写 `base.kind = <自身类型>;`；记录可以留在现有文件，不必搬进 lifecycle.jai。
3. `Lifecycle_Context` 的状态槽类型由 `*void` 改为 `*Stage_State`（保留现有槽名或收敛为单个 `state`，由 065 决定）。
4. hook 读取：先 `ctx.<slot>.kind == <期望记录类型>`，再做 `cast(*<期望记录类型>)`；不匹配时写 ERROR 诊断并返回 false。
5. 构造点保持 `lctx.views = *tstage;` 不变（`#as` 隐式上转）；读取点的 cast 文本不变。测试里的 `cast(*Build_Transpile_Stage) ctx.views` 继续可用。

### 3.2 为什么不是原生 union / Any / tag+*void

- **原生 union 没有 tag**，且错误成员读取不报错；要补 tag 就退化为候选 A/C 的"两处写"问题。
- **`Any` 不是 sum type**：它是不拥有 payload 的 boxed 引用；存值/存指针 tag 不同、临时值会悬垂、未检查误读直接崩溃。用它承载 host-owned stage 状态会把寿命问题藏进最不该藏的地方。
- **tag + `*void`** 能工作，但状态类型信息被彻底丢弃（`ctx.views` 看不出该 cast 成什么），tag 与 payload 分离可 desync，且违反 otter 自己的 `*void` 纪律。
- **官方 `Tagged_Union` 模块** 是 demo 级的 inline 拷贝容器，与"编排器拥有记录、hook 原地修改"的现状不匹配；如果将来确实需要按值自包含的 union，可以再引入，但它不是当前 `Stage_State` 的最佳形状。

### 3.3 权衡：`kind: Type` 还是 `kind: <enum>`

- 选 `Type` 的理由：tag 就是 payload 的类型本身，**不需要维护中央枚举**；同一 stage 可以有多个 payload 类型（TRANSPILE：build vs test；COMPILE：build vs test），`Lifecycle_Stage` 枚举无法区分，而 `Type` 天然区分；官方 `Document` / `Holder_Base` 先例都用 `Type`；诊断信息直接（`print("unexpected state type %", kind)`）。
- 选 enum 的场景：极端在意二进制体积（`Type` = 8 字节且会带入各记录类型的 `Type_Info`）或需要封闭 tag 集合。代价是每个 payload 类型一个枚举成员 + 设置点手工映射；这对 add-only 的 stage 表是额外维护面。
- **不要用 `Lifecycle_Stage` 作 tag**：DISCOVER/TRANSPILE/COMPILE 等阶段与 payload 记录不是一一对应（同一阶段有 build/test 两套记录，PREPARE/VALIDATE 共享 artifact plans），用它会在同一 stage 内丢失区分度。

### 3.4 生成代码与闭包

- Jai 无闭包（`how_to/080_scopes.jai:77-80`），lifecycle 的 hook 是普通过程指针；所有状态必须显式经 `*Lifecycle_Context` 传递，推荐形状不引入隐藏环境或堆分配。
- 推荐形状让 `Lifecycle_Context` 只增加指针（或替换现有指针），不随 payload 大小增长；payload 留在命令栈上的 host-owned 记录里，hook 原地读写——与现在 `lctx.prestep = *pstage` 的代价相同。
- inline union / `Any` / tag+`*void` 都会把 payload 或 16 字节盒子塞进 context；context 按指针传递，单次 hook 调用不复制，但构造/清零成本和"context 被复制时连带复制 payload"的风险都更高。
- hook 必须保持非多态：`how_to/120:401-411` 证明多态过程不能赋给运行期变量，hook 表里存不了 `$T` 版本；tag 检查 + cast 必须发生在运行期。

### 3.5 陷阱清单（给 065/实现）

1. **不可用 `---` 构造 stage 记录**：实验证明 `---` 跳过 `base.kind` initializer，tag 不盖章。
2. **cast 前必须检查 `kind`**：Jai 的 cast 是纯重解释，错误 cast 可编译运行（实验 `miscast.jai`），且 `if case` 不要求穷尽；检查失败应升级为 lifecycle ERROR 诊断，而不是静默。
3. **不要按 base 值传递状态**：`Stage_State = derived` 会切片，只复制 tag（实验 `base_as_literals.jai`）；context 一律存 `*Stage_State`。
4. **at hook 替换的类型检查**：session 在调用 at hook 前后都可比对 `ctx.state.kind == <该阶段期望记录类型>`；这是 `*void` 方案给不出的保护，也与 065 "at hook 替换 built-in 时的 state 类型检查"直接对应。
5. **记录归属**：Type-base 只要求基记录在共享模块；payload 记录留在 `src/commands/*.jai`、`src/test_runner.jai` 也能嵌入（这些文件已 import lifecycle）。把 `Build_Transpile_Stage` 等搬进 `src/lifecycle.jai` 会因其引用 `Juice.Prepared_Workspace` / `Transpile_Plugin` / `Scan_File` 而把依赖拖进 bootstrap `#load` 闭包（`src/main.jai:51`；`src/lifecycle.jai:45` 目前只 import Basic），**不要为了类型而搬**；是否整合是 065 的依赖决策，不是语言要求。
6. **plugin_host 生成文本**：若 065 只改槽类型而保留槽名，生成文本 `lctx.prestep = *stage;` 不变；若收敛为单个 `state` 槽，生成文本需要同步更新并 pin 测试。

---

## 4. 对 065 的直接输入

- **推荐形状**：`Stage_State { kind: Type; }` + 各记录 `#as using base` 自盖章；context 槽 `*void -> *Stage_State`（或单 `state` 槽）。
- **hook 访问契约**：`if ctx.<slot> == null -> ERROR; if ctx.<slot>.kind != Expected -> ERROR; stage := cast(*Expected) ctx.<slot>;`。
- **at hook 类型检查**：session 用 `kind` 比对期望类型；不匹配 = 阶段失败。
- **不需要的东西**：中央 kind 枚举（除非刻意换 enum tag）、`Any`、原生 union、官方 Tagged_Union 模块、把 payload 记录搬进 lifecycle.jai。
- **不可避免的残余风险**：Jai 没有 checked downcast；任何方案都要"tag 检查 + cast"两步。Type-base 把 desync 风险从"设置点两次写"降到"只在手写 cast 撒谎时发生"。

---

## 5. 证据索引

### 5.1 发行版 / 本仓库

| 结论 | 来源 |
| --- | --- |
| 编译器版本 beta 0.2.009（2025-02-06） | `C:/Users/maojiaxing/DevTools/jai/CHANGELOG.txt:1` |
| 原生 union 需要外部 tag、是 C 式联合 | `C:/Users/maojiaxing/DevTools/jai/modules/Tagged_Union.jai:3-8` |
| 官方 Tagged_Union 形状（tag + bytes + set/isa） | `C:/Users/maojiaxing/DevTools/jai/modules/Tagged_Union.jai:34-71` |
| 类型切换宏未完成 | `C:/Users/maojiaxing/DevTools/jai/modules/Tagged_Union.jai:26-27` |
| Print 无法打印 union（无 active member 信息） | `C:/Users/maojiaxing/DevTools/jai/modules/Basic/Print.jai:408` |
| `Any` 定义与 boxing/非持有语义 | `C:/Users/maojiaxing/DevTools/jai/how_to/030_any.jai:55-64,89-107,159-191` |
| Type tag + `#as using base` 的 Document 先例与 `if case` 派发 | `C:/Users/maojiaxing/DevTools/jai/how_to/008_types.jai:98-149,244-257,299-302` |
| `Holder_Base` 动态派发先例 | `C:/Users/maojiaxing/DevTools/jai/how_to/120_polymorphic_structs.jai:340-411` |
| 多态过程不能赋给运行期变量 | `C:/Users/maojiaxing/DevTools/jai/how_to/120_polymorphic_structs.jai:401-411` |
| Jai 无闭包 | `C:/Users/maojiaxing/DevTools/jai/how_to/080_scopes.jai:77-80` |
| `if case` 语义与可选兜底 | `C:/Users/maojiaxing/DevTools/jai/how_to/027_if_case.jai:47-74` |
| `Type` 即 `*Type_Info` 的重解释证据 | `C:/Users/maojiaxing/DevTools/jai/how_to/180_type_variants.jai:185-193` |
| 关键字表无 sum/tagged 类型 | `C:/Users/maojiaxing/DevTools/jai/modules/Jai_Lexer/module.jai:80-122` |
| 现状 `*void` slots | `src/lifecycle.jai:134-169` |
| hook 形状 `(ctx, state: *void) -> bool` | `src/lifecycle.jai:103-110` |
| `Prestep_Stage` 已在共享模块 | `src/lifecycle.jai:175-198` |
| 命令局部 stage 记录 | `src/commands/build.jai:116-142`、`src/commands/test.jai:373-383`、`src/test_runner.jai:414-426` |
| 现有测试 cast 点 | `tests/build_transpile_tests.jai:57,96,185`、`tests/test_transpile_tests.jai:135,144,212` |
| lifecycle.jai 是 bootstrap `#load`、只 import Basic | `src/main.jai:51`、`src/lifecycle.jai:45` |
| context 无闭包、显式数据 | `src/lifecycle.jai:32-36` |

### 5.2 编译运行探针（beta 0.2.009，临时目录，输出原文摘要）

| 探针 | 关键输出 | 支撑结论 |
| --- | --- | --- |
| `union_basics.jai` | `size_of(U) = 16`；成员 offset 全 0；`textual_flags = UNION`；非活动成员读取为位重解释 | 原生 union 无 tag |
| `union_copy.jai` | `u.b` / `v.b` 独立；含 union 的 struct 独立复制 | union 值复制 |
| `any_basics.jai` | `size_of(Any) = 16`；存值 tag = `Record_A`、存指针 tag = `*Record_B`；改源变量 Any 可见；错误 cast 崩溃 | Any 非持有 + boxing 陷阱 |
| `tagged_inline.jai` | `size_of(Stage_State) = 32`；错误变体读取仍可编译通过 | union+enum 无配对检查、inline 膨胀 |
| `tag_void.jai` | `size_of(Stage_State) = 16`；tag 与 payload 两次写 | 现状泛化的代价 |
| `base_as.jai` | base 8B、derived 16B、base offset 0；隐式上转、cast 下转、派发正确 | 推荐形状可行 |
| `base_as_literals.jai` | `.{}` / `Type.{}` 都盖章；`Stage_State = derived` 切片只剩 base | 构造安全、禁止按值传 base |
| `base_as_no_init.jai` | `---` 构造不盖章；默认构造盖章 | 禁止 `---` |
| `hook_abi.jai` | 现有 hook 签名 + `*Stage_State` 槽正常运行；hook 原地修改 payload | 迁移零 ABI 变化 |
| `miscast.jai` | 错误 cast 编译运行并读到错误字段 | cast 无运行期校验 |
| `if_case_no_fallback.jai` | 无兜底/非穷尽编译运行正常 | 必须自写兜底 |
| `first_party_tagged_union.jai` | `set`/`isa` 正常；`size_of = 16`；非法 `set` 编译期断言失败 | 官方模块可用但为 inline 拷贝 |
