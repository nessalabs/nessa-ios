import type { Result, Sources } from './app.contract.d.ts';

export const connectionSources: Pick<Sources, 'connectionState' | 'connectionCommand'> = {
  connectionState: (_args, _store, _storage, native) => {
    if (!native?.available) {
      return {
        connected: false, saved: false, busy: false, setupBusy: false, hasCredential: false,
        hasError: false, available: false, linked: false, desktop: '', desktopID: '',
        phase: 'idle', peer: '', peers: [], failure: '', validCode: false,
      };
    }
    native.watch('link');
    return native.call({ op: 'connectionState' }) as Result<'connectionState'>;
  },
  connectionCommand: async ([action, key], _store, _storage, native) => {
    if (!native?.available) throw new Error('The phone connection is unavailable.');
    return await native.later({ op: 'connectionCommand', action, key }) as Result<'connectionCommand'>;
  },
};
