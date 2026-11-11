import type { Answer, Result } from './app.contract.d.ts';

export const grants = '';

export const answer: Answer = (_source, _args, _store, _storage, native) => {
  if (!native?.available) return { status: 'Not connected', connected: false, desktop: '' };
  native.watch('connection');
  return native.call({ op: 'status' }) as Result<'phoneStatus'>;
};
