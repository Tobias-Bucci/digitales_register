# Store privacy answers for polls (#131)

Polls add one thing the stores ask about: a **random installation ID** that the
app creates the first time the user votes and sends with the vote, together
with the chosen answer. Nothing here has been submitted; copy what fits into
each console after checking the current wording of its questions. The general
review notes are in [STORE_PRIVACY_CHECKLIST.md](STORE_PRIVACY_CHECKLIST.md).

Facts to rely on:

- Sent only when the user votes: `option_id` and the installation ID, to
  `api.digitalesregister.com` (through Cloudflare). Reading polls sends no ID.
- The ID is a UUIDv4 from a secure random source, stored locally. It is not
  derived from the device, the account or an advertising ID. Reinstalling or
  deleting the app data creates a new one.
- The server stores a keyed hash of poll and ID (HMAC-SHA-256) per poll and the
  answer, without time, IP address or account. Hashes are deleted 14 days after
  the poll closes (configurable); only aggregated counts remain.
- No school login needed. No analytics, no advertising, no sharing with third
  parties beyond the hosting providers (Cloudflare as proxy, Oracle as host).
- Encrypted in transit (HTTPS). Data deletion: the ID is removed with the app
  data; server hashes expire automatically; a request by email is possible but
  a vote can generally not be matched to a person.

## Google Play, Data safety

| Question | Answer |
|---|---|
| Data type | **Device or other IDs** (the installation ID) and **App activity → Other user-generated content** or **Other actions** for the poll answer, whichever the current form offers for survey answers |
| Collected | Yes, when the user votes |
| Shared | No (Cloudflare and Oracle act as service providers) |
| Processed ephemerally | No |
| Required or optional | Optional: only collected if the user chooses to vote |
| Purpose | App functionality (counting one vote per device) |
| Encrypted in transit | Yes |
| Users can request deletion | Yes, by email; the hash is deleted automatically after the poll |

## Apple App Store, App Privacy

| Question | Answer |
|---|---|
| Data type | **Identifiers → Device ID** (app-generated installation ID); **User Content → Other User Content** (poll answer) |
| Linked to the user | No. Not linked to an account or identity; the server keeps a per-poll hash only |
| Used for tracking | No |
| Purpose | App Functionality |

Wording for the review notes, if asked:

> Polls are optional. When a user votes, the app sends the chosen answer and a
> random identifier the app generated for this installation, so that each
> device votes once. The identifier is not derived from the device or any
> account, is not used for tracking or advertising, and the server stores only
> a keyed hash of it per poll, deleted after the poll ends.

## Microsoft Store, privacy questions

> The app uses an optional poll feature. When the user votes, the app sends the
> chosen answer and a random installation identifier created by the app to
> api.digitalesregister.com, so that one vote per device counts. No account,
> school, device or advertising identifier is sent. The server keeps a keyed
> hash of the identifier per poll and deletes it after the poll ends. Privacy
> policy: https://tobias-bucci.github.io/privacy-policy-digitales_register/

## Flathub description (metainfo)

A sentence for `linux/*.metainfo.xml` or the store listing, if polls are
mentioned:

> Take part in short polls from the app's announcements: one vote per device,
> without your name or a school account.

Privacy note, if the listing has one:

> Voting in a poll sends the answer and a random installation ID created by the
> app. The server keeps only a keyed hash of it per poll and deletes it after
> the poll ends.

## Honest limits (for any reviewer question)

Votes are counted per device, not per person: reinstalling or clearing the
app's data gives a new ID, and the same person can vote once in the app and
once in a browser on the web voting page. Fine for informal school polls, not
for binding votes.
