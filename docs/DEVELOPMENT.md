# Developing Caylex iOS

For app installation and embedding, see the [README](../README.md).

## Transport and lifecycle

A narrowly scoped fetch bridge routes requests under the configured Assistants
API base URL through an ephemeral native URLSession. SSE chunks are forwarded
as they arrive, multipart uploads preserve their bodies, and AbortSignal cancels
native requests. This avoids requiring CORS changes for an embedded origin.
HTTP error statuses stay ordinary responses so the widget's 401 refresh/retry
logic continues to work. Redirects outside the configured API are not followed.
Only HTTPS API URLs are accepted, apart from localhost HTTP for development.

Live voice retains its existing WebRTC media and WebSocket relay. On foreground,
the wrapper refreshes service/task state and wakes session polling. A terminated
WebKit process is reloaded. iOS suspension can interrupt streams; restore or
resume from the backend rather than assuming uninterrupted background execution.


## Demo and development

```sh
swift test
node --test Tests/JavaScript/native-fetch.test.mjs

# Requires XcodeGen to generate the small demo project.
xcodegen generate --spec Examples/ChatDemo/project.yml
python3 Examples/ChatDemo/demo-server.py
open Examples/ChatDemo/ChatDemo.xcodeproj
```

Run the `ChatDemo` scheme on an iPhone simulator with the `--fixture` launch
argument to test the local fixture. Its initial token deliberately expires to
test automatic refresh. The local backend produces clearly labeled
fixture replies, a tool-approval flow, and a saved session. It never calls an AI
provider. The demo opens a layout picker with three pages: full screen, above a
native bottom dock, and a rounded card between a top bar and bottom dock.
Use **Layouts** to return to the picker. Each page owns a separate controller;
returning to the picker closes that mounted chat. The full-screen page's floating
Layouts button is a demo control, not part of the package.
For a direct launch, add `--layout=full`, `--layout=dock`, or `--layout=framed`.

To test a real agent, run the local server
with `--credentials-file /absolute/path/to/private-credentials.json`. That
private file contains `platformToken`, `caylexApiKey`, `userEmail`, `mintURL`, and
`apiBaseURL`, plus an optional `userName`. Use the matching production or development
Caylex endpoints. Keep this file outside the repository with owner-only permissions.
The demo automatically requests a live widget token at launch when this helper is configured; a token-server failure shows a retry screen instead of silently using a fixture.
This helper is for simulator development only; production apps use their own
backend for token minting and refresh.


## Updating the web bundle

The JavaScript source of truth remains in
`caylex-frontend/packages/chat-widget/src/ios-entry.tsx`, using the same widget
component and chat hook as the npm and CDN packages.

```sh
./Scripts/sync-widget.sh /absolute/path/to/caylex-frontend
```

The script type-checks/builds the iOS entry, copies its generated JavaScript,
and records the frontend commit, working-tree state, widget version, and SHA-256
in `Resources/widget-build.json`. Commit the updated bundle with its metadata.
Before a release, build from a clean committed frontend checkout. Consumers
receive the bundled build and do not need access to the frontend repository.

CI tests configuration encoding and the streaming bridge, checks the bundle
checksum, and compiles the iOS demo. No credentials are required.


## Development and production releases

- `dev` receives Swift changes and reviewed frontend bundle sync PRs.
- `main` is the default branch and contains approved production code. Promote with a `dev` → `main` PR.
- Swift package release versions are independent of the bundled widget's npm version.

After merging a promotion PR, select **Actions → Publish iOS release → Run workflow**,
choose **main**, and enter a new stable version such as `0.1.0` (without `v`).
The workflow validates bundle provenance, runs package/bridge tests, and compiles
both device and simulator builds before creating `v0.1.0` and a GitHub release.
The release is pinned to the production commit selected when the workflow starts;
advancing `main` during its checks does not change what gets tested or tagged.
New versions must increase. A retry may reuse an existing version only when its
tag points to that same tested commit, even if newer versions have since been released.
Recovery detects existing drafts and preserves any newer latest release.
Existing tags are never moved and completed
releases are left unchanged. If tag publication succeeds but GitHub release creation
fails, rerun the failed workflow with **Re-run failed jobs** so it retains the original
commit and completes the missing release. A new dispatch after `main` advances cannot
reuse the old version for a different commit.
The workflow does not merge branches or change repository visibility.

Install production releases in Xcode using a version dependency rule once the first
tag exists. This is a public source package, so app developers and their CI systems
can fetch it without private-repository credentials. There is no binary SDK upload
in this workflow.

Frontend production (`prod`) changes automatically open or update `automation/sync-widget` → `dev`
in this repository after the frontend sync workflow is installed and its cross-repo
credential is configured. Review those PRs after package checks pass, then promote
and release when ready. Native-only improvements can be released without changing
the bundled web widget.

The manual release action is available on the default `main` branch. Use only
`dev` and `main` as long-lived branches; there is no separate iOS `prod` branch.
Both branches require a pull request, one maintainer approval, and a passing
GitHub Actions `check`. New commits dismiss stale approvals; force pushes and
branch deletions are blocked. Reviewers must be different from the PR author.

The frontend workflow uses `CAYLEX_IOS_SYNC_TOKEN` (Contents and Pull requests write
access to this repository) stored in `caylex-frontend` Actions secrets. See
`caylex-frontend/docs/ios-widget-sync.md` for setup and rollout order.
