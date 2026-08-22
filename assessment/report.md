# Fullstack Product Engineer - Case Study Report

**Candidate:** [Your Name]
**Date:** August 21, 2026

## Overview
This report outlines the end-to-end execution of the Rakamin AI Interview Platform revamp. By taking a first-principles approach, I identified gaps that actively harmed the users (privacy leaks) and product fidelity (malicious early terminations), prioritizing those over vanity refactors.

## 1. Deep Context & Domain Immersion
- **The Users:** Assessors handling candidates must trust that the output portfolio genuinely reflects a complete interview. The AI acts as a proxy for the organization.
- **The Candidates:** Interacting with an AI can be stressful. If their data is mishandled or their connection fails abruptly ending the session before they have shown their skills, it dramatically impacts their likelihood of being hired.
- **UU PDP (Data Privacy):** The platform logs the direct voice transcription of the candidates. When this reaches system logs in production (which are often pushed to Datadog or ELK), it creates a dangerous PII sprawl.

## 2. Defining Problem & Gap to Ideal Condition

| Severity | Component | Issue | Impact |
| -------- | --------- | ----- | ------ |
| **P0** | Backend (`LiveClient`) | PII Transcription Log Leak | Raw candidate transcripts were emitted to `Rails.logger`, violating UU PDP compliance. |
| **P0** | Fullstack (`sessions_controller` & frontend) | Insecure Session Termination Boundary | `audio_complete` trusted the client to end the session. An attacker with a token could bypass coverage checks completely. |
| **P1** | Backend (`EndHandler`) | Portfolio Generation Race Condition | Duplicate calls (Timeout + Manual abort) simultaneously bypassed `portfolio.present?` checks, crashing transactions. |

## 3. Revamp Strategy & Trade-offs (Fixing `audio_complete`)

### Evaluated Options
**Option A: Enforce Boundary Validation on REST + UI Graceful Fallback (Chosen)**
We maintain the REST endpoint but independently enforce `coverage_maps.all?(covered)`. If the user hits it prematurely, return `422`. The frontend is updated to break out of infinite retries on `422` and prompt the user gracefully.
- *Pros:* Highly secure. Safely maintains the intended architecture (draining audio queues before end).
- *Cons:* Timing micro-gap between WS and REST. Solved safely via a slight thread-safe yield.

**Option B: Terminate at the WebSocket Edge**
The moment the backend WS detects `all_covered`, it closes the DB session and closes the socket.
- *Pros:* Impossible to spoof from the frontend.
- *Cons:* Poor UI/UX. Cuts off the AI's "Thank you" wrap-up message and causes harsh client drops.

## 4. Monozukuri Implementation

I executed the following changes across the full stack:
1. **PII Sanitization:** Cleaned up `live_client.rb` to redact `[inputTx]` strings before logging. We still retain critical observability (`turnComplete`, `has_audio`).
2. **Secure Session Boundary:** Updated `audio_complete` to block termination if `CoverageMap` states are insufficient. Added negative RSpec edge cases to prove.
3. **Atomic Safety:** Overhauled `Sessions::EndHandler` to use Rails native `Portfolio.create_or_find_by!` ensuring robust Postgres `UNIQUE` constraint handling natively without full transaction aborts.
4. **Resilient UI (Vite+React):** Modded the `useAudioComplete` infinite retry loop in `InterviewPage.tsx` to detect `422` rejections and revert to `active` state gracefully, preventing absolute UI locking.

## GitHub Submission
All changes are cleanly decoupled and committed off the feature branch:
**Branch:** `danibik-feat/assesment-backend-depth` (Pending PR).

## 5. Feature Extension: Recruiter Workflows (Vacancy & Email Invites)

### 5.1. Database & Models
- Added `vacancy_id` as a nullable reference to `assessments` to ensure legacy standalone assessments remain functional.
- Injected `candidate_email`, `invitation_status` (default: `pending`), `invitation_sent_at`, and `invitation_error` to `sessions`. Added native strict email Regex validation.

### 5.2. API & Email Delivery
- Extended `POST /assessments/:id/sessions` to capture emails organically.
- Added `POST /sessions/:id/invitation` to queue invitations. Prevents duplicate sends natively by verifying `invitation_status == 'sent'`.
- Deployed `CandidateMailer` supported by `InvitationSenderWorker` inside existing Sidekiq orchestration. This handles unhandled SMTP failures by bounded retries (3) and safely records final fail states on the session (`invitation_status: 'failed'`).

### 5.3. Predictable React UI
- **Vacancy Handoff:** Added context-aware *Create Assessment* routing (`useLocation().state`) in `VacancyEditPage.tsx` to prefill role titles and core skills into `AssessmentNewPage.tsx` seamlessly.
- **Invitations:** Upgraded `AssessmentInvitePage.tsx` modal to ask for email. Realtime status badges immediately reveal *Wait/Send/Sent/Failed*. Added a *Retry Invite* conditional render that surfaces `invitation_error`.

### 5.4. Focused Test Verifications
Implemented `spec/requests/api/v1/vacancy_invitation_workflow_spec.rb`. Validates 12 specific assertions including:
- Legacy assessment validity.
- 422 triggers for malformed candidate emails.
- SMTP exception handling -> `failed` transition.
- Redundant send blocks.
- Vacancy -> Assessment data propagation.

### 5.5. Local Email Debugging (Mailcatcher)
To ensure reliable email delivery testing without affecting live servers, Mailcatcher was integrated into the local development environment. This provides a local SMTP sink and Web UI to inspect actual email payloads, verifying that invitation links are generated correctly using `APP_BASE_URL` and ensuring Sidekiq workers can successfully dispatch emails.

## Remaining Risks
1. **Production SMTP Configuration:** `CandidateMailer.deliver_now` requires valid Downstream SMTP config within Rails environment secrets. If unavailable, it correctly falls to `failed` and allows retrying later.
2. **Long Polling Overhead:** UI currently polls aggressively. Future revisions of scaling architecture should migrate session listening to ActionCable.

## 6. Minimum Baseline Verification (Seeded Fault)

As part of the minimum baseline verification, a seeded fault was injected into the `scratch` branch to ensure the test suite correctly identifies regressions. 

**Test Failure Output:**
```text
Failures:

  1) User Callbacks downcases email before saving
     Failure/Error: expect(user.email).to eq('uppercase@example.com')
     
       expected: "uppercase@example.com"
            got: "UPPERCASE@EXAMPLE.COM"
```

**Commit History (Fault & Revert):**
```text
64fe858 (HEAD -> scratch) Revert "chore: inject seeded fault for testing purposes"
acdbac4 chore: inject seeded fault for testing purposes
```

*End of Report.*
