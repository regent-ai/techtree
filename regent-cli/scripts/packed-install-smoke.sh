#!/usr/bin/env bash
set -euo pipefail

export NODE_NO_WARNINGS=1

ROOT="/Users/sean/Documents/regent/techtree/regent-cli"
PACK_DIR="$(mktemp -d "/tmp/regent-pack.XXXXXX")"
WORK_DIR="$(mktemp -d "/tmp/regent-install.XXXXXX")"
SERVER_PORT_FILE="${WORK_DIR}/mock-server.port"
CONFIG_PATH="${WORK_DIR}/regent.config.json"
NOTEBOOK_PATH="${WORK_DIR}/publish.py"
RUNTIME_LOG="${WORK_DIR}/runtime.log"
SERVER_LOG="${WORK_DIR}/mock-server.log"

TEST_PRIVATE_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
TEST_WALLET="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
TEST_REGISTRY="0x2222222222222222222222222222222222222222"

RUNTIME_PID=""
SERVER_PID=""

cleanup() {
  if [[ -n "${RUNTIME_PID}" ]] && kill -0 "${RUNTIME_PID}" >/dev/null 2>&1; then
    kill "${RUNTIME_PID}" >/dev/null 2>&1 || true
    wait "${RUNTIME_PID}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi

  rm -rf "${PACK_DIR}" "${WORK_DIR}"
}

wait_for_file() {
  local target="$1"
  local attempts="${2:-50}"

  for ((i = 1; i <= attempts; i += 1)); do
    if [[ -e "${target}" || -S "${target}" ]]; then
      return 0
    fi
    sleep 0.1
  done

  echo "timed out waiting for ${target}" >&2
  return 1
}

pack_workspace_package() {
  local package_dir="$1"
  (
    cd "${package_dir}"
    pnpm pack --pack-destination "${PACK_DIR}" >/dev/null
  )
}

trap cleanup EXIT

cd "${ROOT}"
pnpm build >/dev/null

pack_workspace_package "${ROOT}/packages/regent-types"
pack_workspace_package "${ROOT}/packages/regent-runtime"
pack_workspace_package "${ROOT}/packages/regent-cli"

cat > "${WORK_DIR}/package.json" <<'EOF'
{
  "name": "regent-packed-install-smoke",
  "private": true,
  "packageManager": "pnpm@9.15.0",
  "pnpm": {
    "overrides": {
      "@regent/types": "file:REGENT_TYPES_TARBALL",
      "@regent/runtime": "file:REGENT_RUNTIME_TARBALL"
    }
  }
}
EOF

node -e '
  const fs = require("node:fs");
  const [packageJsonPath, typesTarball, runtimeTarball] = process.argv.slice(1);
  const content = fs
    .readFileSync(packageJsonPath, "utf8")
    .replace("REGENT_TYPES_TARBALL", typesTarball)
    .replace("REGENT_RUNTIME_TARBALL", runtimeTarball);
  fs.writeFileSync(packageJsonPath, content, "utf8");
' "${WORK_DIR}/package.json" "${PACK_DIR}/regent-types-0.1.0.tgz" "${PACK_DIR}/regent-runtime-0.1.0.tgz"

pnpm --dir "${WORK_DIR}" add "${PACK_DIR}"/regent-cli-*.tgz >/dev/null

cat > "${WORK_DIR}/mock-techtree.mjs" <<'EOF'
import http from "node:http";
import fs from "node:fs";

const portFile = process.argv[2];
let nextNodeId = 100;

const json = (res, statusCode, payload) => {
  res.statusCode = statusCode;
  res.setHeader("content-type", "application/json");
  res.end(`${JSON.stringify(payload)}\n`);
};

const readJson = async (req) => {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  return raw === "" ? undefined : JSON.parse(raw);
};

const server = http.createServer(async (req, res) => {
  const requestUrl = new URL(req.url ?? "/", "http://127.0.0.1");
  const body = await readJson(req);

  if (req.method === "GET" && requestUrl.pathname === "/health") {
    json(res, 200, { ok: true, service: "packed-install-smoke" });
    return;
  }

  if (req.method === "POST" && requestUrl.pathname === "/v1/agent/siwa/nonce") {
    json(res, 200, {
      ok: true,
      code: "nonce_issued",
      data: {
        nonce: "packed-install-nonce",
        walletAddress: body?.walletAddress ?? "0x0",
        chainId: body?.chainId ?? 11155111,
        expiresAt: "2999-01-01T00:00:00.000Z"
      }
    });
    return;
  }

  if (req.method === "POST" && requestUrl.pathname === "/v1/agent/siwa/verify") {
    json(res, 200, {
      ok: true,
      code: "siwa_verified",
      data: {
        verified: true,
        walletAddress: body?.walletAddress ?? "0x0",
        chainId: body?.chainId ?? 11155111,
        nonce: body?.nonce ?? "packed-install-nonce",
        keyId: String(body?.walletAddress ?? "0x0").toLowerCase(),
        signatureScheme: "evm_personal_sign",
        receipt: "receipt-valid.eyJ3YWxsZXRBZGRyZXNzIjoiMHgwIiwiY2hhaW5JZCI6MTExNTUxMTEsImtleUlkIjoiMHgwIiwiZXhwaXJlc0F0IjoiMjk5OS0wMS0wMVQwMDowMDowMC4wMDBaIn0",
        receiptExpiresAt: "2999-01-01T00:00:00.000Z"
      }
    });
    return;
  }

  if (req.method === "GET" && requestUrl.pathname === "/v1/tree/nodes") {
    json(res, 200, {
      data: [{
        id: 1,
        parent_id: null,
        path: "1",
        depth: 0,
        seed: "ml",
        kind: "hypothesis",
        title: "Root node",
        slug: "root-node",
        summary: "A root node",
        status: "anchored",
        manifest_cid: "bafyroot",
        manifest_uri: null,
        manifest_hash: null,
        notebook_cid: "bafyrootnotebook",
        skill_slug: null,
        skill_version: null,
        child_count: 0,
        comment_count: 0,
        watcher_count: 0,
        activity_score: "1.0",
        comments_locked: false,
        inserted_at: "2026-03-10T00:00:00.000Z",
        updated_at: "2026-03-10T00:00:00.000Z",
        sidelinks: []
      }]
    });
    return;
  }

  if (req.method === "POST" && requestUrl.pathname === "/v1/tree/nodes") {
    if (!req.headers["x-siwa-receipt"]) {
      json(res, 401, { error: { code: "http_envelope_invalid", message: "missing SIWA receipt" } });
      return;
    }

    json(res, 201, {
      data: {
        node_id: nextNodeId++,
        manifest_cid: "bafypackedinstall",
        status: "pinned",
        anchor_status: "pending"
      }
    });
    return;
  }

  json(res, 404, { error: { code: "route_not_found", message: `${req.method} ${requestUrl.pathname}` } });
});

server.listen(0, "127.0.0.1", () => {
  const address = server.address();
  fs.writeFileSync(portFile, String(address.port), "utf8");
});
EOF

node "${WORK_DIR}/mock-techtree.mjs" "${SERVER_PORT_FILE}" >"${SERVER_LOG}" 2>&1 &
SERVER_PID=$!
wait_for_file "${SERVER_PORT_FILE}"
BASE_URL="http://127.0.0.1:$(cat "${SERVER_PORT_FILE}")"

pnpm --dir "${WORK_DIR}" exec regent create init --config "${CONFIG_PATH}" >/dev/null
pnpm --dir "${WORK_DIR}" exec regent create wallet --dev-file "${WORK_DIR}/wallet.json" >/dev/null

cat > "${WORK_DIR}/replacement.json" <<EOF
{
  "runtime": {
    "socketPath": "${WORK_DIR}/regent.sock",
    "stateDir": "${WORK_DIR}/state",
    "logLevel": "info"
  },
  "techtree": {
    "baseUrl": "${BASE_URL}",
    "audience": "techtree",
    "defaultChainId": 11155111,
    "requestTimeoutMs": 1000
  },
  "wallet": {
    "privateKeyEnv": "REGENT_WALLET_PRIVATE_KEY",
    "keystorePath": "${WORK_DIR}/wallet-keystore.json"
  },
  "gossipsub": {
    "enabled": false,
    "listenAddrs": [],
    "bootstrap": [],
    "peerIdPath": "${WORK_DIR}/peer-id.json"
  }
}
EOF

pnpm --dir "${WORK_DIR}" exec regent config write --config "${CONFIG_PATH}" --input "@${WORK_DIR}/replacement.json" >/dev/null

REGENT_WALLET_PRIVATE_KEY="${TEST_PRIVATE_KEY}" \
  pnpm --dir "${WORK_DIR}" exec regent run --config "${CONFIG_PATH}" >"${RUNTIME_LOG}" 2>&1 &
RUNTIME_PID=$!

wait_for_file "${WORK_DIR}/regent.sock"

REGENT_WALLET_PRIVATE_KEY="${TEST_PRIVATE_KEY}" \
  pnpm --dir "${WORK_DIR}" exec regent auth siwa login \
    --config "${CONFIG_PATH}" \
    --wallet-address "${TEST_WALLET}" \
    --chain-id 11155111 \
    --registry-address "${TEST_REGISTRY}" \
    --token-id 99 >/dev/null

REGENT_WALLET_PRIVATE_KEY="${TEST_PRIVATE_KEY}" \
  pnpm --dir "${WORK_DIR}" exec regent techtree nodes list --config "${CONFIG_PATH}" --limit 1 >/dev/null

printf "print('packed install smoke')\n" > "${NOTEBOOK_PATH}"

REGENT_WALLET_PRIVATE_KEY="${TEST_PRIVATE_KEY}" \
  pnpm --dir "${WORK_DIR}" exec regent techtree node create \
    --config "${CONFIG_PATH}" \
    --seed ml \
    --kind hypothesis \
    --title "Packed install publish" \
    --parent-id 1 \
    --notebook-source "@${NOTEBOOK_PATH}" >/dev/null

echo "packed install smoke passed"
