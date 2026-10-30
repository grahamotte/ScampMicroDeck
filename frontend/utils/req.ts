import * as changeKeys from "change-case/keys";
import { z } from "zod";

export const token = () => localStorage.getItem("jwt");

export const loggedIn = () => !!parsedToken();

export const parsedToken = () => {
  try {
    const t = JSON.parse(atob((token() || "").split(".")[1]) || "{}");
    if (Math.floor(Date.now() / 1000) > t.exp) return null;
    return t;
  } catch (e) {
    return null;
  }
};

export const req = async <T extends z.ZodSchema<any>>({
  method,
  url,
  data,
  params,
  headers,
  schema,
}: {
  url: string;
  schema: T;
  method?: string;
  data?: any;
  params?: any;
  headers?: any;
}) => {
  type InferFromSchema<T extends z.ZodSchema<any>> = z.infer<T>;
  let responseData;
  params ||= {};
  try {
    const requestUrl = new URL(url, import.meta.env.VITE_API_URL || window.location.origin);
    Object.entries(
      changeKeys.snakeCase({ ...params }, 999) as Record<string, unknown>,
    ).forEach(
      ([key, value]) => {
        if (value !== null && value !== undefined)
          requestUrl.searchParams.append(key, String(value));
      },
    );
    const requestMethod = method || "get";
    const requestHeaders = new Headers(headers);
    const body = ["get", "head"].includes(requestMethod.toLowerCase())
      ? undefined
      : JSON.stringify(changeKeys.snakeCase({ ...data }, 999));
    requestHeaders.set("Authorization", `Bearer ${token()}`);
    if (body) requestHeaders.set("Content-Type", "application/json");

    const response = await fetch(requestUrl, {
      method: requestMethod,
      headers: requestHeaders,
      body,
    });
    const responseText = await response.text();
    responseData = responseText ? JSON.parse(responseText) : null;

    const refreshToken = response.headers.get("refresh-token");
    if (refreshToken) localStorage.setItem("jwt", refreshToken);

    if (response.status === 401) void logout();
    if (!response.ok)
      throw new Error(`Request failed with status code ${response.status}`);

    console.log(url, params, responseData);

    return (schema || z.any()).parse(
      changeKeys.camelCase(responseData, 999),
    ) as InferFromSchema<T>;
  } catch (e) {
    console.log(url, params, responseData);
    console.log(e);
    throw e;
  }
};

export const login = ({
  handle,
  password,
}: {
  handle: string;
  password: string;
}) => {
  return req({
    method: "post",
    url: "/users/jwt",
    data: { handle: handle, password: password },
    schema: z.any(),
  }).then((data) => {
    localStorage.setItem("jwt", data.token);
  });
};

export const logout = () => {
  return new Promise((r: any) => {
    localStorage.removeItem("jwt");
    void req({ url: "/users/logout", schema: z.any() });
    r();
  });
};
