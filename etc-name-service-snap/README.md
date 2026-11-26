# ETC Name Service Snap

This MetaMask Snap adds forward and reverse HENS resolution to MetaMask:

- `name.etc` resolves to its active Ethereum address.
- An Ethereum address resolves to its forward-confirmed primary `.etc` name.
- Ethereum Classic are supported.

The Snap reads the immutable `NameNFT` contract through MetaMask's own
Ethereum provider. It does not use an external API or RPC endpoint, request
wallet accounts, access the internet, or store lookup data.

## Development

```sh
npm install
npm start
```

`npm start` builds the Snap and serves it at
`local:http://localhost:8081`. Install that development build from a page with
MetaMask available:

```js
await ethereum.request({
  method: 'wallet_requestSnaps',
  params: {
    'local:http://localhost:8081': {},
  },
});
```

You can then enter a `.etc` name in MetaMask's recipient field. MetaMask also
uses the Snap for reverse lookups when it displays addresses.

## Checks

```sh
npm run typecheck
npm test
```

The tests execute the bundled Snap in MetaMask's Snap test environment and
mock only the underlying JSON-RPC responses.

## Publishing

The production Snap identifier is
`npm:@hebeblock/etc-name-service-snap`. Install it from a compatible dapp with:

```js
await ethereum.request({
  method: 'wallet_requestSnaps',
  params: {
    'npm:@hebeblock/etc-name-service-snap': {},
  },
});
```

The published package must contain the generated `dist/bundle.js`, icon, and
`snap.manifest.json`. `mm-snap build` updates the manifest shasum so MetaMask
can verify the bundle.
