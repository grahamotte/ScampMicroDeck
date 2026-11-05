import React, { useEffect, useState } from "react";
import { z } from "zod";
import { gql, loggedIn as initLoggedIn, login } from "@/utils/req";

export const Auth = ({ children }: { children: React.ReactNode }) => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loggedIn, setLoggedIn] = useState(initLoggedIn());

  const performLogin = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    login({ email, password })
      .then(() => setLoggedIn(true))
      .catch(() => setLoggedIn(false));
  };

  useEffect(() => {
    if (!loggedIn) return;

    void gql({ query: "{ viewer { id } }", schema: z.any() }).catch(() =>
      setLoggedIn(initLoggedIn()),
    );
  }, [loggedIn]);

  if (loggedIn) return <>{children}</>;

  return (
    <div className="flex min-h-screen items-center justify-center px-6">
      <form
        className="flex w-full max-w-xs flex-col gap-3"
        onSubmit={performLogin}
      >
        <input
          type="email"
          autoComplete="username"
          autoCapitalize="off"
          autoFocus
          aria-label="Email"
          placeholder="Email"
          className="h-12 rounded-lg border px-4"
          onChange={(e) => setEmail(e.target.value)}
        />
        <input
          type="password"
          autoComplete="current-password"
          aria-label="Password"
          placeholder="Password"
          className="h-12 rounded-lg border px-4"
          onChange={(e) => setPassword(e.target.value)}
        />
        <button type="submit" className="h-12 rounded-lg border px-4 font-semibold">
          Sign in
        </button>
      </form>
    </div>
  );
};
