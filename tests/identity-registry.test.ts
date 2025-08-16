import { describe, it, expect, beforeEach } from "vitest";

interface Identity {
  did: string;
  credentials: string[];
  createdAt: bigint;
  updatedAt: bigint;
}

interface MockContract {
  admin: string;
  paused: boolean;
  totalIdentities: bigint;
  identities: Map<string, Identity>;
  didToUser: Map<string, string>;
  MAX_CREDENTIALS: number;

  isAdmin(caller: string): boolean;
  setPaused(caller: string, pause: boolean): { value: boolean } | { error: number };
  registerIdentity(caller: string, did: string): { value: boolean } | { error: number };
  updateDid(caller: string, newDid: string): { value: boolean } | { error: number };
  linkCredential(caller: string, credId: string): { value: boolean } | { error: number };
  unlinkCredential(caller: string, credId: string): { value: boolean } | { error: number };
  getIdentity(user: string): Identity | undefined;
}

const mockContract: MockContract = {
  admin: "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM",
  paused: false,
  totalIdentities: 0n,
  identities: new Map<string, Identity>(),
  didToUser: new Map<string, string>(),
  MAX_CREDENTIALS: 50,

  isAdmin(caller: string) {
    return caller === this.admin;
  },

  setPaused(caller: string, pause: boolean) {
    if (!this.isAdmin(caller)) return { error: 100 };
    this.paused = pause;
    return { value: pause };
  },

  registerIdentity(caller: string, did: string) {
    if (this.paused) return { error: 106 };
    if (did.length < 10 || did.length > 64) return { error: 103 };
    if (this.identities.has(caller)) return { error: 101 };
    if (this.didToUser.has(did)) return { error: 101 };
    const currentBlock = 100n; // Mock block height
    this.identities.set(caller, {
      did,
      credentials: [],
      createdAt: currentBlock,
      updatedAt: currentBlock,
    });
    this.didToUser.set(did, caller);
    this.totalIdentities += 1n;
    return { value: true };
  },

  updateDid(caller: string, newDid: string) {
    if (this.paused) return { error: 106 };
    const identity = this.identities.get(caller);
    if (!identity) return { error: 102 };
    if (newDid.length < 10 || newDid.length > 64) return { error: 103 };
    if (newDid === identity.did) return { error: 109 };
    if (this.didToUser.has(newDid)) return { error: 101 };
    this.didToUser.delete(identity.did);
    this.didToUser.set(newDid, caller);
    this.identities.set(caller, {
      ...identity,
      did: newDid,
      updatedAt: 101n, // Mock update
    });
    return { value: true };
  },

  linkCredential(caller: string, credId: string) {
    if (this.paused) return { error: 106 };
    const identity = this.identities.get(caller);
    if (!identity) return { error: 102 };
    if (credId.length === 0) return { error: 105 };
    if (identity.credentials.length >= this.MAX_CREDENTIALS) return { error: 104 };
    if (identity.credentials.includes(credId)) return { error: 101 };
    identity.credentials.push(credId);
    identity.updatedAt = 101n;
    return { value: true };
  },

  unlinkCredential(caller: string, credId: string) {
    if (this.paused) return { error: 106 };
    const identity = this.identities.get(caller);
    if (!identity) return { error: 102 };
    const index = identity.credentials.indexOf(credId);
    if (index === -1) return { error: 108 };
    identity.credentials.splice(index, 1);
    identity.updatedAt = 101n;
    return { value: true };
  },

  getIdentity(user: string) {
    return this.identities.get(user);
  },
};

describe("Identity Registry Contract", () => {
  beforeEach(() => {
    mockContract.admin = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM";
    mockContract.paused = false;
    mockContract.totalIdentities = 0n;
    mockContract.identities = new Map();
    mockContract.didToUser = new Map();
  });

  it("should register a new identity", () => {
    const result = mockContract.registerIdentity("ST2CY5...", "did:example:1234567890");
    expect(result).toEqual({ value: true });
    const identity = mockContract.getIdentity("ST2CY5...");
    expect(identity?.did).toBe("did:example:1234567890");
    expect(identity?.credentials).toEqual([]);
    expect(mockContract.totalIdentities).toBe(1n);
  });

  it("should prevent registering duplicate identities", () => {
    mockContract.registerIdentity("ST2CY5...", "did:example:1234567890");
    const result = mockContract.registerIdentity("ST2CY5...", "did:example:new");
    expect(result).toEqual({ error: 101 });
  });

  it("should prevent registering with invalid DID length", () => {
    const result = mockContract.registerIdentity("ST2CY5...", "short");
    expect(result).toEqual({ error: 103 });
  });

  it("should update DID", () => {
    mockContract.registerIdentity("ST2CY5...", "did:example:old");
    const result = mockContract.updateDid("ST2CY5...", "did:example:new1234567890");
    expect(result).toEqual({ value: true });
    const identity = mockContract.getIdentity("ST2CY5...");
    expect(identity?.did).toBe("did:example:new1234567890");
  });

  it("should prevent updating to same DID", () => {
    mockContract.registerIdentity("ST2CY5...", "did:example:1234567890");
    const result = mockContract.updateDid("ST2CY5...", "did:example:1234567890");
    expect(result).toEqual({ error: 109 });
  });

  it("should link a credential", () => {
    mockContract.registerIdentity("ST2CY5...", "did:example:1234567890");
    const result = mockContract.linkCredential("ST2CY5...", "cred:abc123");
    expect(result).toEqual({ value: true });
    const identity = mockContract.getIdentity("ST2CY5...");
    expect(identity?.credentials).toEqual(["cred:abc123"]);
  });

  it("should prevent linking duplicate credentials", () => {
    mockContract.registerIdentity("ST2CY5...", "did:example:1234567890");
    mockContract.linkCredential("ST2CY5...", "cred:abc123");
    const result = mockContract.linkCredential("ST2CY5...", "cred:abc123");
    expect(result).toEqual({ error: 101 });
  });

  it("should prevent linking when max credentials reached", () => {
    mockContract.registerIdentity("ST2CY5...", "did:example:1234567890");
    for (let i = 0; i < mockContract.MAX_CREDENTIALS; i++) {
      mockContract.linkCredential("ST2CY5...", `cred:${i}`);
    }
    const result = mockContract.linkCredential("ST2CY5...", "cred:extra");
    expect(result).toEqual({ error: 104 });
  });

  it("should unlink a credential", () => {
    mockContract.registerIdentity("ST2CY5...", "did:example:1234567890");
    mockContract.linkCredential("ST2CY5...", "cred:abc123");
    const result = mockContract.unlinkCredential("ST2CY5...", "cred:abc123");
    expect(result).toEqual({ value: true });
    const identity = mockContract.getIdentity("ST2CY5...");
    expect(identity?.credentials).toEqual([]);
  });

  it("should prevent unlinking non-existent credential", () => {
    mockContract.registerIdentity("ST2CY5...", "did:example:1234567890");
    const result = mockContract.unlinkCredential("ST2CY5...", "cred:nonexistent");
    expect(result).toEqual({ error: 108 });
  });

  it("should not allow operations when paused", () => {
    mockContract.setPaused(mockContract.admin, true);
    const regResult = mockContract.registerIdentity("ST2CY5...", "did:example:1234567890");
    expect(regResult).toEqual({ error: 106 });
    const updateResult = mockContract.updateDid("ST2CY5...", "did:example:new");
    expect(updateResult).toEqual({ error: 106 });
    const linkResult = mockContract.linkCredential("ST2CY5...", "cred:abc");
    expect(linkResult).toEqual({ error: 106 });
  });
});