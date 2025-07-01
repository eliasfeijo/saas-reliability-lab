create function public.set_user_id()
returns trigger as $$
begin
  new.user_id := auth.uid();
  return new;
end;
$$ language plpgsql security definer;

create trigger set_user_id_trigger
before insert on public.tasks
for each row
execute function public.set_user_id();