# ios-webview-sdk

Write all documentation and all files in English.

`CueLightShow` — the iOS (13+) Swift SDK for CUE Live Lightshow 2.0, a web view host for the web version of the lightshow. Sources live in `CueLightShow/`; it ships via Swift Package Manager (`Package.swift`) and CocoaPods (`CueLightShow.podspec`). `SDKConsumer/` (opened through `SDKConsumer.xcworkspace`) is the sample app that consumes the SDK.

## Repo etiquette

- Branch off `main` (the main branch); merge feature branches back into it.
- Conventional-commit subjects (`feat:`, `fix:`, `refactor:`).
- Commit or push only when asked.

## Core Principle: KISS

Keep it simple. Always reach for the smallest solution that solves the problem in front of you.

- No speculative abstraction, no premature generalization, no feature you weren't asked for (YAGNI).
- When code repeats, prefer duplication over an abstraction that adds coupling — wait until a pattern is proven before extracting it.
- Fewer moving parts beats clever. Optimize for the next person reading the code, not for the fewest lines.
- Match the surrounding code's idioms, naming, and structure rather than introducing a new style.

## Code Comments

Code explains itself through naming and structure. Default to **no comments**. Add one only when WHY is genuinely non-obvious (a hidden constraint, a bug workaround, a subtle invariant) — never WHAT. Keep it to **one short line**; no multi-paragraph or docstring-style blocks. Applies to every language.

## Testing

- Every code change carries tests for the new and modified behavior — success and error paths.
- Test behavior, not implementation details.
- Prefer real dependencies over mocks so tests exercise the actual integration.

## Linters & Cleanup

Always fix **every** problem you discover in the repo — lint warnings, failing tests, red CI, stale docs — even pre-existing and unrelated. Land it as a focused sibling change in the same session.

The repo has no lint or test scripts. After any change, build the `CueLightShow` framework (`CueLightShow.xcodeproj` / the `Package.swift` package) and the `SDKConsumer` sample app (`SDKConsumer.xcworkspace`, scheme `SDKConsumer`) for iOS, and fix every error and warning they report. When the podspec changes, also run `pod spec lint CueLightShow.podspec`.

## CI / Azure Pipelines

After every push to `main`, watch the triggered build to completion and report the result — never push and walk away.

The pipeline is Azure DevOps `ios-webview-sdk` (`azure-pipelines.yml`; org `transported-labsW4VWWG`, project `Transported Labs 1`, `definitionId: 80`). It triggers on `main` only: an Xcode build on macOS, then a deploy of the framework zip to the dev DXP CDN. Monitoring:

- **Find the build via the raw REST builds API, NOT `az pipelines build list`.** `az pipelines build list` omits freshly-queued/`inProgress` builds — right after a push it returns only older `completed` builds, so the new run looks missing. The REST API surfaces it immediately. Use `queryOrder=queueTimeDescending` and take `value[0]`:
  `az rest --method get --resource 499b84ac-1321-427f-aa17-267ca6975798 --uri "https://dev.azure.com/transported-labsW4VWWG/Transported%20Labs%201/_apis/build/builds?definitions=80&\$top=5&queryOrder=queueTimeDescending&api-version=7.1" --query "value[].{id:id,status:status,result:result,src:sourceVersion}"`
  Match the build to your push by `sourceVersion` (the commit SHA) — don't assume the top one is yours. `buildNumber` is Azure's timezone-based date counter, distinct from `Build.BuildId`; never key off it.
- **Poll the timeline** for stage/step state (the top-level `az pipelines build show` only gives overall status). It needs the Azure DevOps AAD resource id and the project in the path:
  `az rest --method get --resource 499b84ac-1321-427f-aa17-267ca6975798 --uri "https://dev.azure.com/transported-labsW4VWWG/Transported%20Labs%201/_apis/build/builds/<id>/timeline?api-version=7.1"`
  Filter `records[]` by `type` (`Stage`/`Job`/`Task`) and read `state` + `result`.
