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
  chatList: ([screen], _store, _storage, native) => {
    if (!native?.available || (screen !== 'archived' && screen !== 'shared')) return { rows: [], error: '' };
    native.watch('lists');
    return native.call({ op: 'list', screen }) as Result<'chatList'>;
  },
  refreshList: async ([screen], _store, _storage, native) => {
    if (!native?.available) return { done: true };
    return await native.later({ op: 'refresh', screen }) as Result<'refreshList'>;
  },
  unarchiveChat: async ([id], _store, _storage, native) => {
    if (!native?.available) throw new Error('The phone session is unavailable.');
    return await native.later({ op: 'unarchive', id }) as Result<'unarchiveChat'>;
  },
  createChat: async (_args, _store, _storage, native) => {
    if (!native?.available) throw new Error('The phone session is unavailable.');
    return await native.later({ op: 'create' }) as Result<'createChat'>;
  },
};
export const answer: Answer = (source, args, store, storage, native) =>
  sources[source](args, store, storage, native);
