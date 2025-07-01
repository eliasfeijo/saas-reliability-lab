create or replace function get_pending_notifications(now timestamptz)
returns table (
  id uuid,
  title text,
  user_id uuid,
  notify_at timestamptz,
  endpoint text,
  p256dh text,
  auth text
)
language sql
security definer
as $$
  select
    t.id,
    t.title,
    t.user_id,
    t.notify_at,
    s.endpoint,
    s.p256dh,
    s.auth
  from tasks t
  join push_subscriptions s on t.user_id = s.user_id
  where
    t.notify_at <= now
    and t.notification_sent = false
$$;
