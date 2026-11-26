// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Base64} from "https://github.com/Vectorized/solady/blob/main/src/utils/Base64.sol";
import {LibString} from "https://github.com/Vectorized/solady/blob/main/src/utils/LibString.sol";

interface INameMetadataRenderer {
    function renderTokenURI(
        uint8 status, // 0: Invalid, 1: Expired, 2: Valid
        string calldata fullName,
        bool isSubdomain,
        uint64 expiresAt
    ) external pure returns (string memory);
}

contract NameMetadataRenderer is INameMetadataRenderer {
    using LibString for uint256;

    function renderTokenURI(
        uint8 status,
        string calldata fullName,
        bool isSubdomain,
        uint64 expiresAt
    ) external pure override returns (string memory) {
        if (status == 0) {
            return string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        '{"name":"[Invalid]","description":"This subdomain is no longer valid.","image":"data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA0MDAgNDAwIj48cmVjdCB3aWR0aD0iNDAwIiBoZWlnaHQ9IjQwMCIgZmlsbD0iIzk5OSIvPjx0ZXh0IHg9IjIwMCIgeT0iMjAwIiBmb250LWZhbWlseT0ic2Fucy1zZXJpZiIgZm9udC1zaXplPSIyNCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZmlsbD0iI2ZmZiI+W0ludmFsaWRdPC90ZXh0Pjwvc3ZnPg=="}'
                    )
                )
            );
        }

        if (status == 1) {
            return string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        '{"name":"[Expired]","description":"This name has expired.","image":"data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA0MDAgNDAwIj48cmVjdCB3aWR0aD0iNDAwIiBoZWlnaHQ9IjQwMCIgZmlsbD0iIzk5OSIvPjx0ZXh0IHg9IjIwMCIgeT0iMjAwIiBmb250LWZhbWlseT0ic2Fucy1zZXJpZiIgZm9udC1zaXplPSIyNCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZmlsbD0iI2ZmZiI+W0V4cGlyZWRdPC90ZXh0Pjwvc3ZnPg=="}'
                    )
                )
            );
        }

        string memory displayName = bytes(fullName).length <= 20
            ? fullName
            : string.concat(_truncateUTF8(fullName, 17), "...");

        string memory attributes = isSubdomain
            ? ',"attributes":[{"trait_type":"Type","value":"Subdomain"}]'
            : string.concat(
                ',"attributes":[{"trait_type":"Expires","display_type":"date","value":',
                uint256(expiresAt).toString(),
                "}]"
            );

        string memory escapedName = _escapeJSON(fullName);

        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name":"',
                        escapedName,
                        '","description":"Etc Name Service: ',
                        escapedName,
                        '","image":"data:image/svg+xml;base64,',
                        Base64.encode(bytes(_generateSVG(displayName))),
                        '"',
                        attributes,
                        "}"
                    )
                )
            )
        );
    }

    function _truncateUTF8(string memory str, uint256 maxBytes)
        internal
        pure
        returns (string memory)
    {
        bytes memory b = bytes(str);
        if (b.length <= maxBytes) return str;

        uint256 cutPoint = maxBytes;
        while (cutPoint > 0 && uint8(b[cutPoint]) >= 0x80 && uint8(b[cutPoint]) <= 0xBF) {
            unchecked {
                --cutPoint;
            }
        }

        bytes memory result = new bytes(cutPoint);
        for (uint256 i; i < cutPoint; ++i) {
            result[i] = b[i];
        }
        return string(result);
    }

    function _generateSVG(string memory displayName) internal pure returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400"><rect width="400" height="400" fill="#fff"/><text x="200" y="200" font-family="sans-serif" font-size="24" text-anchor="middle" dominant-baseline="middle">',
            _escapeXML(displayName),
            "</text></svg>"
        );
    }

    function _escapeJSON(string memory input) internal pure returns (string memory) {
        bytes memory b = bytes(input);
        uint256 outLen;
        unchecked {
            for (uint256 i; i < b.length; ++i) {
                bytes1 c = b[i];
                if (c == 0x22 || c == 0x5c || c == 0x0a || c == 0x0d || c == 0x09) {
                    outLen += 2;
                } else if (uint8(c) >= 0x20) {
                    outLen += 1;
                }
            }
        }

        if (outLen == b.length) return input;

        bytes memory result = new bytes(outLen);
        uint256 j;
        unchecked {
            for (uint256 i; i < b.length; ++i) {
                bytes1 c = b[i];
                if (c == 0x22) {
                    result[j++] = "\\";
                    result[j++] = '"';
                } else if (c == 0x5c) {
                    result[j++] = "\\";
                    result[j++] = "\\";
                } else if (c == 0x0a) {
                    result[j++] = "\\";
                    result[j++] = "n";
                } else if (c == 0x0d) {
                    result[j++] = "\\";
                    result[j++] = "r";
                } else if (c == 0x09) {
                    result[j++] = "\\";
                    result[j++] = "t";
                } else if (uint8(c) >= 0x20) {
                    result[j++] = c;
                }
            }
        }
        return string(result);
    }

    function _escapeXML(string memory input) internal pure returns (string memory) {
        bytes memory b = bytes(input);
        uint256 extraLen;
        unchecked {
            for (uint256 i; i < b.length; ++i) {
                bytes1 c = b[i];
                if (c == 0x26) extraLen += 4;
                else if (c == 0x3c || c == 0x3e) extraLen += 3;
                else if (c == 0x22 || c == 0x27) extraLen += 5;
            }
        }

        if (extraLen == 0) return input;

        bytes memory result = new bytes(b.length + extraLen);
        uint256 j;
        unchecked {
            for (uint256 i; i < b.length; ++i) {
                bytes1 c = b[i];
                if (c == 0x26) {
                    result[j++] = "&";
                    result[j++] = "a";
                    result[j++] = "m";
                    result[j++] = "p";
                    result[j++] = ";";
                } else if (c == 0x3c) {
                    result[j++] = "&";
                    result[j++] = "l";
                    result[j++] = "t";
                    result[j++] = ";";
                } else if (c == 0x3e) {
                    result[j++] = "&";
                    result[j++] = "g";
                    result[j++] = "t";
                    result[j++] = ";";
                } else if (c == 0x22) {
                    result[j++] = "&";
                    result[j++] = "q";
                    result[j++] = "u";
                    result[j++] = "o";
                    result[j++] = "t";
                    result[j++] = ";";
                } else if (c == 0x27) {
                    result[j++] = "&";
                    result[j++] = "a";
                    result[j++] = "p";
                    result[j++] = "o";
                    result[j++] = "s";
                    result[j++] = ";";
                } else {
                    result[j++] = c;
                }
            }
        }
        return string(result);
    }
}
