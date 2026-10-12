# Flowzeno full-stack project management platform

## Goal
Build Flowzeno as a real, secure, responsive project management and collaboration application—not a static dashboard. Preserve the complete specification while adapting its backend to the user-approved Lovable-native architecture.

## Architecture
- Use the existing TanStack Start, React 19, TypeScript, Tailwind CSS v4, TanStack Router/Query, React Hook Form, Zod, Recharts, and Lucide stack.
- Use Lovable Cloud PostgreSQL, authentication, private file storage, migrations, and row-level access policies instead of a separate Express/Prisma/Render backend.
- Put signed-in pages under the managed authenticated route layout; protect every data operation independently with authenticated server functions and database policies.
- Use typed feature modules for workspaces, projects, tasks, collaboration, notifications, analytics, search, files, and AI; keep server-only logic behind secure boundaries.
- Use real persisted records throughout. Demo content, where offered, will be explicitly labeled and isolated from production defaults.

## Phase 1 — Foundation and identity
- Establish Flowzeno’s dark-first premium design system, light theme, wordmark, favicon, typography, spacing, status colors, motion, and accessible UI primitives.
- Build the public home page with working Product, Features, Solutions, documentation, contact, privacy, terms, sign-in, and get-started destinations; omit fake billing or checkout.
- Enable Lovable Cloud and email/password authentication; add login, signup, forgot/reset password, logout, session-aware navigation, protected routes, and onboarding.
- Build the responsive application shell: collapsible sidebar, mobile drawer, workspace switcher, global search entry, quick-create menu, notifications, theme control, help, and user menu.
- Create the relational schema, indexes, grants, access policies, audit-safe timestamps, and migrations for profiles, workspaces, membership, invitations, projects, tasks, labels, subtasks, dependencies, comments, attachments, notifications, activities, preferences, and supporting job/usage records.

## Phase 2 — Core project and task workflows
- Implement personal and team workspaces with Owner, Admin, Member, and Viewer permissions enforced on every read and write.
- Implement project create, view, edit, membership, archive, restore, and confirmed deletion; calculate progress from completed non-cancelled tasks with safe zero-task handling.
- Implement task CRUD, assignment, statuses, priorities, dates, labels, subtasks, comments, attachments metadata, bulk actions, and deep-linked task details.
- Add Kanban and list modes using real records, scalable loading, filtering, sorting, persisted ordering, optimistic updates, and rollback on failure.
- Cover loading, empty, success, validation, slow, failure, forbidden, missing, and pending states without false success messages.

## Phase 3 — Planning and collaboration
- Add calendar month/week/day views and a functional responsive timeline with real task dates, today marker, grouping, zoom, missing-date handling, and task selection.
- Add cycle-safe task dependencies; begin with reliable read-only timeline behavior before enabling any edit interaction that cannot be persisted safely.
- Add team invitations with hashed, single-use, expiring and revocable tokens; implement acceptance and role management transactionally.
- Add comments, server-created activity events, notification inbox and unread count, deduplicated deadline reminders, and permission-aware polling.
- Add global authorized search and reusable URL-backed filters across projects, tasks, members, files, and appropriate comments.

## Phase 4 — Insights, files, and AI
- Build the dashboard and analytics from real aggregates: project/task totals, completion, overdue/due-soon work, trends, distributions, progress, workload, activity, and date filters.
- Add authorized CSV exports generated from server-filtered data.
- Add private file uploads and downloads with size/type checks, sanitized names, unique keys, progress, signed access, deletion rules, and orphan handling.
- Add the AI assistant for task breakdowns, project plans, priorities, summaries, deadline suggestions, weekly summaries, and next actions through Lovable AI.
- Keep AI context permission-scoped and minimal; treat output as suggestions and require confirmation before changing records. Surface provider errors honestly.

## Phase 5 — Quality, security, and delivery
- Add validation, request limits, secure error responses, role checks, object-level authorization, safe logging, and defenses against cross-workspace ID guessing.
- Test forms, navigation, permissions, CRUD, ordering, date validation, invitations, notifications, files, AI failure handling, constraints, and transactions.
- Verify the complete workflow: register → onboard → create workspace/project/task → assign and update status → dashboard reflects changes → another user is denied access.
- Audit keyboard access, focus, dialogs, contrast, reduced motion, screen-reader labels, mobile/tablet/desktop layouts, and overflow.
- Document the actual Lovable-native architecture, permissions matrix, schema, server interfaces, environment requirements, setup, recovery guidance, and GitHub/GitLab workflow. Publishing uses Lovable; the original Render-specific instructions are replaced by equivalent Lovable deployment guidance.

## Main routes
- Public: `/`, `/login`, `/signup`, `/forgot-password`, `/reset-password`, `/onboarding`, plus separate Product, Features, Solutions, Docs, Contact, Privacy, and Terms pages.
- Application: `/app/dashboard`, `/app/tasks`, `/app/projects`, `/app/projects/new`, project/task detail and project settings, `/app/calendar`, `/app/timeline`, `/app/analytics`, `/app/team`, `/app/files`, `/app/notifications`, `/app/ai`, and profile/account/workspace/notification/security settings.
- Every content route receives unique Flowzeno metadata; every referenced navigation path is implemented in the same change.

## Acceptance criteria
- Authentication, protected navigation, personal workspaces, team roles, projects, tasks, Kanban/list/calendar/timeline, comments, notifications, search, files, analytics, and AI operate on persisted authorized data.
- Workspace isolation is enforced by both server operations and database policies; changing an ID never grants access.
- Drag, edit, bulk, upload, invitation, and AI-assisted actions either persist successfully or visibly roll back/fail—never fake success.
- All primary controls work, all data screens cover required states, and no placeholder pages or dead primary actions remain.
- Automated checks and the end-to-end workflow pass before the application is described as complete.

## Technical notes
- The approved Lovable-native choice supersedes the prompt’s literal Express, Prisma, separate Render services, and local password-hashing implementation while preserving their security and relational-data intent.
- Lovable Cloud manages authentication credentials and sessions; application profiles and authorization data remain in PostgreSQL.
- Private storage replaces local filesystem uploads. Lovable AI replaces a user-managed provider key unless a later requirement explicitly selects another provider.
- Scheduled reminders use bounded, idempotent, database-backed jobs with a lock and persistent failure state; they never depend on an open browser tab.
