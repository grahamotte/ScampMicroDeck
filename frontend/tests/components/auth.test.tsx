import { Auth } from "@/components/auth";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

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

const currentJwt = () => {
  const payload = { exp: Math.floor(Date.now() / 1000) + 60, user_id: "u1" };
  return `header.${btoa(JSON.stringify(payload))}.signature`;
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });

const isLogin = (init?: RequestInit) => String(init?.body).includes("createToken");

const unauthenticated = {
  data: null,
  errors: [ { message: "unauthorized", extensions: { code: "UNAUTHENTICATED" } } ],
};

const submit = (email: string, password: string) => {
  fireEvent.change(screen.getByLabelText("Email"), { target: { value: email } });
  fireEvent.change(screen.getByLabelText("Password"), { target: { value: password } });
  fireEvent.submit(screen.getByRole("button", { name: "Sign in" }).closest("form")!);
};

beforeEach(() => {
  storage.clear();
  vi.stubGlobal("localStorage", storage);
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("Auth", () => {
  test("shows the login form without checking the viewer when logged out", () => {
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchMock);

    render(<Auth>Secret</Auth>);

    expect(screen.queryByText("Secret")).toBeNull();
    expect(screen.getByLabelText("Email")).toBeTruthy();
    expect(screen.getByLabelText("Password")).toBeTruthy();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("renders children and checks the viewer when a current token is stored", async () => {
    storage.setItem("jwt", currentJwt());
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockImplementation(() => Promise.resolve(jsonResponse({ data: { viewer: { id: "u1" } } })));
    vi.stubGlobal("fetch", fetchMock);

    render(<Auth>Secret</Auth>);

    expect(screen.getByText("Secret")).toBeTruthy();
    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    expect(String(fetchMock.mock.calls[0]![0])).toContain("/graphql");
    expect(String(fetchMock.mock.calls[0]![1]?.body)).toContain("viewer");
    expect(screen.getByText("Secret")).toBeTruthy();
  });

  test("shows the login form when the viewer check is unauthenticated", async () => {
    storage.setItem("jwt", currentJwt());
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>().mockImplementation(() => Promise.resolve(jsonResponse(unauthenticated))),
    );

    render(<Auth>Secret</Auth>);

    await waitFor(() => expect(screen.getByLabelText("Email")).toBeTruthy());
    expect(screen.queryByText("Secret")).toBeNull();
    expect(storage.getItem("jwt")).toBeNull();
  });

  test("keeps children when the viewer check fails for another reason", async () => {
    storage.setItem("jwt", currentJwt());
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockImplementation(() => Promise.resolve(new Response("", { status: 500 })));
    vi.stubGlobal("fetch", fetchMock);

    render(<Auth>Secret</Auth>);

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    expect(screen.getByText("Secret")).toBeTruthy();
  });

  test("logs in and then renders children", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockImplementation((_input, init) => {
      if (isLogin(init)) {
        return Promise.resolve(jsonResponse({ data: { createToken: currentJwt() } }));
      }

      return Promise.resolve(jsonResponse({ data: { viewer: { id: "u1" } } }));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<Auth>Secret</Auth>);
    submit("user@example.com", "pass");

    await waitFor(() => expect(screen.getByText("Secret")).toBeTruthy());
    const loginCall = fetchMock.mock.calls.find(([ , init ]) => isLogin(init));
    expect(JSON.parse(String(loginCall?.[1]?.body)).variables).toEqual({
      email: "user@example.com",
      password: "pass",
    });
  });

  test("keeps the login form when login fails", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockImplementation(() =>
      Promise.resolve(
        jsonResponse({
          data: null,
          errors: [ { message: "bad email/password", extensions: { code: "UNAUTHENTICATED" } } ],
        }),
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    render(<Auth>Secret</Auth>);
    submit("user@example.com", "wrong");

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    expect(screen.queryByText("Secret")).toBeNull();
    expect(screen.getByLabelText("Email")).toBeTruthy();
  });
});
