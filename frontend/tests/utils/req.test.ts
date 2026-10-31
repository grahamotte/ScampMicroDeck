import {
  currentUser,
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

describe("authentication", () => {
  test("login stores the returned token", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(JSON.stringify({ token: "new-token" })),
    );
    vi.stubGlobal("fetch", fetchMock);

    await login({ email: "user@example.com", password: "password" });

    expect(localStorage.getItem("jwt")).toBe("new-token");
    expect(fetchMock.mock.calls[0]![1]?.method).toBe("post");
    expect(fetchMock.mock.calls[0]![1]?.body).toBe(
      '{"email":"user@example.com","password":"password"}',
    );
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
