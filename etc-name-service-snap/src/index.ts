import type { OnNameLookupHandler } from '@metamask/snaps-sdk';

import { SUPPORTED_CHAINS } from './constants';
import {
  configureProvider,
  isEtcDomain,
  isEvmAddress,
  resolveAddress,
  resolveDomain,
} from './resolver';

/**
 * Resolve .etc names and primary names inside MetaMask using EtcNameService.
 *
 * The Snap only reads the EtcNameService contract through MetaMask's provider.
 * It does not use an external API, request accounts, or persist lookup data.
 *
 * @param request - MetaMask name-lookup request.
 * @returns A forward or reverse EtcNameService resolution, or null when
 * unsupported or not found.
 */
export const onNameLookup: OnNameLookupHandler = async (request) => {
  const { address, chainId, domain } = request;
  const chain = SUPPORTED_CHAINS[chainId];

  if (
      !chain ||
      (domain && !isEtcDomain(domain)) ||
      (address && !isEvmAddress(address))
  ) {
    return null;
  }

  try {
    await configureProvider(chain);

    if (domain) {
      const resolution = await resolveDomain(domain);
      return resolution ? { resolvedAddresses: [resolution] } : null;
    }

    if (address) {
      const resolution = await resolveAddress(address);
      return resolution ? { resolvedDomains: [resolution] } : null;
    }
  } catch (error) {
    console.error('EtcNameService name lookup failed:', error);
  }

  return null;
};
