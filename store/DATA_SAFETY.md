# Data safety answers (Play Console > App content > Data safety)

**Does the app collect or share required user data types?** Yes. **Is all data encrypted in transit?** Yes (HTTPS/WSS). **Can users request data deletion?** Yes (once the delete-account feature + web link are added).

| Play data type | Collected | Shared with 3rd parties | Optional | Purpose |
|---|---|---|---|---|
| Personal info > **Name**, company / role | Yes | No | No | App functionality, account management |
| Personal info > **Phone number** | Yes | No (SMS is sent through our SMS provider as a processor) | No | Account management, authentication |
| Personal info > **User IDs** (username) | Yes | No | No | App functionality |
| Contacts > **Contacts** | Yes (only the contacts the user ticks and confirms) | No | Yes | App functionality (refer a contact) |
| Messages > **Other in-app messages** | Yes | No | No | App functionality |
| Photos and videos > **Photos** | Yes (picked by user) | No | Yes | App functionality |
| Audio > **Voice** | Not collected/stored (live call audio is peer-to-peer, not recorded) | – | – | – |
| App activity > **Other user-generated content** (asks, replies, updates) | Yes | No | No | App functionality |
| Device or other IDs > **Push token** | Yes | No (Firebase Cloud Messaging is a processor) | Yes | Notifications |

Security practices: data encrypted in transit; users can request deletion; no data sold; no ads.
