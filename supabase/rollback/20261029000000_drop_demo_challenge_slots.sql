-- 20261029000000_demo_challenge_slots.sql を取り消す（体験版のオンライン挑戦の15体の制限をやめる）。
-- 先に Edge Functions（record-challenge-attempt・issue-battle-ticket・demo-challenge-status）を前の版へ戻してから当てる。
-- 注意: 表を消すと、体験版の利用者が挑戦済みのボスの累計も消える（戻すと全員が0体からになる）。
drop function if exists public.demo_challenge_status(text);
drop function if exists public.claim_demo_challenge_slot(uuid, text);
drop table if exists public.demo_challenge_slots;
