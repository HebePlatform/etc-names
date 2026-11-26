import { describe, expect, it } from '@jest/globals';
import { installSnap } from '@metamask/snaps-jest';
import type { ChainId } from '@metamask/snaps-sdk';

const ETC_MAINNET = 'eip155:61' as ChainId;
const OTHER_CHAIN = 'eip155:1' as ChainId;
const RESOLVED_ADDRESS = '0xa5a52d92ff302fcca9e5b060ec797f01311c66ff';
const TOKEN_ID = 123n;
const ETC_NAME_SERVICE_CONTRACT =
    '0xffc26c447c90f9ebdae34a0c368f702c4643de34';
const PROTOCOL = 'Etc Name Service';

function word(value: bigint): string {
  return value.toString(16).padStart(64, '0');
}

function encodeAddressResult(address: string): `0x${string}` {
  return `0x${address.slice(2).toLowerCase().padStart(64, '0')}`;
}

function encodeStringResult(value: string): `0x${string}` {
  const bytes = new TextEncoder().encode(value);
  const data = Array.from(bytes, (byte) =>
      byte.toString(16).padStart(2, '0'),
  ).join('');
  return `0x${word(32n)}${word(BigInt(bytes.length))}${data.padEnd(
      Math.ceil(data.length / 64) * 64,
      '0',
  )}`;
}

function encodeStringArgument(value: string): string {
  return encodeStringResult(value).slice(2);
}

const encodedTokenId = `0x${word(TOKEN_ID)}`;
const encodedAddress = encodeAddressResult(RESOLVED_ADDRESS);
const encodedZeroAddress = encodeAddressResult(
    '0x0000000000000000000000000000000000000000',
);
const encodedDomain = encodeStringResult('hebeswap.etc');
const encodedEmptyDomain = encodeStringResult('');

describe('onNameLookup', () => {
  it('resolves a .etc name on Ethereum Classic mainnet', async () => {
    const { mockJsonRpcOnce, onNameLookup } = await installSnap();
    mockJsonRpcOnce((request) => {
      if (request.method !== 'eth_call') {
        return undefined;
      }
      expect(request).toEqual(
          expect.objectContaining({
            method: 'eth_call',
            params: [
              {
                data: `0xfb021939${encodeStringArgument('hebeswap.etc')}`,
                to: ETC_NAME_SERVICE_CONTRACT,
              },
              'latest',
            ],
          }),
      );
      return encodedTokenId;
    });
    mockJsonRpcOnce((request) => {
      if (request.method !== 'eth_call') {
        return undefined;
      }
      expect(request).toEqual(
          expect.objectContaining({
            method: 'eth_call',
            params: [
              {
                data: `0x4f896d4f${word(TOKEN_ID)}`,
                to: ETC_NAME_SERVICE_CONTRACT,
              },
              'latest',
            ],
          }),
      );
      return encodedAddress;
    });

    const response = await onNameLookup({
      chainId: ETC_MAINNET,
      domain: 'hebeswap.etc',
    });

    expect(response).toRespondWith({
      resolvedAddresses: [
        {
          domainName: 'hebeswap.etc',
          protocol: PROTOCOL,
          resolvedAddress: RESOLVED_ADDRESS,
        },
      ],
    });
  });

  it('returns null for an unregistered or expired name', async () => {
    const { mockJsonRpcOnce, onNameLookup } = await installSnap();
    mockJsonRpcOnce({ method: 'eth_call', result: encodedTokenId });
    mockJsonRpcOnce({ method: 'eth_call', result: encodedZeroAddress });

    const response = await onNameLookup({
      chainId: ETC_MAINNET,
      domain: 'missing.etc',
    });

    expect(response).toRespondWith(null);
  });

  it('reverse-resolves a forward-confirmed primary name', async () => {
    const { mockJsonRpcOnce, onNameLookup } = await installSnap();
    mockJsonRpcOnce((request) => {
      if (request.method !== 'eth_call') {
        return undefined;
      }
      expect(request).toEqual(
          expect.objectContaining({
            method: 'eth_call',
            params: [
              {
                data: `0x9af8b7aa${RESOLVED_ADDRESS.slice(2).padStart(64, '0')}`,
                to: ETC_NAME_SERVICE_CONTRACT,
              },
              'latest',
            ],
          }),
      );
      return encodedDomain;
    });

    const response = await onNameLookup({
      address: RESOLVED_ADDRESS,
      chainId: ETC_MAINNET,
    });

    expect(response).toRespondWith({
      resolvedDomains: [
        {
          protocol: PROTOCOL,
          resolvedDomain: 'hebeswap.etc',
        },
      ],
    });
  });

  it('returns null when an address has no primary name', async () => {
    const { mockJsonRpcOnce, onNameLookup } = await installSnap();
    mockJsonRpcOnce({ method: 'eth_call', result: encodedEmptyDomain });

    const response = await onNameLookup({
      address: RESOLVED_ADDRESS,
      chainId: ETC_MAINNET,
    });

    expect(response).toRespondWith(null);
  });

  it('ignores domains outside the .etc namespace', async () => {
    const { onNameLookup } = await installSnap();
    const response = await onNameLookup({
      chainId: ETC_MAINNET,
      domain: 'vitalik.eth',
    });

    expect(response).toRespondWith(null);
  });

  it('ignores unsupported chains', async () => {
    const { onNameLookup } = await installSnap();
    const response = await onNameLookup({
      chainId: OTHER_CHAIN,
      domain: 'hebeswap.etc',
    });

    expect(response).toRespondWith(null);
  });

  it('ignores malformed reverse-lookup addresses', async () => {
    const { onNameLookup } = await installSnap();
    const response = await onNameLookup({
      address: '0x1234',
      chainId: ETC_MAINNET,
    });

    expect(response).toRespondWith(null);
  });
});
