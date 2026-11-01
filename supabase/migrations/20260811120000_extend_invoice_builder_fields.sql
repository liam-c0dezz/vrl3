-- Persist the richer invoice builder without changing existing invoice ownership or RLS.

alter table public.invoices
  add column if not exists due_at date,
  add column if not exists company_name text not null default '',
  add column if not exists payment_methods jsonb not null default '[]'::jsonb,
  add column if not exists disclaimer text not null default '',
  add column if not exists attachments jsonb not null default '[]'::jsonb;

alter table public.invoices
  add constraint invoices_payment_methods_array
    check (jsonb_typeof(payment_methods) = 'array') not valid,
  add constraint invoices_attachments_array
    check (jsonb_typeof(attachments) = 'array') not valid;

alter table public.invoices validate constraint invoices_payment_methods_array;
alter table public.invoices validate constraint invoices_attachments_array;

comment on column public.invoices.payment_methods is
  'Display-only payment instructions selected by the contractor; no payment credentials are processed.';
