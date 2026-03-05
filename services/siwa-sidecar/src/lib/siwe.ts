import type { HexString, Result } from "../types.js";

const SIWE_HEADER_SUFFIX = " wants you to sign in with your Ethereum account:";
const REQUIRED_FIELD_NAMES = ["URI", "Version", "Chain ID", "Nonce", "Issued At"] as const;
const OPTIONAL_FIELD_NAMES = ["Expiration Time", "Not Before", "Request ID"] as const;
const KNOWN_FIELD_NAMES = [...REQUIRED_FIELD_NAMES, ...OPTIONAL_FIELD_NAMES, "Resources"] as const;

type RequiredFieldName = (typeof REQUIRED_FIELD_NAMES)[number];
type OptionalFieldName = (typeof OPTIONAL_FIELD_NAMES)[number];
type KnownFieldName = (typeof KNOWN_FIELD_NAMES)[number];

type RequiredFieldMap = Record<RequiredFieldName, string>;
type OptionalFieldMap = Partial<Record<OptionalFieldName, string>>;

export interface ParsedSiweMessage {
  domain: string;
  domainAuthority: string;
  address: HexString;
  uri: string;
  uriAuthority: string;
  version: "1";
  chainId: number;
  nonce: string;
  issuedAt: string;
  statement?: string;
  expirationTime?: string;
  notBefore?: string;
  requestId?: string;
  resources?: readonly string[];
}

type SiweParseErrorCode =
  | "message_format_invalid"
  | "domain_invalid"
  | "address_invalid"
  | "uri_invalid"
  | "version_invalid"
  | "chain_id_invalid"
  | "nonce_invalid"
  | "issued_at_invalid"
  | "expiration_time_invalid"
  | "not_before_invalid"
  | "domain_uri_mismatch";

export interface SiweParseError {
  code: SiweParseErrorCode;
  message: string;
}

const isHexAddress = (value: string): value is HexString => {
  return /^0x[a-fA-F0-9]{40}$/.test(value);
};

const isKnownField = (fieldName: string): fieldName is KnownFieldName => {
  return (KNOWN_FIELD_NAMES as readonly string[]).includes(fieldName);
};

const parseSafePositiveInt = (value: string): number | null => {
  if (!/^[1-9][0-9]*$/.test(value)) {
    return null;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    return null;
  }

  return parsed;
};

const parseAuthorityFromDomain = (rawDomain: string): Result<string, SiweParseError> => {
  const trimmed = rawDomain.trim();
  if (trimmed.length === 0 || /\s/.test(trimmed)) {
    return {
      ok: false,
      error: {
        code: "domain_invalid",
        message: "SIWE domain is missing or malformed",
      },
    };
  }

  try {
    const parsed = new URL(`https://${trimmed}`);
    if (
      parsed.host.length === 0 ||
      parsed.username.length > 0 ||
      parsed.password.length > 0 ||
      parsed.pathname !== "/" ||
      parsed.search.length > 0 ||
      parsed.hash.length > 0
    ) {
      return {
        ok: false,
        error: {
          code: "domain_invalid",
          message: "SIWE domain is missing or malformed",
        },
      };
    }

    return { ok: true, value: parsed.host.toLowerCase() };
  } catch {
    return {
      ok: false,
      error: {
        code: "domain_invalid",
        message: "SIWE domain is missing or malformed",
      },
    };
  }
};

const parseAuthorityFromUri = (rawUri: string): Result<{ uri: string; authority: string }, SiweParseError> => {
  try {
    const parsed = new URL(rawUri);
    if (parsed.host.length === 0) {
      return {
        ok: false,
        error: {
          code: "uri_invalid",
          message: "SIWE URI must be an absolute URI with authority",
        },
      };
    }

    return {
      ok: true,
      value: {
        uri: rawUri,
        authority: parsed.host.toLowerCase(),
      },
    };
  } catch {
    return {
      ok: false,
      error: {
        code: "uri_invalid",
        message: "SIWE URI must be an absolute URI with authority",
      },
    };
  }
};

const parseTimestamp = (value: string): number | null => {
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) {
    return null;
  }
  return parsed;
};

const withOptionalFields = (
  requiredFields: RequiredFieldMap,
  optionalFields: OptionalFieldMap,
  statement: string | undefined,
  resources: readonly string[] | undefined,
  domain: string,
  domainAuthority: string,
  address: HexString,
  uri: string,
  uriAuthority: string,
  chainId: number,
): ParsedSiweMessage => {
  const valueBase: ParsedSiweMessage = {
    domain,
    domainAuthority,
    address,
    uri,
    uriAuthority,
    version: "1",
    chainId,
    nonce: requiredFields["Nonce"],
    issuedAt: requiredFields["Issued At"],
  };

  return {
    ...valueBase,
    ...(typeof statement === "string" ? { statement } : {}),
    ...(typeof optionalFields["Expiration Time"] === "string"
      ? { expirationTime: optionalFields["Expiration Time"] }
      : {}),
    ...(typeof optionalFields["Not Before"] === "string"
      ? { notBefore: optionalFields["Not Before"] }
      : {}),
    ...(typeof optionalFields["Request ID"] === "string" ? { requestId: optionalFields["Request ID"] } : {}),
    ...(Array.isArray(resources) ? { resources } : {}),
  };
};

const extractRequiredFields = (
  requiredFields: Partial<RequiredFieldMap>,
): Result<RequiredFieldMap, SiweParseError> => {
  const uri = requiredFields.URI;
  if (typeof uri !== "string") {
    return {
      ok: false,
      error: {
        code: "message_format_invalid",
        message: "SIWE message is missing required 'URI' field",
      },
    };
  }

  const version = requiredFields.Version;
  if (typeof version !== "string") {
    return {
      ok: false,
      error: {
        code: "message_format_invalid",
        message: "SIWE message is missing required 'Version' field",
      },
    };
  }

  const chainId = requiredFields["Chain ID"];
  if (typeof chainId !== "string") {
    return {
      ok: false,
      error: {
        code: "message_format_invalid",
        message: "SIWE message is missing required 'Chain ID' field",
      },
    };
  }

  const nonce = requiredFields.Nonce;
  if (typeof nonce !== "string") {
    return {
      ok: false,
      error: {
        code: "message_format_invalid",
        message: "SIWE message is missing required 'Nonce' field",
      },
    };
  }

  const issuedAt = requiredFields["Issued At"];
  if (typeof issuedAt !== "string") {
    return {
      ok: false,
      error: {
        code: "message_format_invalid",
        message: "SIWE message is missing required 'Issued At' field",
      },
    };
  }

  return {
    ok: true,
    value: {
      URI: uri,
      Version: version,
      "Chain ID": chainId,
      Nonce: nonce,
      "Issued At": issuedAt,
    },
  };
};

export const parseSiweMessage = (message: string): Result<ParsedSiweMessage, SiweParseError> => {
  const normalizedMessage = message.replace(/\r\n/g, "\n").trimEnd();
  const lines = normalizedMessage.split("\n");

  if (lines.length < 6) {
    return {
      ok: false,
      error: {
        code: "message_format_invalid",
        message: "SIWE message does not match expected EIP-4361 line structure",
      },
    };
  }

  const firstLine = lines[0];
  if (typeof firstLine !== "string" || !firstLine.endsWith(SIWE_HEADER_SUFFIX)) {
    return {
      ok: false,
      error: {
        code: "message_format_invalid",
        message: "SIWE message does not match expected EIP-4361 line structure",
      },
    };
  }

  const domain = firstLine.slice(0, firstLine.length - SIWE_HEADER_SUFFIX.length).trim();
  const domainAuthority = parseAuthorityFromDomain(domain);
  if (!domainAuthority.ok) {
    return domainAuthority;
  }

  const addressLine = lines[1];
  if (typeof addressLine !== "string" || !isHexAddress(addressLine)) {
    return {
      ok: false,
      error: {
        code: "address_invalid",
        message: "SIWE address must be a 0x-prefixed 20-byte hex address",
      },
    };
  }

  if (lines[2] !== "") {
    return {
      ok: false,
      error: {
        code: "message_format_invalid",
        message: "SIWE message does not match expected EIP-4361 line structure",
      },
    };
  }

  let index = 3;
  let statement: string | undefined;
  const statementCandidate = lines[index];
  if (
    typeof statementCandidate === "string" &&
    statementCandidate.length > 0 &&
    !/^[A-Za-z][A-Za-z ]*: /.test(statementCandidate)
  ) {
    statement = statementCandidate;
    index += 1;
    if (lines[index] !== "") {
      return {
        ok: false,
        error: {
          code: "message_format_invalid",
          message: "SIWE message does not match expected EIP-4361 line structure",
        },
      };
    }
    index += 1;
  }

  const requiredFields: Partial<RequiredFieldMap> = {};
  const optionalFields: OptionalFieldMap = {};
  let resources: readonly string[] | undefined;

  while (index < lines.length) {
    const line = lines[index];
    if (typeof line !== "string" || line.length === 0) {
      return {
        ok: false,
        error: {
          code: "message_format_invalid",
          message: "SIWE message does not match expected EIP-4361 line structure",
        },
      };
    }

    if (line === "Resources:") {
      if (resources !== undefined) {
        return {
          ok: false,
          error: {
            code: "message_format_invalid",
            message: "SIWE message contains duplicate Resources section",
          },
        };
      }

      const values: string[] = [];
      for (let resourceIndex = index + 1; resourceIndex < lines.length; resourceIndex += 1) {
        const resourceLine = lines[resourceIndex];
        if (typeof resourceLine !== "string" || !resourceLine.startsWith("- ")) {
          return {
            ok: false,
            error: {
              code: "message_format_invalid",
              message: "SIWE Resources entries must be lines prefixed with '- '",
            },
          };
        }

        const resourceValue = resourceLine.slice(2).trim();
        if (resourceValue.length === 0) {
          return {
            ok: false,
            error: {
              code: "message_format_invalid",
              message: "SIWE Resources entries must not be empty",
            },
          };
        }

        values.push(resourceValue);
      }

      resources = values;
      break;
    }

    const fieldMatch = /^([A-Za-z][A-Za-z ]*): (.+)$/.exec(line);
    if (!fieldMatch?.[1] || !fieldMatch[2]) {
      return {
        ok: false,
        error: {
          code: "message_format_invalid",
          message: "SIWE message contains malformed field lines",
        },
      };
    }

    const fieldName = fieldMatch[1];
    const fieldValue = fieldMatch[2].trim();
    if (!isKnownField(fieldName) || fieldValue.length === 0 || fieldName === "Resources") {
      return {
        ok: false,
        error: {
          code: "message_format_invalid",
          message: "SIWE message contains unsupported or empty fields",
        },
      };
    }

    if (fieldName in requiredFields || fieldName in optionalFields) {
      return {
        ok: false,
        error: {
          code: "message_format_invalid",
          message: `SIWE message contains duplicate '${fieldName}' field`,
        },
      };
    }

    if (REQUIRED_FIELD_NAMES.includes(fieldName as RequiredFieldName)) {
      requiredFields[fieldName as RequiredFieldName] = fieldValue;
    } else {
      optionalFields[fieldName as OptionalFieldName] = fieldValue;
    }

    index += 1;
  }

  for (const requiredFieldName of REQUIRED_FIELD_NAMES) {
    if (typeof requiredFields[requiredFieldName] !== "string") {
      return {
        ok: false,
        error: {
          code: "message_format_invalid",
          message: `SIWE message is missing required '${requiredFieldName}' field`,
        },
      };
    }
  }

  const requiredFieldValuesResult = extractRequiredFields(requiredFields);
  if (!requiredFieldValuesResult.ok) {
    return requiredFieldValuesResult;
  }

  const requiredFieldValues = requiredFieldValuesResult.value;

  if (requiredFieldValues.Version !== "1") {
    return {
      ok: false,
      error: {
        code: "version_invalid",
        message: "SIWE Version must be '1'",
      },
    };
  }

  const chainId = parseSafePositiveInt(requiredFieldValues["Chain ID"]);
  if (chainId === null) {
    return {
      ok: false,
      error: {
        code: "chain_id_invalid",
        message: "SIWE Chain ID must be a positive integer",
      },
    };
  }

  if (!/^[A-Za-z0-9]{8,}$/.test(requiredFieldValues.Nonce)) {
    return {
      ok: false,
      error: {
        code: "nonce_invalid",
        message: "SIWE Nonce must be an alphanumeric string with length >= 8",
      },
    };
  }

  if (parseTimestamp(requiredFieldValues["Issued At"]) === null) {
    return {
      ok: false,
      error: {
        code: "issued_at_invalid",
        message: "SIWE Issued At must be an RFC3339 timestamp",
      },
    };
  }

  if (
    typeof optionalFields["Expiration Time"] === "string" &&
    parseTimestamp(optionalFields["Expiration Time"]) === null
  ) {
    return {
      ok: false,
      error: {
        code: "expiration_time_invalid",
        message: "SIWE Expiration Time must be an RFC3339 timestamp",
      },
    };
  }

  if (typeof optionalFields["Not Before"] === "string" && parseTimestamp(optionalFields["Not Before"]) === null) {
    return {
      ok: false,
      error: {
        code: "not_before_invalid",
        message: "SIWE Not Before must be an RFC3339 timestamp",
      },
    };
  }

  const uri = parseAuthorityFromUri(requiredFieldValues.URI);
  if (!uri.ok) {
    return uri;
  }

  if (domainAuthority.value !== uri.value.authority) {
    return {
      ok: false,
      error: {
        code: "domain_uri_mismatch",
        message: "SIWE domain must match SIWE URI authority",
      },
    };
  }

  return {
    ok: true,
    value: withOptionalFields(
      requiredFieldValues,
      optionalFields,
      statement,
      resources,
      domain,
      domainAuthority.value,
      addressLine,
      uri.value.uri,
      uri.value.authority,
      chainId,
    ),
  };
};
