create function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

create trigger set_tasks_updated_at_trigger
before update on public.tasks
for each row
execute function public.set_updated_at();