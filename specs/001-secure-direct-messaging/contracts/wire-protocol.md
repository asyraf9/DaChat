# Contract: Wire Protocol (QR, link, XMPP stanzas, encrypted payloads), v1

This contract covers everything that crosses between two clients, or between a client and Prosody.
The key service HTTP API is in [keyservice-api.md](./keyservice-api.md).

All multi-byte integers are big-endian. "‖" means concatenation.

---

## 1. Connection QR (R9)

```text
QR text  = "DC1:" ‖ base45( payload )                     (alphanumeric mode)
payload  = 0x01 (version)
         ‖ x25519_pub          33 B   (libsignal serialized IdentityKey, 0x05 prefix)
         ‖ sha256(mldsa_pub)   32 B
         ‖ pairing_nonce       16 B   (fresh per PairingSession, expires after 10 min)
```

- **Size**: 82 B before encoding, which fits QR version 10 at error-correction level M.
- **What it omits**: the display name, by design.
- **Scanner rejections**, each with a plain explanation:
  - a wrong prefix or version;
  - an expired nonce, where the peer must refresh;
  - one's own payload (edge case "scanning own QR").

## 2. Safety-code QR (R10)

```text
"DCS1:" ‖ base45( 0x02 ‖ fp_self(32) ‖ fp_peer(32) )
```

The scanner compares, in constant time, its own `(fp_peer, fp_self)` with the scanned
`(fp_self, fp_peer)`.

## 3. Connection link (R9)

```text
https://<main-domain>/c/<link_id_b64url>#<fragment_b64url>
fragment = 0x01 ‖ x25519_pub(33) ‖ sha256(mldsa_pub)(32) ‖ link_secret(32) ‖ flags(1)
flags    = bit0: requires_code_word
```

- `GET /c/*` on the main domain serves a static page with install instructions (edge case "no app").
  The page has no analytics and logs only the route. The fragment never reaches the server.
- Android App Links (`/.well-known/assetlinks.json`) and iOS Universal Links
  (`/.well-known/apple-app-site-association`) route `/c/*` into the app.
- On Linux, the user pastes the link into **Connect → Open a link**.

---

## 4. XMPP usage (Prosody, R6/R16/R17/R18)

| Concern | Mechanism |
|---|---|
| Stream security | TLS 1.3 with the SPKI pin. SASL PLAIN with `(address, session_token)`. Resource `d1` (device 1). |
| Ack ("sent") | XEP-0198 Stream Management, `<r/>` after each outbound message. |
| Delivery ("delivered") | XEP-0184 `<received id=…/>`, sent only after commit (data model §5.4). |
| Offline | `mod_offline`, held until delivered or 30 days at most. No MAM. |
| Blocking | XEP-0191 `<block>` and `<unblock>`. The server drops silently (no error to the blocked sender). |
| Push (iOS) | XEP-0357 enable, toward the key-service push component. |
| Supersede | A stream error `<conflict/>`, plus the text code `superseded`, ends the old session (R8). |

### Message stanza

```xml
<message to="<peer>@<domain>" id="<message uuid>" type="chat">
  <dc xmlns="urn:dachat:msg:1" t="prekey|whisper">BASE64(libsignal ciphertext)</dc>
  <request xmlns="urn:xmpp:receipts"/>
  <no-store xmlns="urn:xmpp:hints"/>       <!-- belt-and-braces: no archive anywhere -->
</message>
```

- `t=prekey` is a libsignal `PreKeySignalMessage` (first message of a session, session reset, or
  connection hello/accept). `t=whisper` is a `SignalMessage`.
- No `<body>`. There is no plaintext fallback element of any kind.
- `<no-store/>` applies to the message stanza. Offline storage still applies, because
  `mod_offline` is configured to store `urn:dachat:msg:1` messages regardless of hints.

Receipts carry only `id`, which the server already sees.

---

## 5. Encrypted payload (plaintext inside the libsignal ciphertext)

Deterministic CBOR (RFC 8949 §4.2), versioned. Unknown `kind` values are dropped and logged by kind
code only. Maximum plaintext is 16 KiB, padded to a 256 B multiple before encryption to reduce
length leakage.

```text
Envelope    = { 0: version(1), 1: kind, 2: body }
kind        = 1 text | 2 connection_hello | 3 connection_accept | 4 connection_reject
            | 5 profile_update | 6 session_reset
```

| kind | body fields | Rules |
|---|---|---|
| `text` (1) | `seq: u64`, `sent_at: i64 ms`, `text: tstr ≤ 4096 UTF-16 units` | `seq` is monotonic per conversation (R17). |
| `connection_hello` (2) | `mldsa_pub: bstr(2592)`, `binding_sig: DualSig`, `display_name: tstr`, `method: qr\|link`, `qr_nonce: bstr(16)?` (qr), `link_id: bstr(16)?`, `link_proof: bstr(32)?`, `code_word: tstr?` (link) | `binding_sig` is over `"dachat/v1/bind" ‖ own_x25519 ‖ own_mldsa ‖ peer_x25519 ‖ peer_mldsa_hash ‖ (qr_nonce \| link_id)`. The receiver verifies both halves and checks `sha256(mldsa_pub)` against the hash it holds. |
| `connection_accept` (3) | `mldsa_pub`, `binding_sig`, `display_name`, `verified: bool` | Sent by the link creator after a valid hello. `verified=true` only when a code word was required and matched. |
| `connection_reject` (4) | `reason: wrong_code_word \| exhausted`, `attempts_left: u8` | Only for code-word links. After 3 failures the creator resolves the link as `exhausted`. |
| `profile_update` (5) | `display_name: tstr` | FR-006. It triggers a backup re-sync on the receiver. |
| `session_reset` (6) | `epoch: u32` | Sent by a restored device (R8). The receiver accepts it only if the identity is unchanged. |

`DualSig = { 0: ed(bstr 64), 1: pq(bstr 4627) }`.

### Hello/accept acceptance rules (receiver side, unit-tested)

- **QR**: `qr_nonce` must equal a live `PairingSession.ownNonce`, and the session must not have been
  used before.
- **Link**:
  - `link_id` must be one of the receiver's own links in `reserved` state, reserved by this sender's
    address.
  - `link_proof` must equal `HMAC-SHA-256(link_secret, "dachat/v1/link-proof" ‖ sender_x25519 ‖ sha256(sender_mldsa))`.
  - The proof check is constant-time.
- A hello from an address that is already a contact with the same identity keeps the existing
  contact (edge case "already connected").
- A hello from a blocked address never gets this far, because it is dropped before decryption.
