import type { Result, Sources } from './app.contract.d.ts';

export const composerSources: Pick<Sources, 'composerSnapshot' | 'composerCommand'> = {
  composerSnapshot: ([visit, screen, key], _store, _storage, native) => {
    const empty = { token: '', scope: '', visit: '', screen: '', key: '', text: '', seq: 0, placeholder: '',
      reason: '', role: '', autoFocus: false, sendable: false, attachable: false, sending: false,
      preparing: false, listening: false, finishing: false, running: '', canStop: false,
      errorTitle: '', error: '', files: [], recovery: [] };
    if (!native?.available) return empty;
    native.watch('composer');
    const result = native.call({ op: 'composerSnapshot', visit, screen, key }) as Partial<Result<'composerSnapshot'>>;
    return result.token ? result as Result<'composerSnapshot'> : { ...empty, scope: result.scope ?? '' };
  },
  composerCommand: async ([visit, screen, key, token, action, value, sequence], _store, _storage, native) => {
    if (!native?.available) return { done: false };
    if (action === 'edit') {
      native.call({ op: 'composerEdit', visit, screen, key, token, value, sequence });
      return { done: true };
    }
    return await native.later({ op: 'composerCommand', visit, screen, key, token, action, value, sequence }) as Result<'composerCommand'>;
  },
};
