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
