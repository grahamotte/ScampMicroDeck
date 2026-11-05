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

export const currentUser = () => {
  const t = parsedToken();
  if (!t?.user_id) return null;

  return { id: t.user_id as string, email: t.email as string };
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

const zGraphqlErrors = z
  .array(
    z.object({
      message: z.string(),
      extensions: z.object({ code: z.string().nullish() }).nullish(),
    }),
  )
  .nullish();

export const gql = async <T extends z.ZodTypeAny>({
  query,
  variables,
  schema,
}: {
  query: string;
  variables?: Record<string, unknown>;
  schema: T;
}): Promise<z.infer<T>> => {
  const headers = new Headers({ "Content-Type": "application/json" });
  const jwt = token();
  if (jwt) headers.set("Authorization", `Bearer ${jwt}`);

  const response = await fetch(
    new URL("/graphql", import.meta.env.VITE_API_URL || window.location.origin),
    { method: "post", headers, body: JSON.stringify({ query, variables }) },
  );
  const responseText = await response.text();
  const body = responseText ? JSON.parse(responseText) : null;

  const refreshToken = response.headers.get("refresh-token");
  if (refreshToken) localStorage.setItem("jwt", refreshToken);

  const errors = zGraphqlErrors.parse(body?.errors) || [];
  if (errors.some((error) => error.extensions?.code === "UNAUTHENTICATED")) {
    void logout();
  }
  if (!response.ok) {
    throw new Error(`Request failed with status code ${response.status}`);
  }
  if (errors.length > 0) {
    throw new Error(errors.map((error) => error.message).join(", "));
  }

  return schema.parse(body?.data);
};

export const login = ({
  email,
  password,
}: {
  email: string;
  password: string;
}) => {
  return gql({
    query: `mutation($email: String!, $password: String!) {
      createToken(email: $email, password: $password)
    }`,
    variables: { email, password },
    schema: z.object({ createToken: z.string() }),
  }).then((data) => {
    localStorage.setItem("jwt", data.createToken);
  });
};

export const logout = () => {
  localStorage.removeItem("jwt");
  return Promise.resolve();
};
