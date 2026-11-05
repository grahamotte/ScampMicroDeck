import {
  currentUser,
  gql,
  loggedIn,
  login,
  logout,
  parsedToken,
  req,
  token,
} from "@/utils/req";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { z } from "zod";

const values = new Map<string, string>();
const storage: Storage = {
  get length() {
    return values.size;
  },
  clear: () => values.clear(),
  getItem: (key) => values.get(key) ?? null,
  key: (index) => [ ...values.keys() ][index] ?? null,
  removeItem: (key) => values.delete(key),
  setItem: (key, value) => values.set(key, value),
};

beforeEach(() => {
  storage.clear();
  vi.stubGlobal("localStorage", storage);
  vi.stubGlobal("window", { location: { origin: "https://example.com" } });
  vi.stubEnv("VITE_API_URL", "https://api.example.com");
  vi.spyOn(console, "log").mockImplementation(() => undefined);
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

describe("parsedToken", () => {
  test("returns a current token payload", () => {
    const payload = { exp: Math.floor(Date.now() / 1000) + 60, userId: 7 };
    localStorage.setItem("jwt", `header.${btoa(JSON.stringify(payload))}.signature`);

    expect(parsedToken()).toEqual(payload);
    expect(token()).toContain("header.");
    expect(loggedIn()).toBe(true);
  });

  test("rejects expired and malformed tokens", () => {
    localStorage.setItem("jwt", `header.${btoa(JSON.stringify({ exp: 0 }))}.signature`);
    expect(parsedToken()).toBeNull();

    localStorage.setItem("jwt", "invalid");
    expect(parsedToken()).toBeNull();
    expect(loggedIn()).toBe(false);
  });
});

describe("currentUser", () => {
  test("returns the signed-in user from the token", () => {
    const payload = {
      exp: Math.floor(Date.now() / 1000) + 60,
      user_id: "u1",
      email: "user@example.com",
    };
    localStorage.setItem("jwt", `header.${btoa(JSON.stringify(payload))}.signature`);

    expect(currentUser()).toEqual({ id: "u1", email: "user@example.com" });
  });

  test("returns null without a user", () => {
    expect(currentUser()).toBeNull();

    const payload = { exp: Math.floor(Date.now() / 1000) + 60 };
    localStorage.setItem("jwt", `header.${btoa(JSON.stringify(payload))}.signature`);
    expect(currentUser()).toBeNull();
  });
});

describe("req", () => {
  test("serializes requests and parses responses", async () => {
    localStorage.setItem("jwt", "token");
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(JSON.stringify({ item_id: 4 }), {
        headers: { "refresh-token": "refreshed" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(
      req({
        method: "post",
        url: "/items",
        params: { pageNumber: 2, ignored: null },
        data: { itemName: "Example" },
        schema: z.object({ itemId: z.number() }),
      }),
    ).resolves.toEqual({ itemId: 4 });

    const [ url, request ] = fetchMock.mock.calls[0]!;
    expect(url.toString()).toBe("https://api.example.com/items?page_number=2");
    expect(request?.method).toBe("post");
    expect(request?.body).toBe('{"item_name":"Example"}');
    expect(new Headers(request?.headers).get("Authorization")).toBe("Bearer token");
    expect(localStorage.getItem("jwt")).toBe("refreshed");
  });

  test("sends GET requests without a body and parses empty responses", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(""));
    vi.stubGlobal("fetch", fetchMock);

    await expect(req({ url: "/empty", schema: z.null() })).resolves.toBeNull();

    const [ , request ] = fetchMock.mock.calls[0]!;
    expect(request?.method).toBe("get");
    expect(request?.body).toBeUndefined();
    expect(new Headers(request?.headers).has("Content-Type")).toBe(false);
  });

  test("falls back to the page origin without an API URL", async () => {
    vi.stubEnv("VITE_API_URL", "");
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(""));
    vi.stubGlobal("fetch", fetchMock);

    await req({ url: "/empty", schema: z.null() });

    expect(fetchMock.mock.calls[0]![0].toString()).toBe("https://example.com/empty");
  });

  test("throws for failed requests and logs out after unauthorized responses", async () => {
    localStorage.setItem("jwt", "token");
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValue(new Response("{}", { status: 401 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(req({ url: "/private", schema: z.any() })).rejects.toThrow(
      "Request failed with status code 401",
    );
    expect(localStorage.getItem("jwt")).toBeNull();
    expect(fetchMock).toHaveBeenCalledOnce();
  });
});

describe("gql", () => {
  test("posts the query and variables and parses data", async () => {
    localStorage.setItem("jwt", "token");
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(JSON.stringify({ data: { viewer: { id: "u1" } } }), {
        headers: { "refresh-token": "refreshed" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(
      gql({
        query: "query($id: ID!) { item(id: $id) { id } }",
        variables: { id: "u1" },
        schema: z.object({ viewer: z.object({ id: z.string() }) }),
      }),
    ).resolves.toEqual({ viewer: { id: "u1" } });

    const [ url, request ] = fetchMock.mock.calls[0]!;
    expect(url.toString()).toBe("https://api.example.com/graphql");
    expect(request?.method).toBe("post");
    expect(request?.body).toBe(
      '{"query":"query($id: ID!) { item(id: $id) { id } }","variables":{"id":"u1"}}',
    );
    expect(new Headers(request?.headers).get("Authorization")).toBe("Bearer token");
    expect(new Headers(request?.headers).get("Content-Type")).toBe("application/json");
    expect(localStorage.getItem("jwt")).toBe("refreshed");
  });

  test("omits authorization without a token and falls back to the page origin", async () => {
    vi.stubEnv("VITE_API_URL", "");
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(JSON.stringify({ data: { healthCheck: null } })),
    );
    vi.stubGlobal("fetch", fetchMock);

    await gql({ query: "{ healthCheck { frontendTime } }", schema: z.any() });

    const [ url, request ] = fetchMock.mock.calls[0]!;
    expect(url.toString()).toBe("https://example.com/graphql");
    expect(new Headers(request?.headers).has("Authorization")).toBe(false);
  });

  test("rejects graphql errors", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>().mockResolvedValue(
        new Response(
          JSON.stringify({
            data: null,
            errors: [ { message: "User not found" }, { message: "other" } ],
          }),
        ),
      ),
    );

    await expect(gql({ query: "{ viewer { id } }", schema: z.any() })).rejects.toThrow(
      "User not found, other",
    );
  });

  test("removes the token on unauthenticated errors", async () => {
    localStorage.setItem("jwt", "token");
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>().mockResolvedValue(
        new Response(
          JSON.stringify({
            data: null,
            errors: [ { message: "unauthorized", extensions: { code: "UNAUTHENTICATED" } } ],
          }),
        ),
      ),
    );

    await expect(gql({ query: "{ viewer { id } }", schema: z.any() })).rejects.toThrow(
      "unauthorized",
    );
    expect(localStorage.getItem("jwt")).toBeNull();
  });

  test("keeps the token on other errors", async () => {
    localStorage.setItem("jwt", "token");
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>().mockResolvedValue(
        new Response(
          JSON.stringify({
            data: null,
            errors: [ { message: "too many requests", extensions: { code: "RATE_LIMITED" } } ],
          }),
        ),
      ),
    );

    await expect(gql({ query: "{ viewer { id } }", schema: z.any() })).rejects.toThrow(
      "too many requests",
    );
    expect(localStorage.getItem("jwt")).toBe("token");
  });

  test("rejects failed responses", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>().mockResolvedValue(new Response("", { status: 500 })),
    );

    await expect(gql({ query: "{ viewer { id } }", schema: z.any() })).rejects.toThrow(
      "Request failed with status code 500",
    );
  });

  test("rejects data that does not match the schema", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify({ data: { viewer: null } }))),
    );

    await expect(
      gql({ query: "{ viewer { id } }", schema: z.object({ viewer: z.object({ id: z.string() }) }) }),
    ).rejects.toThrow();
  });
});

describe("authentication", () => {
  test("login stores the token from createToken", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(JSON.stringify({ data: { createToken: "new-token" } })),
    );
    vi.stubGlobal("fetch", fetchMock);

    await login({ email: "user@example.com", password: "password" });

    expect(localStorage.getItem("jwt")).toBe("new-token");
    expect(String(fetchMock.mock.calls[0]![0])).toBe("https://api.example.com/graphql");
    const body = JSON.parse(String(fetchMock.mock.calls[0]![1]?.body));
    expect(body.query).toContain("createToken(email: $email, password: $password)");
    expect(body.variables).toEqual({ email: "user@example.com", password: "password" });
  });

  test("login rejects bad credentials without storing a token", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>().mockResolvedValue(
        new Response(
          JSON.stringify({
            data: null,
            errors: [ { message: "bad email/password", extensions: { code: "UNAUTHENTICATED" } } ],
          }),
        ),
      ),
    );

    await expect(login({ email: "user@example.com", password: "wrong" })).rejects.toThrow(
      "bad email/password",
    );
    expect(localStorage.getItem("jwt")).toBeNull();
  });

  test("logout removes the token without a request", async () => {
    localStorage.setItem("jwt", "token");
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response("{}"));
    vi.stubGlobal("fetch", fetchMock);

    await logout();

    expect(localStorage.getItem("jwt")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
