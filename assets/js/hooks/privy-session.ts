import type { PrivyLike, PrivyUser } from "./privy-wallet";

import {
  labelForUser,
  requireEthereumProvider,
  signWithConnectedWallet,
  walletForUser,
} from "./privy-wallet";

type PrivyReadyXmtpState = {
  status: "ready";
  inbox_id: string;
  wallet_address: string | null;
};

type PrivySignatureRequiredXmtpState = {
  status: "signature_required";
  inbox_id: null;
  wallet_address: string;
  client_id: string;
  signature_request_id: string;
  signature_text: string;
};

export type PrivySessionResponse = {
  ok: true;
  human: {
    id: number;
    privy_user_id: string;
    wallet_address: string | null;
    display_name: string | null;
    role: string;
    xmtp_inbox_id: string | null;
  };
  xmtp: PrivyReadyXmtpState | PrivySignatureRequiredXmtpState | null;
};

type SessionOptions = {
  csrfToken: string;
  sessionUrl: string;
  completeUrl: string;
  allowInteractiveCompletion?: boolean;
};

function csrfHeaders(csrfToken: string): Record<string, string> {
  return csrfToken ? { "x-csrf-token": csrfToken } : {};
}

async function parseErrorMessage(response: Response): Promise<string> {
  try {
    const payload = (await response.json()) as {
      error?: { message?: string; code?: string };
      message?: string;
    };

    return (
      payload.error?.message ||
      payload.message ||
      payload.error?.code ||
      `request failed (${response.status})`
    );
  } catch {
    return `request failed (${response.status})`;
  }
}

async function fetchSessionJson<T>(
  input: string,
  init: RequestInit,
): Promise<T> {
  const response = await fetch(input, init);

  if (!response.ok) {
    throw new Error(await parseErrorMessage(response));
  }

  return (await response.json()) as T;
}

export async function syncPrivySession(
  privy: PrivyLike,
  user: PrivyUser,
  options: SessionOptions,
): Promise<PrivySessionResponse> {
  const token = await privy.getAccessToken();
  if (!token) {
    throw new Error("Your sign-in token is missing. Try connecting again.");
  }

  const walletAddress = walletForUser(user);
  if (!walletAddress) {
    throw new Error("Connect a wallet before you continue.");
  }

  const session = await fetchSessionJson<PrivySessionResponse>(
    options.sessionUrl,
    {
      method: "POST",
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
        ...csrfHeaders(options.csrfToken),
      },
      credentials: "same-origin",
      body: JSON.stringify({
        display_name: labelForUser(user),
        wallet_address: walletAddress,
      }),
    },
  );

  if (session.xmtp?.status === "signature_required") {
    if (!options.allowInteractiveCompletion) {
      return session;
    }

    const provider = await requireEthereumProvider();
    const { signature } = await signWithConnectedWallet(
      provider,
      session.xmtp.signature_text,
      session.xmtp.wallet_address,
    );

    return await fetchSessionJson<PrivySessionResponse>(options.completeUrl, {
      method: "POST",
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        ...csrfHeaders(options.csrfToken),
      },
      credentials: "same-origin",
      body: JSON.stringify({
        wallet_address: session.xmtp.wallet_address,
        client_id: session.xmtp.client_id,
        signature_request_id: session.xmtp.signature_request_id,
        signature,
      }),
    });
  }

  return session;
}

export async function clearPrivySession(
  sessionUrl: string,
  csrfToken: string,
): Promise<void> {
  await fetchSessionJson<Record<string, never>>(sessionUrl, {
    method: "DELETE",
    headers: {
      accept: "application/json",
      ...csrfHeaders(csrfToken),
    },
    credentials: "same-origin",
  });
}
