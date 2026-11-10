# Instructions for coding and design agents — Spider Wallet

Before changing **any** `Console/` UI or UX code, read the root [`DESIGN_RULES.md`](DESIGN_RULES.md). It is the canonical design system for this project; older notes in `docs/SPIDER_DESIGN_RULES.md` are historical.

Mandatory workflow:
1. Preserve transaction semantics, security controls, wallet secrets, network behavior, and existing navigation entrypoints.
2. Reuse the existing centralized styles in `Console/Design/WalletTheme.swift` before introducing a component or design token.
3. Validate visible states, labels, touch areas, accessibility, iOS 17 compatibility, and actual backend support for advertised actions.
4. Report tests, Xcode build, Simulator and device validation **separately**. Never imply a test was performed if it was not.
5. For ZIP patches, use paths relative to repository root; never include `.github/workflows` unless specifically requested.

If design rules conflict with safety, accessibility, or functional correctness, prioritize those concerns and explain the exception. Do not silently revise brand decisions.
