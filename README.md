# codex-windows-init

一个面向 Windows 的轻量级 Codex 初始化脚本，用于快速准备本机 `~/.codex` 使用环境。

它的目标是尽量减少手工修改配置的步骤，尤其适合在新电脑、新用户环境下快速完成初始化。

## 功能说明

脚本会完成以下两件事：

1. 初始化或更新 `config.toml`
   - 仅维护以下 3 个顶层配置项
   - `sandbox_mode = "danger-full-access"`
   - `model_context_window = 512000`
   - `model_auto_compact_token_limit = 400000`
   - 不会主动修改其他 section，例如 `plugins`、`projects`、`desktop` 等

2. 初始化或更新 `.env`
   - 优先读取 Windows `Internet Settings` 代理配置
   - 如果系统代理不可用，则回退到现有 `.env`
   - 如果仍无法解析，则使用默认值 `127.0.0.1:7890`
   - 会写入以下环境变量：
     - `HTTP_PROXY`
     - `HTTPS_PROXY`
     - `ALL_PROXY`
     - `NO_PROXY=localhost,127.0.0.1`

## 文件说明

- `scripts/init-codex.ps1`
  主初始化脚本，负责配置更新、代理探测、备份和结果摘要输出。
- `scripts/init-codex.bat`
  批处理入口，方便双击执行或在 `cmd` 中直接调用，本质上会转调 PowerShell 脚本。

## 默认行为

如果不传任何参数，脚本会按下面的逻辑执行：

- `CodexHome`
  - 优先使用环境变量 `CODEX_HOME`
  - 如果未设置，则回退到当前用户目录下的 `~/.codex`
- `DefaultProxyHost`
  - 默认值为 `127.0.0.1`
- `DefaultProxyPort`
  - 默认值为 `7890`

## 快速开始

### 方式一：使用 bat 入口

```bat
scripts\init-codex.bat
```

### 方式二：直接运行 PowerShell 脚本

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\init-codex.ps1
```

执行完成后，脚本会输出一份 JSON 摘要，包含：

- 实际使用的 `CodexHome`
- `config.toml` 是否创建、是否变更
- `.env` 是否创建、是否变更
- 备份文件路径
- 最终使用的代理地址
- 代理来源

## 参数含义

### 脚本运行参数

#### `-CodexHome`

指定要初始化的 Codex 配置目录。

默认值：优先使用 `CODEX_HOME`，如果未设置则回退到 `$HOME\.codex`。

示例：

```bat
scripts\init-codex.bat -CodexHome C:\Users\foo\.codex
```

适用场景：

- 想初始化另一个用户目录下的 Codex 配置
- 本机使用了自定义 `CODEX_HOME`
- 希望先在测试目录中验证脚本效果

#### `-DefaultProxyHost`

指定默认代理主机地址。

只有当系统代理和现有 `.env` 都无法解析时才会生效。

默认值：`127.0.0.1`

示例：

```bat
scripts\init-codex.bat -DefaultProxyHost 192.168.1.10
```

#### `-DefaultProxyPort`

指定默认代理端口。

只有当系统代理和现有 `.env` 都无法解析时才会生效。

默认值：`7890`

示例：

```bat
scripts\init-codex.bat -DefaultProxyPort 7891
```

### `config.toml` 配置项含义

脚本会写入下面 3 个配置项，它们的含义如下。

#### `sandbox_mode = "danger-full-access"`

表示 Codex 运行时使用完全访问权限模式。

含义：

- 不使用受限沙箱
- 允许更高权限地访问本机文件和执行命令
- 适合本地开发、自动化初始化和需要较强操作能力的场景

注意：

- 这个配置权限较高
- 使用前请确认你了解它带来的访问范围和风险

#### `model_context_window = 512000`

表示模型可使用的上下文窗口大小。

含义：

- 控制单轮或连续对话中可容纳的上下文规模
- 值越大，可保留的上下文通常越多
- 适合长对话、大仓库分析、复杂任务持续推进的场景

这里固定为你当前机器使用的值：`512000`。

#### `model_auto_compact_token_limit = 400000`

表示上下文接近上限时，自动触发压缩的阈值。

含义：

- 当上下文 token 使用量接近这个阈值时，Codex 会更早开始做上下文压缩
- 有助于避免真正撞到窗口上限后再处理
- 适合长线程下维持稳定的上下文管理行为

这里固定为你当前机器使用的值：`400000`。

### `.env` 代理变量含义

脚本会写入以下变量：

- `HTTP_PROXY`
  用于 HTTP 请求代理
- `HTTPS_PROXY`
  用于 HTTPS 请求代理
- `ALL_PROXY`
  用于通用代理回退
- `NO_PROXY`
  指定不走代理的地址，当前固定为 `localhost,127.0.0.1`

## 代理解析规则

脚本按以下优先级选择代理：

1. Windows `Internet Settings`
2. 现有 `.env`
3. `-DefaultProxyHost` + `-DefaultProxyPort`

支持的 `ProxyServer` 格式包括：

```text
127.0.0.1:7890
```

```text
http=127.0.0.1:7890;https=127.0.0.1:7890
```

如果系统只配置了 `PAC` 脚本地址，而没有显式 `ProxyServer`，当前脚本不会解析 PAC，而是继续走回退逻辑。

## 备份与重复执行

脚本在写入前会自动备份原文件，命名格式如下：

```text
config.toml.bak.yyyyMMddHHmmss
.env.bak.yyyyMMddHHmmss
```

只有在文件实际发生变更时才会生成备份。

脚本支持重复执行。如果目标配置已经符合预期：

- 不会重复插入相同配置项
- 不会破坏原有 `TOML` section 结构
- 不会重复生成备份
- 输出摘要中的 `configChanged` 和 `envChanged` 会是 `false`

## 注意事项

- 当前仅支持 Windows
- `sandbox_mode` 会被设置为 `danger-full-access`
- 脚本不会修改 `WinHTTP` 代理设置
- 脚本不会解析 PAC 地址
