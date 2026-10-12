# Saved history display

A chat can render before asynchronous disk hydration supplies its saved view.
The reply layout previously cached that empty result using only the agent name.
Hydration then replaced the message view, and an identical live publication did
not invalidate the layout. Messages existed in the phone snapshot and gateway
while the thread appeared blank.

Layout reuse now compares every input: name, turns and reply links. The suspended
hydration regression fails on the previous source and passes with the change;
all 122 package tests, architecture/design checks and the simulator build pass.
Independent review found no actionable issues. A cold-installed live build showed
both existing chats' messages in the simulator, including the image attachment,
agent reply and the older chat's reply thread. This is display-cache verification,
not proof that the unfinished native retained-sync integration is complete.
