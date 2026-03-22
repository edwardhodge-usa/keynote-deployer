# Secure Embed Mode — Implementation Plan

> **For agentic workers:** Execute tasks sequentially. All modify the same codebase.

**Goal:** Add a "Secure Embed" option to the Keynote Deployer that prevents downloading when presentations are embedded in the Framer client portal.

**Architecture:** Toggle in the deploy confirm phase. When enabled: (1) inject download-prevention JS into the generated index.html, (2) write a vercel.json with CSP frame-ancestors headers restricting embedding to allowed domains.

**Tech Stack:** Electron + React + TypeScript (existing app)

**Project root:** `/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer/`

---

## File Map

```
src/types/index.ts              — ADD secureEmbed to ProcessRequest, embedAllowedDomains to AppSettings
electron/fileOperations.ts      — ADD embedAllowedDomains default
electron/keynoteProcessor.ts    — ACCEPT secureEmbed flag, inject protections into generated HTML
electron/vercelDeployer.ts      — WRITE vercel.json with CSP headers when secureEmbed
electron/main.ts                — PASS secureEmbed through IPC pipeline
src/components/Deploy.tsx       — ADD Secure Embed toggle in confirm phase
```

---

### Task 1: Types + Settings

**Files:**
- Modify: `src/types/index.ts`
- Modify: `electron/fileOperations.ts`

- [ ] **Step 1: Add secureEmbed to ProcessRequest**

In `src/types/index.ts`, add `secureEmbed?: boolean` to `ProcessRequest`:

```typescript
export interface ProcessRequest {
  folderPath: string
  projectName: string
  metadata: KeynoteMetadata
  secureEmbed?: boolean
}
```

- [ ] **Step 2: Add embedAllowedDomains to AppSettings**

In `src/types/index.ts`, add to `AppSettings`:

```typescript
export interface AppSettings {
  // ... existing fields ...
  secureEmbed: boolean
  embedAllowedDomains: string
}
```

- [ ] **Step 3: Add defaults in fileOperations.ts**

In `electron/fileOperations.ts`, add to `DEFAULT_SETTINGS`:

```typescript
secureEmbed: true,
embedAllowedDomains: '*.imaginelabstudios.com *.framer.app',
```

- [ ] **Step 4: Commit**

```bash
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" add src/types/index.ts electron/fileOperations.ts
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" commit -m "feat: add secureEmbed types and settings defaults"
```

---

### Task 2: HTML Protections in Keynote Processor

**Files:**
- Modify: `electron/keynoteProcessor.ts`

- [ ] **Step 1: Update processKeynoteFolder signature**

Add `secureEmbed` parameter to `processKeynoteFolder`:

```typescript
export async function processKeynoteFolder(
  folderPath: string,
  metadata: KeynoteMetadata,
  onProgress: ProgressCallback,
  secureEmbed: boolean = false
): Promise<ProcessResult> {
```

Pass it to `generateIndexHtml`:

```typescript
const indexHtml = generateIndexHtml(metadata.slideCount, secureEmbed)
```

- [ ] **Step 2: Update generateIndexHtml to accept secureEmbed**

```typescript
function generateIndexHtml(slideCount: number, secureEmbed: boolean = false): string {
```

When `secureEmbed` is true, add a third `<script>` block after the existing navigation script:

```typescript
const secureEmbedScript = secureEmbed ? `<script>${buildSecureEmbedScript()}</script>` : ''
```

Add it to the HTML output array before the closing `</body>`.

- [ ] **Step 3: Implement buildSecureEmbedScript()**

```typescript
function buildSecureEmbedScript(): string {
  return `
(function(){
  // Disable right-click context menu
  document.addEventListener('contextmenu',function(e){e.preventDefault()});
  // Disable drag (prevents drag-to-desktop)
  document.addEventListener('dragstart',function(e){e.preventDefault()});
  // Disable text selection
  document.body.style.userSelect='none';
  document.body.style.webkitUserSelect='none';
  // Block save/print/view-source keyboard shortcuts
  document.addEventListener('keydown',function(e){
    if((e.ctrlKey||e.metaKey)&&['s','p','u'].indexOf(e.key.toLowerCase())!==-1){
      e.preventDefault();
    }
  });
})();
`.trim()
}
```

- [ ] **Step 4: Commit**

```bash
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" add electron/keynoteProcessor.ts
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" commit -m "feat: inject download-prevention JS when secureEmbed enabled"
```

---

### Task 3: Vercel Headers

**Files:**
- Modify: `electron/vercelDeployer.ts`

- [ ] **Step 1: Update deployToVercel signature**

Add `secureEmbed` and `embedAllowedDomains` parameters:

```typescript
export async function deployToVercel(
  folderPath: string,
  projectName: string,
  token: string,
  teamId: string,
  onProgress: ProgressCallback,
  secureEmbed: boolean = false,
  embedAllowedDomains: string = ''
): Promise<DeployResult> {
```

- [ ] **Step 2: Write vercel.json before deployment**

After the project is ensured (step 12) and before CLI deployment (step 13), if `secureEmbed` is true, write a `vercel.json` to `folderPath`:

```typescript
if (secureEmbed) {
  // Build frame-ancestors from allowed domains
  const domains = embedAllowedDomains
    .split(/[\s,]+/)
    .filter(Boolean)
    .map(d => d.startsWith('https://') ? d : `https://${d}`)
    .join(' ')

  const vercelConfig = {
    headers: [
      {
        source: '/(.*)',
        headers: [
          {
            key: 'Content-Security-Policy',
            value: `frame-ancestors 'self' ${domains}`
          },
          {
            key: 'X-Content-Type-Options',
            value: 'nosniff'
          }
        ]
      }
    ]
  }

  const fs = await import('fs/promises')
  await fs.writeFile(
    path.join(folderPath, 'vercel.json'),
    JSON.stringify(vercelConfig, null, 2),
    'utf-8'
  )
}
```

Add `import path from 'path'` at the top if not already present.

- [ ] **Step 3: Commit**

```bash
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" add electron/vercelDeployer.ts
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" commit -m "feat: write vercel.json with CSP frame-ancestors for secure embed"
```

---

### Task 4: Wire IPC + Deploy UI Toggle

**Files:**
- Modify: `electron/main.ts`
- Modify: `src/components/Deploy.tsx`

- [ ] **Step 1: Update main.ts IPC handler**

Find the IPC handler that receives the `ProcessRequest` and calls `processKeynoteFolder` and `deployToVercel`. Pass `secureEmbed` through to both functions. Also load `embedAllowedDomains` from settings and pass to `deployToVercel`.

Read `electron/main.ts` first to find the exact handler.

- [ ] **Step 2: Add Secure Embed toggle to Deploy.tsx**

In the `confirm` phase JSX (between the project name input and the Deploy button), add a checkbox:

```tsx
<label style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 12, fontSize: 13, color: 'var(--text-secondary, #999)' }}>
  <input
    type="checkbox"
    checked={secureEmbed}
    onChange={(e) => setSecureEmbed(e.target.checked)}
  />
  Secure Embed — disable downloads, restrict embedding to portal
</label>
```

Add state: `const [secureEmbed, setSecureEmbed] = useState(true)` (default on).

Pass `secureEmbed` in the process request when calling the IPC.

- [ ] **Step 3: Commit**

```bash
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" add electron/main.ts src/components/Deploy.tsx
git -C "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" commit -m "feat: secure embed toggle in deploy UI + IPC wiring"
```

---

### Task 5: Build Verification

- [ ] **Step 1: Type check**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npx tsc --noEmit
```

Fix any type errors.

- [ ] **Step 2: Dev build test**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer" && npm run electron:dev
```

Verify the app launches and the Secure Embed checkbox appears in the deploy confirm phase.

- [ ] **Step 3: Final commit if fixes needed**

---

## Execution Route

| Signal | Route |
|--------|-------|
| 5 tasks, multi-file, sequential deps | `/do` (subagents) |
