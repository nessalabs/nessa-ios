import type { Result, Sources } from './app.contract.d.ts';

export const agentsSources: Pick<Sources, 'agentsOverview' | 'agentsCommand'> = {
  agentsOverview: ([active], _store, _storage, native) => {
    if (!active || !native?.available) {
      return { groups: [], pendingChats: [], complete: true, pendingUnavailable: false, connected: false, canAct: false, scope: 0, connection: 0 };
    }
    native.watch('agents');
    return native.call({ op: 'agents' }) as Result<'agentsOverview'>;
  },
  agentsCommand: async ([verb, id, stamp, option, scope, connection], _store, _storage, native) => {
    if (!native?.available) return { chat: '' };
    return await native.later({ op: 'agentCommand', verb, id, stamp, option, scope, connection }) as Result<'agentsCommand'>;
  },
};
