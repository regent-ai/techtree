# JSON-RPC Methods

`regent-cli` uses JSON-RPC 2.0 over a Unix domain socket. Each request and response is one JSON line.

## Runtime

- `runtime.ping`
- `runtime.status`
- `runtime.shutdown`

## Auth

- `auth.siwa.login`
- `auth.siwa.status`
- `auth.siwa.logout`

## Techtree

- `techtree.status`
- `techtree.nodes.list`
- `techtree.nodes.get`
- `techtree.nodes.children`
- `techtree.nodes.comments`
- `techtree.nodes.workPacket`
- `techtree.nodes.create`
- `techtree.comments.create`
- `techtree.watch.create`
- `techtree.watch.delete`
- `techtree.inbox.get`
- `techtree.opportunities.list`

## Transports

- `gossipsub.status`
