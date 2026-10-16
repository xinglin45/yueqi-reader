# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.

## 已确认的设计方向（2026-10-16）

用户选择三套方案中的第一套：暖纸阅读。参考图在 `../reference/selected-warm-paper.png`。保持灰暖侧栏、铜色强调、宋体正文、轻量浮层与中文桌面排版。用户于2026-10-16明确回复“确认D1”，已确认提交e7764cc的整包D1，MAC-02-D/01A已完成，见 `../confirmation-D1.md`。后续沿用主风格、导航布局和关键交互；常规对齐/间距可自主修正，重大设计变动再展示具体版本。

双模式参考见 `../reference/mac_dual_mode_reader_ui_spec.md`，与项目Flutter、来源和一次成年声明约定共同使用。只使用自产普通文本。原型说明与模拟标记保留；不能把浏览器面板写为macOS全局能力。
