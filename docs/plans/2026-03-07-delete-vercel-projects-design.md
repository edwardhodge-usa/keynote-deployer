# Design: Delete Vercel Projects from History

**Date:** 2026-03-07
**Status:** Approved
**Goal:** Add a Delete button to each history entry that deletes the Vercel project and removes the local history entry.

## Flow

1. User clicks "Delete" on a history entry
2. Confirmation replaces button area: "Delete [name].vercel.app permanently?" with Cancel + Delete buttons
3. On confirm: DELETE Vercel project via REST API, remove from local history, update UI
4. On error: show inline error, still remove from local history (project may already be gone)

## Files to Modify

- `electron/vercelDeployer.ts` — add `deleteVercelProject(projectId, token, teamId)` function
- `electron/main.ts` — add IPC handler `delete-project`
- `electron/preload.ts` — expose `deleteProject` via context bridge
- `electron/fileOperations.ts` — add `removeHistoryEntry(id)` function
- `src/components/History.tsx` — add Delete button + inline confirmation per entry
- `src/types/index.ts` — add `deleteProject` to electron API type

## API

Vercel REST API: `DELETE /v9/projects/{projectId}?teamId={teamId}`
- Auth: `Authorization: Bearer {token}`
- 200/204 = success, 404 = already deleted (treat as success)

## UI Details

- Red "Delete" button (btn-danger btn-sm) after "Open" button
- Confirmation inline (replaces button area): "Delete [name].vercel.app permanently?" + Cancel (ghost) + Delete (danger)
- Loading state: spinner on Delete button, all buttons disabled
- Success: entry removed from list
- Error: red text below entry, entry remains (retry or dismiss)

## Security

- Uses existing Vercel token from settings
- Confirmation required before any deletion
- 404 from Vercel treated as success (clean up local history regardless)

---

# Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add delete button to history entries that removes Vercel project + local history entry.

**Architecture:** Backend IPC for `delete-vercel-project` already exists in main.ts + preload.ts. Need to add `removeHistoryEntry` to fileOperations, wire a new IPC handler, expose it in preload, and update History.tsx with delete UI + confirmation.

**Tech Stack:** Electron 33, React 18, TypeScript 5.7, Vercel REST API

---

### Task 1: Add removeHistoryEntry + IPC wiring

**Files:**
- Modify: `electron/fileOperations.ts` — add `removeHistoryEntry(id)`
- Modify: `electron/main.ts` — add `remove-history-entry` IPC handler, update import
- Modify: `electron/preload.ts` — expose `removeHistoryEntry`, add to ElectronAPI interface

**Step 1: Add removeHistoryEntry to fileOperations.ts**

Add after `addHistoryEntry` (line 58):

```typescript
export async function removeHistoryEntry(id: string): Promise<void> {
  const history = await loadHistory()
  const filtered = history.filter(entry => entry.id !== id)
  await fs.writeFile(getHistoryPath(), JSON.stringify(filtered, null, 2), 'utf-8')
}
```

**Step 2: Add IPC handler in main.ts**

Add import of `removeHistoryEntry` to line 4:
```typescript
import { loadSettings, saveSettings, loadHistory, addHistoryEntry, removeHistoryEntry, validateKeynoteFolder, detectVercelToken } from './fileOperations'
```

Add handler after the `load-history` handler (after line 234):
```typescript
// Remove a history entry by ID
ipcMain.handle('remove-history-entry', async (_event, id: string) => {
  try {
    await removeHistoryEntry(id)
    return { success: true }
  } catch (error) {
    return { success: false, error: String(error) }
  }
})
```

**Step 3: Update preload.ts**

Add to the ElectronAPI interface (after line 11):
```typescript
removeHistoryEntry: (id: string) => Promise<IpcResponse<void>>
```

Add to the electronAPI object (after line 39):
```typescript
removeHistoryEntry: (id: string) => ipcRenderer.invoke('remove-history-entry', id),
```

**Step 4: Update the existing delete-vercel-project handler to treat 404 as success**

In `main.ts` lines 290-291, change:
```typescript
    if (!response.ok) {
      const errorBody = await response.text()
      return { success: false, error: `API error: ${response.status} ${errorBody}` }
    }
```
To:
```typescript
    if (!response.ok && response.status !== 404) {
      const errorBody = await response.text()
      return { success: false, error: `API error: ${response.status} ${errorBody}` }
    }
```

**Step 5: Commit**

```bash
git add electron/fileOperations.ts electron/main.ts electron/preload.ts
git commit -m "feat: add removeHistoryEntry and wire IPC for history deletion"
```

---

### Task 2: Update History.tsx with delete button + confirmation

**Files:**
- Modify: `src/components/History.tsx` — add delete button, inline confirmation, loading/error states

**Step 1: Replace History.tsx content**

The full updated component adds:
- `confirmingDelete` state: tracks which entry ID is showing confirmation
- `deletingId` state: tracks which entry is currently being deleted
- `deleteError` state: tracks error message per entry
- `handleDelete` function: calls `deleteVercelProject(projectName)` then `removeHistoryEntry(id)`, updates local state
- Inline confirmation UI replacing button area
- Red "Delete" button in normal state

```typescript
import { useState, useEffect } from 'react'
import type { HistoryEntry } from '../types'

export default function History() {
  const [entries, setEntries] = useState<HistoryEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [copied, setCopied] = useState<string | null>(null)
  const [confirmingDelete, setConfirmingDelete] = useState<string | null>(null)
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [deleteError, setDeleteError] = useState<Record<string, string>>({})

  useEffect(() => {
    loadHistory()
  }, [])

  const loadHistory = async () => {
    setLoading(true)
    const res = await window.electron.loadHistory()
    if (res.success && res.data) {
      setEntries(res.data)
    }
    setLoading(false)
  }

  const copyUrl = async (url: string, id: string) => {
    await window.electron.copyToClipboard(url)
    setCopied(id)
    setTimeout(() => setCopied(null), 2000)
  }

  const handleDelete = async (entry: HistoryEntry) => {
    setDeletingId(entry.id)
    setDeleteError((prev) => ({ ...prev, [entry.id]: '' }))

    try {
      // Delete from Vercel (use projectName — API accepts name or ID)
      const vercelResult = await window.electron.deleteVercelProject(entry.projectName)
      if (!vercelResult.success) {
        // Show error but still remove from local history
        setDeleteError((prev) => ({
          ...prev,
          [entry.id]: vercelResult.error || 'Vercel deletion failed',
        }))
      }
    } catch {
      // Vercel delete failed — still clean up locally
    }

    // Always remove from local history
    await window.electron.removeHistoryEntry(entry.id)
    setEntries((prev) => prev.filter((e) => e.id !== entry.id))
    setDeletingId(null)
    setConfirmingDelete(null)
  }

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr)
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    })
  }

  return (
    <div className="h-full flex flex-col">
      <div className="window-drag h-14 flex-shrink-0" />

      <div className="flex-1 overflow-y-auto px-8 pb-8">
        <h1 className="text-2xl font-semibold mb-6">Deployment History</h1>

        {loading ? (
          <div className="text-center py-12">
            <span className="spinner text-primary" />
          </div>
        ) : entries.length === 0 ? (
          <div className="text-center py-12">
            <div className="text-4xl mb-3 text-gray-300 dark:text-gray-600">{'\u23F3'}</div>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              No deployments yet. Deploy your first Keynote presentation!
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {entries.map((entry) => (
              <div key={entry.id} className="card p-4">
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <h3 className="text-sm font-semibold truncate">{entry.title}</h3>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                      {entry.projectName} &middot; {entry.slideCount} slides &middot; {entry.fixesApplied} fixes
                    </p>
                    <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
                      {formatDate(entry.date)}
                    </p>
                  </div>

                  <div className="flex gap-2 flex-shrink-0">
                    {confirmingDelete === entry.id ? (
                      <>
                        <button
                          onClick={() => setConfirmingDelete(null)}
                          disabled={deletingId === entry.id}
                          className="btn btn-ghost btn-sm"
                        >
                          Cancel
                        </button>
                        <button
                          onClick={() => handleDelete(entry)}
                          disabled={deletingId === entry.id}
                          className="btn btn-danger btn-sm"
                        >
                          {deletingId === entry.id ? (
                            <span className="spinner spinner-sm" />
                          ) : (
                            'Confirm Delete'
                          )}
                        </button>
                      </>
                    ) : (
                      <>
                        <button
                          onClick={() => copyUrl(entry.url, entry.id)}
                          className="btn btn-secondary btn-sm"
                        >
                          {copied === entry.id ? 'Copied!' : 'Copy URL'}
                        </button>
                        <button
                          onClick={() => window.electron.openUrl(entry.url)}
                          className="btn btn-ghost btn-sm"
                        >
                          Open
                        </button>
                        <button
                          onClick={() => setConfirmingDelete(entry.id)}
                          className="btn btn-danger btn-sm"
                        >
                          Delete
                        </button>
                      </>
                    )}
                  </div>
                </div>

                {confirmingDelete === entry.id && (
                  <p className="text-xs text-red-400 mt-2">
                    This will permanently delete {entry.projectName}.vercel.app
                  </p>
                )}

                {deleteError[entry.id] && (
                  <p className="text-xs text-red-400 mt-2">
                    {deleteError[entry.id]} — removed from history
                  </p>
                )}

                <div className="mt-2 px-2 py-1 rounded bg-gray-100 dark:bg-gray-700/50">
                  <p className="text-xs font-mono text-gray-600 dark:text-gray-400 truncate">
                    {entry.url}
                  </p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
```

**Step 2: Commit**

```bash
git add src/components/History.tsx
git commit -m "feat: add delete button with confirmation to deployment history"
```

---

### Task 3: Build verification + test

**Step 1: Run dev build**

```bash
cd "/Users/EdwardHodge_1/Library/Mobile Documents/com~apple~CloudDocs/03_Custom Apps/Keynote Deployer"
npm run electron:dev
```

Verify:
- History page shows Delete button on each entry
- Clicking Delete shows inline confirmation with "Cancel" and "Confirm Delete"
- Clicking Cancel returns to normal button state
- Clicking Confirm Delete removes the entry (and Vercel project if token is configured)

**Step 2: Commit any fixes if needed**

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete delete Vercel projects from history"
```
