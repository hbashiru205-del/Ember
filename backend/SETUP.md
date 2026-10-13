# Backend setup (from a phone browser)
1. supabase.com -> New project (free). Settings -> API: copy Project URL + anon key.
2. SQL Editor -> paste backend/schema.sql -> Run.
3. Authentication -> enable Email. Storage -> create private bucket `photos`.
4. Never put the service_role key in the front-end. It is only for the payment webhook that calls credit_tokens().
