CREATE TYPE public.app_role AS ENUM ('admin', 'user');
CREATE TYPE public.workspace_type AS ENUM ('PERSONAL', 'TEAM');
CREATE TYPE public.workspace_role AS ENUM ('OWNER', 'ADMIN', 'MEMBER', 'VIEWER');
CREATE TYPE public.project_status AS ENUM ('PLANNING', 'ACTIVE', 'ON_HOLD', 'COMPLETED', 'ARCHIVED');
CREATE TYPE public.task_status AS ENUM ('BACKLOG', 'TODO', 'IN_PROGRESS', 'IN_REVIEW', 'DONE');
CREATE TYPE public.priority_level AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'URGENT');

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL DEFAULT '',
  avatar_url text,
  timezone text NOT NULL DEFAULT 'UTC',
  onboarding_completed boolean NOT NULL DEFAULT false,
  theme text NOT NULL DEFAULT 'dark' CHECK (theme IN ('dark','light','system')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles_select_self" ON public.profiles FOR SELECT TO authenticated USING (id = auth.uid());
CREATE POLICY "profiles_update_self" ON public.profiles FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL DEFAULT 'user',
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_roles_select_self" ON public.user_roles FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.raw_user_meta_data->>'full_name', ''));
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'user');
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TABLE public.workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  type public.workspace_type NOT NULL,
  owner_id uuid NOT NULL REFERENCES public.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.workspaces TO authenticated;
GRANT ALL ON public.workspaces TO service_role;
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.workspace_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role public.workspace_role NOT NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, user_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.workspace_members TO authenticated;
GRANT ALL ON public.workspace_members TO service_role;
ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;
CREATE INDEX workspace_members_user_idx ON public.workspace_members(user_id, workspace_id);

CREATE OR REPLACE FUNCTION public.workspace_role_for(_workspace_id uuid, _user_id uuid DEFAULT auth.uid())
RETURNS public.workspace_role LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM public.workspace_members WHERE workspace_id = _workspace_id AND user_id = _user_id LIMIT 1
$$;
CREATE OR REPLACE FUNCTION public.is_workspace_member(_workspace_id uuid, _user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.workspace_members WHERE workspace_id = _workspace_id AND user_id = _user_id)
$$;
CREATE OR REPLACE FUNCTION public.can_manage_workspace(_workspace_id uuid, _user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(public.workspace_role_for(_workspace_id, _user_id) IN ('OWNER','ADMIN'), false)
$$;
GRANT EXECUTE ON FUNCTION public.workspace_role_for(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_workspace(uuid, uuid) TO authenticated;

CREATE POLICY "workspaces_select_members" ON public.workspaces FOR SELECT TO authenticated USING (public.is_workspace_member(id));
CREATE POLICY "workspaces_insert_owner" ON public.workspaces FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());
CREATE POLICY "workspaces_update_managers" ON public.workspaces FOR UPDATE TO authenticated USING (public.can_manage_workspace(id)) WITH CHECK (public.can_manage_workspace(id));
CREATE POLICY "workspaces_delete_owner" ON public.workspaces FOR DELETE TO authenticated USING (owner_id = auth.uid());
CREATE POLICY "members_select_members" ON public.workspace_members FOR SELECT TO authenticated USING (public.is_workspace_member(workspace_id));
CREATE POLICY "members_insert_managers_or_self_owner" ON public.workspace_members FOR INSERT TO authenticated WITH CHECK (public.can_manage_workspace(workspace_id) OR (user_id = auth.uid() AND role = 'OWNER' AND EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id = workspace_id AND w.owner_id = auth.uid())));
CREATE POLICY "members_update_managers" ON public.workspace_members FOR UPDATE TO authenticated USING (public.can_manage_workspace(workspace_id)) WITH CHECK (public.can_manage_workspace(workspace_id));
CREATE POLICY "members_delete_managers" ON public.workspace_members FOR DELETE TO authenticated USING (public.can_manage_workspace(workspace_id));

CREATE TABLE public.workspace_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  email text NOT NULL, role public.workspace_role NOT NULL, token_hash text NOT NULL UNIQUE,
  invited_by_id uuid NOT NULL REFERENCES public.profiles(id), expires_at timestamptz NOT NULL,
  accepted_at timestamptz, revoked_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.workspace_invitations TO authenticated;
GRANT ALL ON public.workspace_invitations TO service_role;
ALTER TABLE public.workspace_invitations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "invitations_manage_workspace" ON public.workspace_invitations FOR ALL TO authenticated USING (public.can_manage_workspace(workspace_id)) WITH CHECK (public.can_manage_workspace(workspace_id));
CREATE INDEX invitations_workspace_email_idx ON public.workspace_invitations(workspace_id, lower(email));

CREATE TABLE public.projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120), description text NOT NULL DEFAULT '',
  status public.project_status NOT NULL DEFAULT 'PLANNING', priority public.priority_level NOT NULL DEFAULT 'MEDIUM',
  owner_id uuid NOT NULL REFERENCES public.profiles(id), color text NOT NULL DEFAULT 'violet', icon text,
  start_date date, due_date date, archived_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_date IS NULL OR due_date IS NULL OR start_date <= due_date)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.projects TO authenticated;
GRANT ALL ON public.projects TO service_role;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "projects_select_members" ON public.projects FOR SELECT TO authenticated USING (public.is_workspace_member(workspace_id));
CREATE POLICY "projects_insert_contributors" ON public.projects FOR INSERT TO authenticated WITH CHECK (public.workspace_role_for(workspace_id) IN ('OWNER','ADMIN','MEMBER'));
CREATE POLICY "projects_update_contributors" ON public.projects FOR UPDATE TO authenticated USING (public.workspace_role_for(workspace_id) IN ('OWNER','ADMIN','MEMBER')) WITH CHECK (public.workspace_role_for(workspace_id) IN ('OWNER','ADMIN','MEMBER'));
CREATE POLICY "projects_delete_managers" ON public.projects FOR DELETE TO authenticated USING (public.can_manage_workspace(workspace_id));
CREATE INDEX projects_workspace_status_idx ON public.projects(workspace_id, status, updated_at DESC);

CREATE TABLE public.project_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE, role public.workspace_role NOT NULL DEFAULT 'MEMBER', joined_at timestamptz NOT NULL DEFAULT now(), UNIQUE(project_id,user_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_members TO authenticated;
GRANT ALL ON public.project_members TO service_role;
ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "project_members_select_workspace" ON public.project_members FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.projects p WHERE p.id=project_id AND public.is_workspace_member(p.workspace_id)));
CREATE POLICY "project_members_manage_workspace" ON public.project_members FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM public.projects p WHERE p.id=project_id AND public.can_manage_workspace(p.workspace_id))) WITH CHECK (EXISTS (SELECT 1 FROM public.projects p WHERE p.id=project_id AND public.can_manage_workspace(p.workspace_id)));

CREATE TABLE public.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200), description text NOT NULL DEFAULT '',
  status public.task_status NOT NULL DEFAULT 'TODO', priority public.priority_level NOT NULL DEFAULT 'MEDIUM',
  creator_id uuid NOT NULL REFERENCES public.profiles(id), assignee_id uuid REFERENCES public.profiles(id),
  start_date date, due_date date, estimated_minutes integer CHECK (estimated_minutes IS NULL OR estimated_minutes >= 0),
  position numeric NOT NULL DEFAULT 0, completed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_date IS NULL OR due_date IS NULL OR start_date <= due_date)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.task_workspace(_project_id uuid) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$ SELECT workspace_id FROM public.projects WHERE id=_project_id $$;
GRANT EXECUTE ON FUNCTION public.task_workspace(uuid) TO authenticated;
CREATE POLICY "tasks_select_members" ON public.tasks FOR SELECT TO authenticated USING (public.is_workspace_member(public.task_workspace(project_id)));
CREATE POLICY "tasks_insert_contributors" ON public.tasks FOR INSERT TO authenticated WITH CHECK (creator_id=auth.uid() AND public.workspace_role_for(public.task_workspace(project_id)) IN ('OWNER','ADMIN','MEMBER'));
CREATE POLICY "tasks_update_contributors" ON public.tasks FOR UPDATE TO authenticated USING (public.workspace_role_for(public.task_workspace(project_id)) IN ('OWNER','ADMIN','MEMBER')) WITH CHECK (public.workspace_role_for(public.task_workspace(project_id)) IN ('OWNER','ADMIN','MEMBER'));
CREATE POLICY "tasks_delete_contributors" ON public.tasks FOR DELETE TO authenticated USING (public.workspace_role_for(public.task_workspace(project_id)) IN ('OWNER','ADMIN','MEMBER'));
CREATE INDEX tasks_project_status_position_idx ON public.tasks(project_id,status,position);
CREATE INDEX tasks_assignee_due_idx ON public.tasks(assignee_id,due_date);

CREATE TABLE public.subtasks (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE, title text NOT NULL, is_completed boolean NOT NULL DEFAULT false, position numeric NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.task_dependencies (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), predecessor_task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE, successor_task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE, UNIQUE(predecessor_task_id,successor_task_id), CHECK(predecessor_task_id<>successor_task_id));
CREATE TABLE public.labels (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE, name text NOT NULL, color text NOT NULL, UNIQUE(workspace_id,name));
CREATE TABLE public.task_labels (task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE, label_id uuid NOT NULL REFERENCES public.labels(id) ON DELETE CASCADE, PRIMARY KEY(task_id,label_id));
CREATE TABLE public.comments (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE, author_id uuid NOT NULL REFERENCES public.profiles(id), content text NOT NULL CHECK(char_length(content) BETWEEN 1 AND 10000), created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.attachments (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE, project_id uuid REFERENCES public.projects(id) ON DELETE CASCADE, task_id uuid REFERENCES public.tasks(id) ON DELETE CASCADE, uploaded_by_id uuid NOT NULL REFERENCES public.profiles(id), original_filename text NOT NULL, storage_key text NOT NULL UNIQUE, mime_type text NOT NULL, size_bytes bigint NOT NULL CHECK(size_bytes>0), created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.notifications (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE, workspace_id uuid REFERENCES public.workspaces(id) ON DELETE CASCADE, type text NOT NULL, title text NOT NULL, message text NOT NULL, target_type text, target_id uuid, read_at timestamptz, deduplication_key text UNIQUE, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.activity_logs (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE, actor_id uuid REFERENCES public.profiles(id), entity_type text NOT NULL, entity_id uuid NOT NULL, action text NOT NULL, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.subtasks, public.task_dependencies, public.labels, public.task_labels, public.comments, public.attachments, public.notifications, public.activity_logs TO authenticated;
GRANT ALL ON public.subtasks, public.task_dependencies, public.labels, public.task_labels, public.comments, public.attachments, public.notifications, public.activity_logs TO service_role;
ALTER TABLE public.subtasks ENABLE ROW LEVEL SECURITY; ALTER TABLE public.task_dependencies ENABLE ROW LEVEL SECURITY; ALTER TABLE public.labels ENABLE ROW LEVEL SECURITY; ALTER TABLE public.task_labels ENABLE ROW LEVEL SECURITY; ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY; ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY; ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY; ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.task_is_visible(_task_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$ SELECT EXISTS(SELECT 1 FROM public.tasks t JOIN public.projects p ON p.id=t.project_id WHERE t.id=_task_id AND public.is_workspace_member(p.workspace_id)) $$;
CREATE OR REPLACE FUNCTION public.task_is_editable(_task_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$ SELECT EXISTS(SELECT 1 FROM public.tasks t JOIN public.projects p ON p.id=t.project_id WHERE t.id=_task_id AND public.workspace_role_for(p.workspace_id) IN ('OWNER','ADMIN','MEMBER')) $$;
GRANT EXECUTE ON FUNCTION public.task_is_visible(uuid), public.task_is_editable(uuid) TO authenticated;
CREATE POLICY "subtasks_select" ON public.subtasks FOR SELECT TO authenticated USING(public.task_is_visible(task_id)); CREATE POLICY "subtasks_write" ON public.subtasks FOR ALL TO authenticated USING(public.task_is_editable(task_id)) WITH CHECK(public.task_is_editable(task_id));
CREATE POLICY "dependencies_select" ON public.task_dependencies FOR SELECT TO authenticated USING(public.task_is_visible(predecessor_task_id)); CREATE POLICY "dependencies_write" ON public.task_dependencies FOR ALL TO authenticated USING(public.task_is_editable(predecessor_task_id)) WITH CHECK(public.task_is_editable(predecessor_task_id));
CREATE POLICY "labels_select" ON public.labels FOR SELECT TO authenticated USING(public.is_workspace_member(workspace_id)); CREATE POLICY "labels_write" ON public.labels FOR ALL TO authenticated USING(public.workspace_role_for(workspace_id) IN ('OWNER','ADMIN','MEMBER')) WITH CHECK(public.workspace_role_for(workspace_id) IN ('OWNER','ADMIN','MEMBER'));
CREATE POLICY "task_labels_select" ON public.task_labels FOR SELECT TO authenticated USING(public.task_is_visible(task_id)); CREATE POLICY "task_labels_write" ON public.task_labels FOR ALL TO authenticated USING(public.task_is_editable(task_id)) WITH CHECK(public.task_is_editable(task_id));
CREATE POLICY "comments_select" ON public.comments FOR SELECT TO authenticated USING(public.task_is_visible(task_id)); CREATE POLICY "comments_insert" ON public.comments FOR INSERT TO authenticated WITH CHECK(author_id=auth.uid() AND public.task_is_visible(task_id)); CREATE POLICY "comments_update_own" ON public.comments FOR UPDATE TO authenticated USING(author_id=auth.uid()) WITH CHECK(author_id=auth.uid()); CREATE POLICY "comments_delete_own" ON public.comments FOR DELETE TO authenticated USING(author_id=auth.uid());
CREATE POLICY "attachments_select" ON public.attachments FOR SELECT TO authenticated USING(public.is_workspace_member(workspace_id)); CREATE POLICY "attachments_insert" ON public.attachments FOR INSERT TO authenticated WITH CHECK(uploaded_by_id=auth.uid() AND public.workspace_role_for(workspace_id) IN ('OWNER','ADMIN','MEMBER')); CREATE POLICY "attachments_delete" ON public.attachments FOR DELETE TO authenticated USING(uploaded_by_id=auth.uid() OR public.can_manage_workspace(workspace_id));
CREATE POLICY "notifications_select_own" ON public.notifications FOR SELECT TO authenticated USING(recipient_id=auth.uid()); CREATE POLICY "notifications_update_own" ON public.notifications FOR UPDATE TO authenticated USING(recipient_id=auth.uid()) WITH CHECK(recipient_id=auth.uid());
CREATE POLICY "activity_select_members" ON public.activity_logs FOR SELECT TO authenticated USING(public.is_workspace_member(workspace_id));
CREATE INDEX notifications_recipient_unread_idx ON public.notifications(recipient_id,read_at,created_at DESC); CREATE INDEX activity_workspace_created_idx ON public.activity_logs(workspace_id,created_at DESC);

CREATE OR REPLACE FUNCTION public.set_updated_at() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$ BEGIN NEW.updated_at=now(); RETURN NEW; END; $$;
CREATE TRIGGER profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER workspaces_updated BEFORE UPDATE ON public.workspaces FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER projects_updated BEFORE UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER subtasks_updated BEFORE UPDATE ON public.subtasks FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER comments_updated BEFORE UPDATE ON public.comments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "flowzeno_storage_select" ON storage.objects FOR SELECT TO authenticated USING (bucket_id='flowzeno-files' AND name ~ '^[0-9a-f-]{36}/' AND public.is_workspace_member((split_part(name,'/',1))::uuid));
CREATE POLICY "flowzeno_storage_insert" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id='flowzeno-files' AND name ~ '^[0-9a-f-]{36}/' AND public.workspace_role_for((split_part(name,'/',1))::uuid) IN ('OWNER','ADMIN','MEMBER'));
CREATE POLICY "flowzeno_storage_delete" ON storage.objects FOR DELETE TO authenticated USING (bucket_id='flowzeno-files' AND name ~ '^[0-9a-f-]{36}/' AND public.workspace_role_for((split_part(name,'/',1))::uuid) IN ('OWNER','ADMIN','MEMBER'));
