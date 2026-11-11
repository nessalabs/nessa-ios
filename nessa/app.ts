import { threadSources } from './thread';
import { agentsSources } from './agents';
import { connectionSources } from './connection';
import type { Answer, Sources, Result } from './app.contract.d.ts';

export const grants = '';
const sources: Sources = {
  ...agentsSources,
  ...threadSources,
  ...connectionSources,
  phoneStatus: (_args, _store, _storage, native) => {
    if (!native?.available) {
      return { desktopID: '', greeting: '', waiting: false, pairingNeeded: true, status: 'Not connected', connected: false, desktop: '', channels: [], working: 0, canCreate: false };
    }
    native.watch('connection');
    return native.call({ op: 'status' }) as Result<'phoneStatus'>;
  },
  chatList: ([screen, key], _store, _storage, native) => {
    if (!native?.available || (screen !== 'archived' && screen !== 'shared' && screen !== 'channel')) return { title: '', rows: [], error: '' };
    native.watch('lists');
    return native.call({ op: 'list', screen, key }) as Result<'chatList'>;
  },
  readShared: async ([id, owner], _store, _storage, native) => {
    if (!id || !owner || !native?.available) return { owner, chat: id, title: 'Chat', failed: false, bubbles: [] };
    return await native.later({ op: 'sharedTranscript', id, owner }) as Result<'readShared'>;
  },
  retryLink: async (_args, _store, _storage, native) => {
    if (!native?.available) return { done: false };
    return await native.later({ op: 'retryLink' }) as Result<'retryLink'>;
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
