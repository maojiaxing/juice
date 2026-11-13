# 普通 Package 字段的省略状态实验

关联：[Jai 声明表达、默认值与校验契约](../../issues/0084-decision-declaration-evaluation-validation.md#resolution)。这是独立的编译器实验，不是 Juice 实现。用户在决策票 Q27 中已接受内部保留标记及其显式构造碰撞限制；具体产品常量和编码不由这个实验确定。

## 结论

Jai beta 0.2.009（编译器报告构建日期 2025-02-06）支持为普通数组、字符串和嵌套结构设置不同的字段默认值。两次编译成功，最终程序的断言全部通过：可以区分省略、显式空和普通非空数据，用户写法无需 Manifest、Some 或三态包装。

但是，显式构造相同默认标记，会得到与省略完全相同的求值结果。仅根据最终值无法恢复“这个字段在源码中是否出现”。实验并未证明严格的初始化来源追踪，也没有验证编译器是否提供相应元数据。普通数组零值本身不能作为可靠的省略判断。

## 已执行的验证

在独立临时目录定义简化的 Entry、Workspace、Package，并用编译器 API `compiler_get_version_info(null)` 核实版本。没有导入或修改 Juice。关键定义为：

```jai
OMITTED :: "\x01internal-omitted";
Entry :: struct {
    name: string;
}
Workspace :: struct {
    root: string = ".";
}
Package :: struct {
    modules: []Entry = .[.{name = OMITTED}];
    name: string = OMITTED;
    default_run: string = OMITTED;
    workspace: Workspace = .{root = OMITTED};
}
PACKAGE :: Package.{};
```

这里的 root 字段只是实验观察点，不是提议给 Workspace 新增公开字段。上面的标记也不是产品常量；即使其包含控制字符，手工构造相同值仍会碰撞。

测试覆盖：

| 输入 | 观察结果 |
|---|---|
| `Package.{}` | 数组/字符串/嵌套值采用字段特定默认值 |
| `Package.{modules = .[], name = "", default_run = "", workspace = .{}}` | 数组为零项、字符串为空、workspace 使用 Workspace 类型默认值 |
| 给以上字段普通非空值 | 得到相应非空值 |
| 显式填写与字段默认值相同的标记 | 与省略无法区分，碰撞断言通过 |

最终运行输出：

```text
PASS []Entry: omitted=sentinel, explicit-empty=count-0, populated=app
PASS string: omitted=sentinel, explicit-empty=length-0, populated=app
PASS Workspace: omitted=field-override, explicit-.{}=type-default, populated=src
LIMIT explicit sentinel values collide with omission in all three value representations
```

## 复核信息

实验目录：`C:/Users/maojiaxing/DevTools/msys/tmp/jai-presence-8f7e12f4/`，包含 `probe.jai`、`compile-1.txt`、`compile-2.txt`、`run.txt` 和 `probe.exe`。最终编译及运行命令，在该目录执行：

```powershell
jai probe.jai -output_path . -exe probe -no_color
.\probe.exe
```

两次成功编译中，第一版未打印版本，第二版添加了版本 API 输出。主会话核读了最终完整 probe.jai、编译输出与运行结果；未将该程序集成到生产接口，也未据此声称新 Package 字段已经可通过当前 `#import "Juice"` 使用。

## 决策票采用的取舍

用户已确认采用内部保留标记：标记不属于可手工构造的配置输入，须与合法名称、路径和实际条目不相交；显式空仍正常表达禁用或触发字段错误。记录的是声明数据中的配置状态，不保证恢复所有源码初始化痕迹。

本轮不要求对手工构造保留标记追踪初始化来源，不引入公开包装、布尔开关或模式枚举。完整约束以关联票 Resolution 为准。
