import type { Answer, Sources, Result } from './app.contract.d.ts';

export const grants = '';
const sources: Sources = {
  phoneStatus: (_args, _store, _storage, native) => {
    if (!native?.available) {
      return { status: 'Not connected', connected: false, desktop: '', channels: [], working: 0, canCreate: false };
    }
    native.watch('connection');
    return native.call({ op: 'status' }) as Result<'phoneStatus'>;
  },
  createChat: async (_args, _store, _storage, native) => {
    if (!native?.available) throw new Error('The phone session is unavailable.');
    return await native.later({ op: 'create' }) as Result<'createChat'>;
  },
};
export const answer: Answer = (source, args, store, storage, native) =>
  sources[source](args, store, storage, native);
