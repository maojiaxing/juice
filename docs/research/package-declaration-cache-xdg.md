**0086：Cargo 全局内容缓存与 XDG 目录契约**

实际核查：2026-11-13。范围：四份官方公开页面；XDG 当前 `latest` 返回 0.8（2021-05-08 发布）；Cargo Book 为核查日在线滚动版，页面未标注发行版本。未调查本地实现。

**XDG 规范事实。** `XDG_CACHE_HOME` 存放用户专属、非必需的缓存数据；未设置或空值时应使用 `$HOME/.cache`。`XDG_STATE_HOME` 存放应跨应用重启保留、但不适合归入可移植用户数据的状态，如历史、布局、撤销记录；未设置或为空时应使用 `$HOME/.local/state`。两者用途不同。[规范 §2–3][1]

所有这些变量中的路径必须为绝对路径；实现遇到相对值应视为无效并忽略，不能相对于当前目录使用。规范没有单列“忽略相对值后如何回退”的算法；Juice 可选择按未设置处理，但应注明这是实施选择。[规范 §3][1]

规范定义基目录，并以 `subdir/filename` 说明其他规范如何引用数据及配置路径，没有规定应用缓存子目录的统一名称。`juice/` 应是 Juice 的隔离约定。写文件时，目标目录不存在应尝试以 `0700` 创建；已有目录不应改变权限，创建或写入失败应能处理。不要把 `XDG_RUNTIME_DIR` 的强制所有权要求直接套给缓存目录。[规范 §3–4][1]

正文使用 Unix 权限语义，但未明确排除 Windows，也未规定 Windows 的 XDG 优先级、`LOCALAPPDATA` 回退、盘符路径判定或 ACL 映射；这些不能宣称为 XDG 标准要求。[规范全文][1]

**Cargo 行为事实。** Cargo Home 默认是 `$HOME/.cargo/`，可通过 `CARGO_HOME` 覆盖；其中除下载源码，还包含配置、安装记录及可执行文件，内部结构未稳定。因此不能把整个 Cargo Home 当成可删缓存，也不能把默认 `~/.cargo` 称为符合 XDG 的缓存布局。[Cargo Home][2]

`git/db` 保存 Git 裸仓库并按需更新；`git/checkouts` 从中检出所需提交，同一仓库可有多个不同提交的检出。这解释了内容复用，不能代替工程的提交选择记录。Cargo 将精确 Git 提交写入 `Cargo.lock`，Git 依赖更新由 `cargo update` 触发；选择记录与 Cargo Home 内容缓存职责分离。[Cargo Home][2]、[锁文件指南][3]、[Git 依赖说明][4]

**删除成本：事实与推荐。** Cargo 文档说缓存可删除，并会尽力通过重新检出、解压或下载恢复所需源码；这是恢复机制，不是离线或上游永久可用的保证。[清理缓存][2] 推荐 Juice 将全局 Git 内容视为可重建缓存，工程已选提交仍分别记录；遵循已确认的无 `juice.lock` 约束。若工程选择记录也随缓存删除，移动后的分支或标签可能解析到不同提交；固定 rev 仍依赖对象可取得。这是 Juice 的风险推论，不是 XDG 的恢复承诺。

**结论与待人工决定。** 可借鉴 Cargo 的全局内容复用，并按 XDG 区分缓存和状态。待定：应用子目录名；相对值忽略后的回退；Windows 是否优先有效 XDG、何时回退 `LOCALAPPDATA` 及权限处理；工程选择记录归入可删缓存还是持久状态。将选择记录归入状态目录是保留选择的建议，不改变已确认的“缓存可删”，也不替用户作路径决策。

[1]: https://specifications.freedesktop.org/basedir-spec/latest/ "XDG Base Directory Specification 0.8，2021-05-08"
[2]: https://doc.rust-lang.org/cargo/guide/cargo-home.html "Cargo Book：Cargo Home，2026-11-13 核查"
[3]: https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html "Cargo Book：Cargo.toml vs Cargo.lock，2026-11-13 核查"
[4]: https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#specifying-dependencies-from-git-repositories "Cargo Book：Git dependencies，2026-11-13 核查"
