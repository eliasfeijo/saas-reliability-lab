create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  title text not null,
  description text,
  start_date timestamptz,
  due_date timestamptz,
  completed boolean default false,
  notify_at timestamptz,
  notification_sent boolean default false,
  priority smallint default 0 check (priority >= 0 and priority <= 5),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  created_at timestamptz default now()
);

alter table tasks enable row level security;
alter table push_subscriptions enable row level security;

alter table push_subscriptions
add constraint unique_endpoint_per_user
unique (user_id, endpoint);

-- For authenticated users to access only their own tasks
create policy "Allow user to access own tasks"
on tasks for all
using (auth.uid() = user_id);

-- Same for push subscriptions
create policy "Allow user to access own subscriptions"
on push_subscriptions for all
using (auth.uid() = user_id);

