# Mini Telegram — API & WebSocket Gateway Contracts

## 1. REST API Specification (`/api/v1`)

All endpoints accept and return `application/json` (unless binary upload/download).
Standard authentication: `Authorization: Bearer <access_token>`

### 1.1 Authentication & Registration

#### `POST /api/v1/auth/invitation/validate`
Validates an invitation code before rendering account creation screen.
- **Request**: `{ "code": "invite_a8f93b..." }`
- **Response `200 OK`**:
  ```json
  {
    "valid": true,
    "role": "member",
    "expires_at": "2026-11-01T00:00:00Z"
  }
  ```

#### `POST /api/v1/auth/register-with-invite`
Accepts invitation and provisions account with initial device identity keys.
- **Request**:
  ```json
  {
    "invitation_code": "invite_a8f93b...",
    "username": "channarith",
    "display_name": "Channarith",
    "password": "SecurePassword123!",
    "device_name": "iPhone 16 Pro",
    "identity_key_pub": "<base64_curve25519_pubkey>",
    "signed_prekey_pub": "<base64_curve25519_signed_prekey>",
    "signed_prekey_sig": "<base64_ed25519_signature>",
    "signed_prekey_id": 1,
    "one_time_prekeys": [
      { "key_id": 1, "public_key": "<base64_pubkey>" },
      { "key_id": 2, "public_key": "<base64_pubkey>" }
    ]
  }
  ```
- **Response `201 Created`**:
  ```json
  {
    "user": {
      "id": "c1f7b029-...",
      "username": "channarith",
      "display_name": "Channarith",
      "role": "member"
    },
    "device": {
      "id": "e8d91024-...",
      "device_name": "iPhone 16 Pro"
    },
    "tokens": {
      "access_token": "eyJhbGciOi...",
      "refresh_token": "rt_8a7df1..."
    }
  }
  ```

#### `POST /api/v1/auth/login`
Authenticates existing user and registers device session.
- **Request**: `{ "username": "channarith", "password": "...", "device_id": "...", ... }`
- **Response `200 OK`**: `{ "tokens": { ... }, "user": { ... } }`

#### `GET /api/v1/auth/me` and `PATCH /api/v1/auth/profile`
The authenticated user's profile response includes `developer_profile`. Patching that field saves
the public developer portfolio and returns the updated profile.

```json
{
  "developer_profile": {
    "headline": "iOS developer building thoughtful apps",
    "skills": ["Swift", "SwiftUI", "TypeScript"],
    "projects": [
      {
        "id": "project-uuid",
        "title": "Our Chat",
        "summary": "A private messaging app",
        "technologies": ["SwiftUI", "NestJS"],
        "repository_url": "https://github.com/example/our-chat",
        "live_url": "https://example.com",
        "is_pinned": true
      }
    ],
    "website_url": "https://example.com",
    "github_url": "https://github.com/example",
    "social_links": {
      "linkedin_url": "https://linkedin.com/in/example",
      "instagram_url": "https://instagram.com/example",
      "x_url": "https://x.com/example"
    },
    "currently_building": "A new app",
    "work_availability": "open_to_opportunities",
    "location": "Phnom Penh"
  }
}
```

Developer-profile content is visible to everyone who can open a profile. Allowed availability values
are `open_to_opportunities`, `available_for_work`, and `not_available`; omit the field when it is not
listed. The profile supports up to 40 skills and 20 projects.

#### `POST /api/v1/auth/refresh`
Rotates refresh token and returns fresh access token.
- **Request**: `{ "refresh_token": "rt_8a7df1..." }`
- **Response `200 OK`**: `{ "access_token": "...", "refresh_token": "rt_new..." }`

---

### 1.2 Devices & Cryptographic Key Distribution

#### `GET /api/v1/devices/{user_id}/prekey-bundle`
Fetches cryptographic prekey bundle to initiate an X3DH session with a recipient device.
- **Response `200 OK`**:
  ```json
  {
    "user_id": "c1f7b029-...",
    "device_id": "e8d91024-...",
    "identity_key_pub": "<base64>",
    "signed_prekey_pub": "<base64>",
    "signed_prekey_sig": "<base64>",
    "signed_prekey_id": 1,
    "one_time_prekey": {
      "key_id": 42,
      "public_key": "<base64>"
    }
  }
  ```
  *(Note: `one_time_prekey` is consumed atomically upon dispatch).*

#### `POST /api/v1/devices/prekeys/refill`
Uploads a new batch of one-time prekeys when the pool runs low (< 10 keys).

---

### 1.3 Conversations & Messaging

#### `GET /api/v1/conversations`
List user's active conversations, latest sequence ID, unread count, and metadata.

#### `POST /api/v1/conversations`
Create a 1-to-1 conversation, group, or announcement channel.

#### `GET /api/v1/conversations/{id}/sync`
Incremental synchronization cursor endpoint:
- **Query Params**: `since_sequence=145&limit=50`
- **Response `200 OK`**:
  ```json
  {
    "conversation_id": "...",
    "messages": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "sender_user_id": "...",
        "sender_device_id": "...",
        "sequence_id": 146,
        "envelope_type": "e2ee_text",
        "encrypted_payload": "<base64_ciphertext>",
        "iv": "<base64_iv>",
        "reply_to_message_id": null,
        "is_edited": false,
        "is_deleted": false,
        "created_at": "2026-10-17T20:15:00Z"
      }
    ],
    "has_more": false,
    "latest_sequence_id": 146
  }
  ```

#### `POST /api/v1/conversations/{id}/messages`
Submits an encrypted message envelope (with idempotent client-provided UUID).

### 1.4 Live Friend Locations

Location reads and standard sharing mutations require JWT authentication. Sharing is opt-in and
remains active until the owner stops it. On each sharing session, the owner explicitly chooses
which mutual accepted friends can view the location. That audience is fixed for the session: adding
a friend later does not grant access. A user can read locations only for active users who selected
them and still have a mutual accepted friendship. Shares created before stop-token support are
cleared by the migration; owners must start a new session with an explicit audience.

#### `GET /api/v1/locations/friends`
Returns the current live locations of accepted friends who are sharing. The server retains at most
one current coordinate per sharing user; it does not retain a route history.

#### `GET /api/v1/locations/me`
Returns `{ "sharing": true, "location": { ..., "viewer_ids": ["..."] } }` when the authenticated
user has an active share, or `{ "sharing": false, "location": null }`. The iOS client uses this to
restore the sharing state and audience after relaunch. Each location includes a `share_id` that
identifies that sharing session.

#### `POST /api/v1/locations/me`
Starts a sharing session and snapshots the explicitly selected audience. Each `viewer_id` must
identify a mutual accepted friend. At least one friend is required. `stop_token` is a 64-character
random hexadecimal capability used only to stop this share if the login session expires; the server
stores only its SHA-256 hash. A new `share_id` is returned for each session so clients can ignore
delayed updates or stop events belonging to an older share.
- **Request**: `{ "latitude": 37.78, "longitude": -122.41, "heading": 92.5, "accuracy": 8, "viewer_ids": ["<friend UUID>"], "stop_token": "<64 hex characters>" }`

#### `PUT /api/v1/locations/me`
Updates the caller's current position during an active share. The server emits the update only to
the selected audience. It does not start a session.
- **Request**: `{ "latitude": 37.78, "longitude": -122.41, "heading": 92.5, "accuracy": 8 }`
- Latitude must be between -90 and 90, longitude between -180 and 180, heading between 0 and 360
  (exclusive), and accuracy between 0 and 10,000 meters.

#### `DELETE /api/v1/locations/me`
Stops sharing, deletes the caller's current coordinate, and notifies accepted friends that sharing
has stopped. Only the selected audience is notified. `location.stopped` events include the
`share_id`, allowing clients to avoid clearing a newer session when an older stop event arrives.

#### `POST /api/v1/locations/revoke`
Unauthenticated, rate-limited, stop-only fallback. The high-entropy token can delete only the active
share that created it; it cannot read location data or identify the owner. Repeated revocations are
safe and return `{ "sharing": false }`.
- **Request**: `{ "stop_token": "<64 hex characters>" }`

---

### 1.5 Encrypted Attachments

#### `POST /api/v1/attachments/upload-ticket`
Generates authorization ticket to upload encrypted ciphertext blob.

#### `POST /api/v1/attachments/upload`
Uploads ciphertext binary with valid upload ticket.

#### `GET /api/v1/attachments/{id}/download`
Returns temporary signed redirect or binary stream for ciphertext blob.

---

### 1.6 Calling & LiveKit SFU

#### `POST /api/v1/calls/initiate`
Initiates audio or video call for conversation, reserves LiveKit room, generates access tokens.

#### `POST /api/v1/calls/{id}/join`
Validates membership and issues LiveKit participant token with room permissions.

#### `POST /api/v1/calls/{id}/end`
Terminates call and calculates total duration.

---

## 2. WebSocket Gateway Contracts

Endpoint: `wss://<host>/socket.io` or `wss://<host>/ws/gateway`
Authentication: Query param `?token=<jwt_access_token>` or auth handshake payload.

### 2.1 Client-to-Server Events

| Event | Payload | Description |
| :--- | :--- | :--- |
| `message.submit` | `{ conversation_id, id, envelope_type, ciphertext, iv, reply_to }` | Submit encrypted message. |
| `message.receipt` | `{ message_id, status: 'delivered' \| 'read' }` | Acknowledge delivery or read state. |
| `typing.update` | `{ conversation_id, is_typing: true \| false }` | Typing indicator (ephemeral). |
| `presence.heartbeat` | `{ status: 'online' }` | Keepalive presence pulse. |
| `call.signal` | `{ call_id, target_device_id, signal_data }` | WebRTC signaling payload. |

### 2.2 Server-to-Client Events

| Event | Payload | Description |
| :--- | :--- | :--- |
| `message.accepted` | `{ id, sequence_id, created_at }` | Ack to sender that server persisted envelope. |
| `message.new` | Full encrypted message envelope | Push new message to online recipients. |
| `message.read` | `{ message_id, user_id, device_id, timestamp }` | Read receipt broadcast. |
| `typing.update` | `{ conversation_id, user_id, is_typing }` | Typing state update. |
| `presence.update` | `{ user_id, is_online, last_seen }` | User presence update. |
| `call.invite` | `{ call_id, conversation_id, caller, call_type, room_token }` | Incoming call alert. |
| `call.participant` | `{ call_id, user_id, status }` | Call participant join/leave alert. |
| `call.ended` | `{ call_id, duration_seconds, reason }` | Call termination notice. |
| `sync.required` | `{ conversation_id, latest_sequence_id }` | Prompt client to perform gap-sync. |
| `location.update` | `{ user_id, share_id, username, display_name, avatar_url, latitude, longitude, heading?, accuracy?, updated_at }` | Current location update from an accepted friend. |
| `location.stopped` | `{ user_id, share_id }` | An accepted friend stopped sharing, or this account stopped on another device; remove only that share’s marker or stop local tracking. |
