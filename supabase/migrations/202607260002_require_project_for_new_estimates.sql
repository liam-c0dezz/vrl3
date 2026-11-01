-- Preserve historical unassigned estimates while preventing any new estimate
-- from being created without a canonical customer project.
--
-- NOT VALID skips the 62 legacy rows during creation, but PostgreSQL enforces
-- the constraint for every new or subsequently changed row.

alter table public.estimates
  drop constraint if exists estimates_project_required;

alter table public.estimates
  add constraint estimates_project_required
  check (project_id is not null) not valid;
