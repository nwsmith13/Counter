-- Center-wide Bowling Schedule enum expansion.
-- This migration must commit before later migrations reference the new labels.
alter type public.bsb_booking_type add value if not exists 'PARTY';
alter type public.bsb_booking_type add value if not exists 'OPEN_PLAY';
