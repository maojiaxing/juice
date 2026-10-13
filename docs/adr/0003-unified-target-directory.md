# 0003: 统一 target/ 构建目录（cargo 式），取代 result/ 与 .packages

转译集成票（0008）讨论缓存位置时票主拍板：Juice 管理的可再生产物不应散落三处（package root 的 `result/`、`.packages`、用户级 XDG 缓存），统一收进 package root 的 `target/`，参考 cargo。

**决定**：

1. `<package_root>/target/` 是 Juice 管理的统一构建目录：artifact 直落 target/ 根（无 debug/release profile，cargo 的扁平版）；依赖 import shim 落 `target/packages/`（`-import_dir` 指向，取代 `.packages`）；转译生成物落 `target/transpile/`。
2. root 级 `result/` 与 `.packages` 退出模型：磁盘遗留目录 Juice 不再管理、不清理（沿「不把旧 `bin/` 当管理对象」先例）。Clean 语义改为递归删除 root 与已验证 workspace member 的 `target/` 整目录。
3. 用户级 XDG 缓存只保留外部输入：git 源缓存（`cache_dir/git_repos`）与 manifest 求值临时文件——对应 cargo 的 `~/.cargo/registry`。target/ 的收容判据：可再生自 package 自身内容。
4. 不做失效指纹：转译子树内容寻址（同键必同产物），jai 无增量编译，fingerprint/mtime 机制是纯负担；也不做主动清理（随 clean 整目录消失）。

**Considered Options**: (a) 转译缓存挂用户级 XDG（跨包共享）——否决：转译产物属 package 可再生物，随 per-package clean 消失更符合直觉，而 jai 无增量使跨包共享收益为零；(b) 保留 `result/` + `.packages`、只把转译物放新目录——否决：三处散落，用户要记三套清理规则。

**Consequences**: 对外路径约定的破坏性替换（`.gitignore`、文档、脚本需跟进）；目录名 `target/` 与领域词 Target declaration / Effective target 同名异义（Rust 自身同样共存），CONTEXT.md 词条定名「Target directory」并写明区分；jai 自身中间物（obj）不承诺入 target/（CLI 仅有 `-output_path`，实现期一次实验定案）。
