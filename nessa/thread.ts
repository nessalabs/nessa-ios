import type { Result, Sources } from './app.contract.d.ts';

export const threadSources: Pick<Sources, 'threadSnapshot' | 'threadCommand' | 'threadDetailsData'> = {
  threadSnapshot: ([chat], _store, _storage, native) => {
    if (chat === '' || !native?.available) {
      return { chat, name: '', connected: false, working: false, empty: false, recent: false,
        error: '', reply: '', menu: false, sent: 0, rows: [], reviews: [] };
    }
    native.watch('thread');
    return native.call({ op: 'threadSnapshot', chat }) as Result<'threadSnapshot'>;
  },
  threadDetailsData: ([chat], _store, _storage, native) => {
    if (chat === '' || !native?.available) {
      return { chat: '', name: '', description: '', model: '', working: false, prompt: '',
        accessReported: false, access: [], recent: false, loaded: false, error: '', artifacts: [], activity: [] };
    }
    native.watch('thread');
    return native.call({ op: 'threadDetailsData', chat }) as Result<'threadDetailsData'>;
  },
  threadCommand: async ([command, chat, review, option], _store, _storage, native) => {
    if (!native?.available) throw new Error('The phone session is unavailable.');
    return await native.later({ op: 'threadCommand', command, chat, review, option }) as Result<'threadCommand'>;
  },
};
