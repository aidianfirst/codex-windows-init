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

## 参数说明

### `-CodexHome`

指定要初始化的 Codex 配置目录。

默认值：

```text
$env:CODEX_HOME
```

如果 `CODEX_HOME` 未设置，则回退为：

```text
$HOME\.codex
```

示例：

```bat
scripts\init-codex.bat -CodexHome C:\Users\foo\.codex
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\init-codex.ps1 -CodexHome C:\Users\foo\.codex
```

适用场景：

- 你想初始化另一个用户目录下的 Codex 配置
- 你本机使用了自定义 `CODEX_HOME`
- 你希望先在测试目录中验证脚本效果

### `-DefaultProxyHost`

指定默认代理主机地址。

只有在下面两种情况都失败时才会使用：

1. Windows `Internet Settings` 中没有可解析的代理配置
2. 现有 `.env` 中没有可解析的代理配置

默认值：

```text
127.0.0.1
```

示例：

```bat
scripts\init-codex.bat -DefaultProxyHost 192.168.1.10
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\init-codex.ps1 -DefaultProxyHost 192.168.1.10
```

### `-DefaultProxyPort`

指定默认代理端口。

同样只有在系统代理和现有 `.env` 都不可用时才会生效。

默认值：

```text
7890
```

示例：

```bat
scripts\init-codex.bat -DefaultProxyPort 7891
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\init-codex.ps1 -DefaultProxyPort 7891
```

## 参数该如何修改

最常见的修改方式有下面几种。

### 1. 修改初始化目标目录

如果你不想让脚本操作当前用户的 `~/.codex`，可以显式传入 `-CodexHome`：

```bat
scripts\init-codex.bat -CodexHome D:\custom\codex-home
```

### 2. 修改默认代理端口

如果你常用的本地代理端口不是 `7890`，例如是 `7891`，可以这样执行：

```bat
scripts\init-codex.bat -DefaultProxyPort 7891
```

### 3. 同时修改默认代理主机和端口

如果你的代理服务不在本机回环地址，而是在局域网设备上，可以这样执行：

```bat
scripts\init-codex.bat -DefaultProxyHost 192.168.31.10 -DefaultProxyPort 7890
```

### 4. 用 PowerShell 方式传参

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\init-codex.ps1 -CodexHome C:\Users\foo\.codex -DefaultProxyHost 127.0.0.1 -DefaultProxyPort 7890
```

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

## 备份说明

脚本在写入前会自动备份原文件，命名格式如下：

```text
config.toml.bak.yyyyMMddHHmmss
.env.bak.yyyyMMddHHmmss
```

只有在文件实际发生变更时才会生成备份。

## 幂等性说明

脚本支持重复执行。

如果目标配置已经符合预期：

- 不会重复插入相同配置项
- 不会破坏原有 `TOML` section 结构
- 不会重复生成备份
- 输出摘要中的 `configChanged` 和 `envChanged` 会是 `false`

## 注意事项

- 当前仅支持 Windows
- `sandbox_mode` 会被设置为 `danger-full-access`
- 请确认你了解该配置带来的权限范围
- 脚本不会修改 `WinHTTP` 代理设置
- 脚本不会解析 PAC 地址

## 示例

### 使用当前用户默认目录初始化

```bat
scripts\init-codex.bat
```

### 初始化指定目录

```bat
scripts\init-codex.bat -CodexHome C:\Users\foo\.codex
```

### 当系统代理不可用时，使用自定义默认端口

```bat
scripts\init-codex.bat -DefaultProxyPort 7891
```

### 同时指定自定义目录和默认代理

```bat
scripts\init-codex.bat -CodexHome D:\codex-home -DefaultProxyHost 127.0.0.1 -DefaultProxyPort 7891
```
