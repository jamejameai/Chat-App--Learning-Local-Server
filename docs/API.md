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

---

### 1.4 Encrypted Attachments

#### `POST /api/v1/attachments/upload-ticket`
Generates authorization ticket to upload encrypted ciphertext blob.

#### `POST /api/v1/attachments/upload`
Uploads ciphertext binary with valid upload ticket.

#### `GET /api/v1/attachments/{id}/download`
Returns temporary signed redirect or binary stream for ciphertext blob.

---

### 1.5 Calling & LiveKit SFU

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
