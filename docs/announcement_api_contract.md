# Announcement API Contract (Client/Server Aligned)

This document defines the backend contract used by the client implementation in this repository.

## Scope

- Scene: `chat_list` (chat list top banner)
- Default frequency cap: `max_impressions = 3`
- Platform targeting via a single field: `target_platforms`

## Platform Enum

Use lowercase values:

- `all`
- `android`
- `ios`
- `web`
- `windows`
- `macos`
- `linux`

## API 1: Query Active Announcements

- Method: `GET`
- Path: `/api/announcements/active`
- Query:
  - `scene` (required, example: `chat_list`)
  - `platform` (required, one enum value above)

### Success Response

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "announcements": [
      {
        "announcement_id": "ann_20260316_android_bugfix",
        "title": "Android 已知问题说明",
        "body": "当前版本 Android 端存在上传失败问题，正在修复。",
        "target_platforms": ["android"],
        "scene": "chat_list",
        "priority": 100,
        "max_impressions": 3,
        "min_interval_hours": 24,
        "dismissible": true,
        "require_ack": false,
        "action_label": "查看详情",
        "action_url": "https://stg.example.com/notices/ann_20260316_android_bugfix",
        "start_at": "2026-03-16T00:00:00Z",
        "end_at": "2026-03-30T00:00:00Z"
      }
    ]
  }
}
```

### Field Rules

- `announcement_id`: required, unique string.
- `target_platforms`: required list. Use `["all"]` for all platforms.
- `max_impressions`: optional, default `3` if omitted.
- `min_interval_hours`: optional, default `0` if omitted.
- `priority`: optional, default `0`. Higher value wins.
- `scene`: optional, default `chat_list`.
- `dismissible`: optional, default `true`.
- `require_ack`: optional, default `false`. If true, client sends `acknowledge` on CTA click or close.
- `start_at` / `end_at`: optional validity window (ISO 8601 UTC).

## API 2: Track Announcement Events

- Method: `POST`
- Path: `/api/announcements/{announcement_id}/events`

### Request Body

```json
{
  "event_type": "impression",
  "scene": "chat_list",
  "platform": "android",
  "occurred_at": "2026-03-16T09:45:12.000Z"
}
```

### Event Enum

- `impression`
- `click`
- `dismiss`
- `acknowledge`

### Success Response

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

## Counting Semantics

- One `impression` is counted when banner stays visible for at least 1 second.
- Client sends at most one impression per announcement per app session.
- Server should aggregate by user and announcement, then enforce `max_impressions`.

## Server-Side Selection Rules (Recommended)

1. Filter by `scene`.
2. Filter by `platform` against `target_platforms`.
3. Filter by time window (`start_at <= now <= end_at`).
4. Filter by user display count (`< max_impressions`).
5. Return candidates sorted by `priority desc`, then newest first.

## STG Validation Checklist

1. Create one `target_platforms=["android"]` announcement in STG.
2. Confirm Android sees banner, iOS/Web/Desktop do not.
3. Trigger 3 impressions across sessions; the 4th session should not show it.
4. Confirm `click` and `dismiss` events are received by STG endpoint.
5. Confirm no non-STG environment is called during verification.

You can use the helper script:

- `scripts/stg-announcement-smoke.sh`
