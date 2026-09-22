-- A closed business night is historical and must not prevent the next Open
-- Play night from opening on the same local business date.  The partial OPEN
-- index remains the only lifecycle exclusivity rule.
drop index if exists public.business_nights_one_date_per_organization;
create index if not exists business_nights_by_organization_date
  on public.business_nights(organization_id, business_date);
