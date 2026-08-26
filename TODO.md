# 需求 TODO：本地 CLI 状态、账号配置与项目消耗统计

> 状态：实现完成，验收清单持续复审中。本文中的“额度”均指 Claude Code `/usage` 与 Codex
> `/status` 所报告的订阅限额状态；Claude 的套餐/认证方式来自其独立 `/status` 会话。本应用不得直接通过 HTTP API、OAuth token 或本地
> 凭据读取服务商额度。允许由用户本机已登录的 Claude/Codex CLI 自身经代理访问服务商。

## 0. 不可违反的约束

- [x] 额度读取只能通过启动本机 `claude` 和 `codex` 的**交互会话**、分别发送 Claude `/usage`、Claude `/status` 与 Codex `/status`、
  解析终端输出完成。CLI 自身的、经用户配置代理进行的服务商访问是允许且预期的。
- [x] 本应用自身禁止访问 Claude、OpenAI/Codex 的 HTTP 用量、重置额度或 OAuth endpoint。
- [x] 禁止读取、缓存、传输或刷新 OAuth access token / refresh token；不得读取
  `~/.codex/auth.json`、Claude Keychain、Claude credentials 文件来供本应用发请求。
- [x] 不得以 `Authorization` 请求头向服务商发送任何凭据。
- [x] CLI 进程必须运行在专用伪终端（PTY）中，以满足 `/status` 的交互会话要求；设置
  固定终端尺寸、超时、PTY master 合并输出捕获，并避免多个轮询并发启动。子进程必须处于
  独立进程组，超时/失败时终止整个进程组，避免 CLI 或其子进程残留。
- [x] Claude CLI 状态操作显式设置 `HTTP_PROXY` 与 `HTTPS_PROXY`，配置为空时不得启动；
  Codex 配置项的代理可选，留空时清理继承的代理变量并直连。除这些变量外，不额外干预或清理子
  进程继承的环境变量；Claude 额外设置用户指定的本地 `NO_PROXY`。
- [x] 本地日志的成本与 token 统计不需要网络；在代理为空时仍允许此纯本地统计，仅禁止
  CLI `/status` 额度刷新。
- [x] 不持久化、打印或上传原始 PTY 输出；只保留已解析的必要状态字段。日志和测试
  transcript 必须脱敏邮箱、账号、路径及其他身份信息。
- [x] 本次为直接重构：不保留旧 HTTP/OAuth 用量实现、旧缓存、历史数据迁移、兼容分支或
  回退路径。新版本只认可新的 CLI `/status` 与本地日志数据模型。

## 1. Claude Code 额度：通过独立交互 `/usage` 与 `/status` 获取

- [x] 删除当前 Claude OAuth 凭据解析、Keychain 访问、token 刷新辅助逻辑及
  `https://api.anthropic.com/api/oauth/usage` 请求。
- [x] 用 PTY 启动两个独立 `claude` 交互会话：`/usage` 只读取额度窗口，`/status` 只读取 `Login method`；分别捕获终端渲染状态，随后发终端 `SIGINT` 请求退出；失败或超时时终止子进程组。
- [x] `/usage` 与 `/status` 调用不得附带自然语言 prompt、模型任务、工具调用或任何会产生 token 消耗的
  参数；不得使用 `claude -p/--print` 模拟状态查询。
- [x] 以受控的真实界面形态与脱敏离线 fixture 确认：目标 Claude Code 版本的 `/usage` 与 `/status` 不会
  开启模型 turn，且输出可稳定识别；若不满足，显示解析错误，不会偷偷退回 HTTP API。
- [x] 新增 Claude 独立代理配置。执行时必须同时注入：

  ```text
  HTTP_PROXY=http://127.0.0.1:7890
  HTTPS_PROXY=http://127.0.0.1:7890
  ```

- [x] Claude 代理为空时，状态刷新被阻止，并在灵动岛和设置页显示“proxy required”；不会
  把它显示成额度为 0。
- [x] 从 CLI `/usage` 解析并显示可用的限额窗口、已用/剩余比例、重置时间；从独立 `/status` 的 `Login method` 解析套餐/认证模式。若 CLI 不提供某个字段，UI 显示“CLI 未提供”，不可推测。
- [x] 限额数据模型保留 CLI 报告的真实窗口时长和窗口标识，支持任意数量的窗口；不得
  再把所有结果强制映射为现有的固定“5 小时 + 7 天”两个字段。

## 2. Codex 额度：多配置目录、多账号/认证模式与交互 `/status`

- [x] 删除当前从 `~/.codex/auth.json` 读取 token、请求
  `chatgpt.com/backend-api/wham/usage` 与 `rate-limit-reset-credits` 的实现。
- [x] 用 PTY 启动 `codex` 交互会话，等待 composer/prompt 后写入 `/status` 与换行，捕获
  终端渲染的额度状态，随后发终端 `SIGINT` 请求退出；失败或超时时终止子进程组。
- [x] Codex 状态探测以单次配置覆盖 `-c check_for_update_on_startup=false` 禁用启动更新
  检查；不得在额度轮询时触发 Codex 自更新，也不得改写用户的 `CODEX_HOME/config.toml`。
- [x] 不使用 `codex login status`、`codex exec`、Codex app-server 或任何应用侧 HTTP API
  作为额度来源；`/status` 是唯一的 Codex 额度来源。
- [x] `/status` 调用不附带自然语言 prompt、模型任务、工具调用或任何会产生 token 消耗的
  参数。实施前以受控测试确认目标 Codex 版本的 `/status` 输出可稳定识别；不支持时明确报错。
- [x] 支持维护多个 Codex 配置项（可新增、编辑、删除、启用/停用），每项至少包含：
  - 唯一名称；
  - `CODEX_HOME` 的绝对路径；
  - 独立代理地址；
  - 最近一次状态和错误信息。
- [x] 每个配置项以类似下列环境运行 `codex`，而不是让应用读取其中的认证文件：

  ```text
  CODEX_HOME=/Users/baerwang/codex/baerwang
  HTTP_PROXY=http://127.0.0.1:7890
  HTTPS_PROXY=http://127.0.0.1:7890
  codex  # 在 PTY 交互会话中运行，再输入 /status
  ```

- [x] Codex 每个配置项的代理独立配置；可留空以直接运行 CLI，填写时在该配置项的所有
  Codex 状态操作中统一生效。
- [x] 将 CLI 可识别的认证模式显示为“账号订阅”或“API”；无法可靠识别时显示解析错误，
  不能根据 auth 文件推断。API 模式显示“无订阅额度”，只展示本机日志统计的
  token 与美元成本；不得尝试调用 API 查询服务端额度或账单。
- [x] 多个 Codex 配置项的订阅额度不得汇总或平均；灵动岛显示第一个可用的手工配置项，
  展开页和设置页按用户命名的配置项分别展示，避免不同账号的额度被误合并。
- [x] 套餐、所有额度窗口、重置时间和任何 CLI 报告的附属额度信息绑定到单个 Codex
  配置项；不得继续使用全局单例状态或跨账号合并。
- [x] 限额数据模型保留 CLI 报告的真实窗口时长和窗口标识，支持任意数量的窗口；不得
  再把所有结果强制映射为现有的固定“5 小时 + 7 天”两个字段。

## 3. 全部项目与单项目的消耗统计

- [x] 保留纯本地日志扫描，不发送项目日志、token 明细或路径到网络。
- [x] 给每个 token 事件附加项目标识：使用日志中的 `cwd` 作为内部唯一键，使用目录名
  作为默认显示名；同名但不同路径必须分开统计。
- [x] Claude Code：直接使用 usage 行中的 `cwd`，并将 subagent 日志归属到该 `cwd`。
- [x] Codex：优先从 `session_meta.payload.cwd` 取得默认目录，并随
  `turn_context.payload.cwd` 更新，令后续 `token_count` 归属当前目录。
- [x] 每个 Codex 配置项都扫描其自身 `CODEX_HOME/sessions`；token 事件携带所属
  Codex 配置项，避免多个账号的项目消耗被混入默认 `~/.codex`。
- [x] 按“provider + Codex 配置项（如适用）+ 项目”聚合，提供：
  - 所有项目总计；
  - 每个项目的今天、当月累计；
  - 美元成本估算；
  - token 吞吐量（总量和 input + output 的 billable 口径）；
  - 今日按小时、当月按天的累计趋势，以及近 5 小时/近 7 天模型明细；
  - 每个项目的今日/当月美元与 token 汇总。
- [x] 为无法归属 `cwd` 的记录保留“未归属项目”桶，并在 UI 中显示独立行；不得静默归入任意
  项目。
- [x] 现有 OpenCode 日志纳入 Claude/Codex 总计时归为“未归属项目”；后续
  单独调研其 session → workspace 元数据后再做精确归属。
- [x] 明确标注：项目 token/美元来自本机日志，美元为模型价目表估算；它不等于服务端
  账户级额度百分比，也不包含其他设备、网页端或缺失/已删除日志的使用量。
- [x] 保留公开 GitHub Pages 价格目录
  `https://ericjypark.github.io/codex-island-model-catalog/v1/models.json` 的无认证自动更新；
  请求不得携带 token、`Authorization`、账号、项目路径或用户用量数据。目录不可用时使用
  内置静态价目表，并标记价格可能过期。

## 4. 轮询与状态生命周期

- [x] 保留 5 / 15 / 30 分钟的安全刷新档位和“单次刷新不重叠”的保护，但刷新对象改为
  Claude/Codex PTY 交互会话中的 `/usage` / `/status`，不再调用应用侧网络 endpoint。
- [x] 抽取共享的 CLI 状态探测器：启动 PTY → 等待初始界面 → 写入对应 `/usage` 或 `/status` → 等待完整输出
  → 解析 ANSI/终端屏幕 → `SIGINT`/超时清理。Claude 与每个 Codex 配置项复用同一状态机。
- [x] 解析器从 ANSI/VT 控制序列、加载动画、终端换行和不同窗口尺寸中恢复可测试的纯文本；
  固定 PTY 尺寸，避免因自动折行破坏字段识别。
- [x] Codex PTY 初始化会发出光标位置查询 `ESC[6n`；探测器在写入 `/status` 前回复
  终端位置报告，并等待 `›` prompt。随后整体写入 `/status` 与其确认 `CR`，不能依赖脆弱的
  slash 菜单筛选、逐键节奏或菜单行号。
- [x] 每次 CLI 状态探测在配置的固定状态工作目录 `/private/tmp/` 中启动，不能在用户项目
  目录启动；该目录不由应用创建、修改或删除。避免加载项目级配置、hooks、MCP、插件、
  AGENTS 指令或工作区信任提示。
- [x] Codex 若首次对固定状态工作目录提示信任，自动选择继续；该信任状态归用户自己的
  Codex CLI 管理，应用不得直接写 `CODEX_HOME/config.toml`。
- [x] 代理缺失、CLI 不存在、命令超时、非零退出、格式无法识别时，保留上一次成功状态并
  标注过期/错误；不能伪造 0% 或 100%。
- [x] 上一次成功的额度读数只保留到其自身 `resetsAt`；超过该时间立即作废并显示“状态已
  过期”，不能无限显示旧的已用比例。
- [x] 重新配置代理、Codex 配置目录或 CLI 可用性恢复时，允许按安全规则在下一次安全轮询刷新。
- [x] 移除基于 Anthropic HTTP 429、OAuth token 过期、Keychain 变化和 OAuth re-auth 的
  冷却、监听与恢复逻辑；以 CLI 的退出状态和输出为唯一状态来源。

## 5. 移除 Sparkle 自动更新

- [x] 禁用应用启动时的 Sparkle updater 初始化及自动调度。
- [x] 注释或禁用设置页的检查更新入口、相关文案和自动更新状态；运行时不再检查或下载更新。
- [x] 保留现有 Sparkle 构建/发布依赖、文档和脚本，不改变发布流程；只禁用应用运行时的
  自动更新行为。

## 6. 灵动岛与设置界面调整

- [x] 未配置代理时，灵动岛显示清晰的配置状态，而不是可点击的伪用量。
- [x] PTY 状态探测进行时，灵动岛显示“正在读取 CLI 状态”；超时、提示符未出现、未登录、
  代理错误或无法解析时显示对应错误，不显示伪造额度。
- [x] 同时存在多个 Codex 配置项时，主视图只显示第一个可用手工配置项且不合并额度；
  展开页必须能看到每个配置项的独立状态。
- [x] 增加项目消耗入口：全部项目概览、单项目的今日/当月行、provider/账号区分与趋势图。
- [x] 用“CLI 状态”“本地日志估算”替换所有暗示 OAuth/API 直连的 UI、帮助文案、错误文案和
  隐私声明。

## 7. 清理、测试与验收

- [x] 删除或替换所有 Claude/Codex HTTP 用量 endpoint、OAuth endpoint、Bearer token、
  `URLSession` 用量请求和 reset-credit 请求；确认本应用网络层不会因额度刷新而直接访问
  服务商。
- [x] 删除不再使用的 OAuth/Keychain token 读取、刷新、重认证和 credential-watch 代码及测试。
- [x] 删除旧 API 用量历史、旧用量缓存及其 UserDefaults key；不做数据迁移。首次启动新版后，
  仅显示新 CLI `/usage` / `/status` 和新本地日志扫描得到的数据。
- [x] 更新 README、隐私说明、故障排查与设置文案，说明代理是状态读取的必填项。
- [x] 为 CLI 输出解析准备脱敏 PTY transcript fixture，覆盖正常、多个窗口、单窗口、API
  模式、未登录、代理失败、提示符未出现、ANSI 控制序列、加载动画、超时、`SIGINT` 清理、版本
  变化与未知字段。
- [x] 为多 `CODEX_HOME` 配置、项目路径归属、同名路径、子代理、未归属事件、日/月边界和
  多账号不合并建立单元测试。
- [x] 验收：以静态网络面审计确认本应用不会直接向 Claude/OpenAI 服务发出用量、
  reset-credit 或 OAuth HTTP 请求；额度刷新所需的服务商交互仅由用户机器上的 CLI 进程在
  显式代理下完成。

## 实施前必须确认

- [x] 收集并锁定当前验证的 Claude Code `/usage` / `/status` 与 Codex `/status` PTY transcript；验证
  这些命令不会触发模型 turn 或 token 消耗，并为未支持版本提供明确的降级提示。
- [x] 多 Codex 配置项在灵动岛显示第一个可用手工配置项；展开页按配置分别展示。
