# AI QuickNote Project Rules

* Keep the product ultra-lightweight and simple.
* Core functionality must remain fully usable without AI or voice.
* AI and voice are optional enhancement layers only.
* Prefer OS/system capabilities and existing APIs over custom implementations.
* Reuse existing code before adding new code.
* All platform adapters must call the same Core Capability Layer.
* Keep ACI capability semantics consistent across iOS, Android, and MCP.
* Keep local data user-owned, traceable, permission-controlled, and auditable.
* Do not expand into a full productivity suite, finance suite, or knowledge-management system.
* Build only what is required for the current task.
* Prefer deterministic code for deterministic work.
* Run the smallest relevant tests after changes and required regression tests before completion.



\# Identity and Data Ownership Rule



\## Anonymous use

\- Users may install and browse the app without registration.

\- Browsing public content, product information, public marketplace content, onboarding, settings previews, and other actions that do not create persistent private user data must not require registration.



\## First persistent save

\- The first time the user performs any action that creates or persists private local data, the app must check whether a confirmed user identity exists.

\- If no confirmed registered/logged-in identity exists, the app must trigger the unified registration/login flow before the save is finalized.

\- Persistent local private data must always belong to a clearly identified registered user.

\- Anonymous persistent private data is not allowed.



\## Separation of responsibilities

Identity, Backup, and Sharing are separate systems and must not be coupled.



\### Identity

\- Answers: who does this data belong to?

\- Registration/login establishes ownership identity only.

\- Registration must not automatically imply backup, upload, sync, or sharing.



\### Backup

\- Answers: how is the user's private data preserved and restored?

\- Backup is responsible for local/cloud backup, restore, device migration, and recovery policy.

\- Backup may use user-selected destinations such as iCloud, Google Drive, or other supported backup targets.

\- Backup must not depend on the sharing/publishing system.



\### Sharing / Upload / Publish

\- Answers: which data leaves the private user space, where it goes, and who can access it?

\- Data must leave the private space only through explicit user action or previously authorized sharing behavior.

\- Sharing/uploading one record must not change the backup policy for the user's private database.



\## Core invariant

\- Registration does not cause automatic backup.

\- Registration does not cause automatic upload.

\- Backup does not imply sharing.

\- Sharing does not imply backup.

\- The systems may cooperate, but there is no automatic causal dependency between them.



\## Save flow

User initiates first persistent save

→ check identity

→ if no confirmed identity: trigger registration/login

→ after identity is confirmed: save locally under that user

→ backup follows backup policy

→ sharing/upload occurs only through explicit sharing logic



\## Product principle

Browse anonymously.

Persist privately only with a confirmed owner.

Keep identity, backup, and sharing logically independent.

