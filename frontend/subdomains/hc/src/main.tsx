import { req } from "@/utils/req";
import ReactDOM from "react-dom/client";
import { useEffect, useState } from "react";
import { z } from "zod";

const Hc = () => {
  const [data, setData] = useState<{
    frontendTime: string;
    backendTime: string;
    databaseTime: string;
    hcJobFinishedAt?: string | null | undefined;
  } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchData = () => {
      req({
        url: "/noop/hc",
        params: { frontendTime: new Date().toISOString() },
        schema: z.object({
          frontendTime: z.string(),
          backendTime: z.string(),
          databaseTime: z.string(),
          hcJobFinishedAt: z.string().nullish(),
        }),
      })
        .then((response) => {
          setData(response);
          setError(null);
        })
        .catch((responseError) => {
          setError(
            responseError instanceof Error
              ? responseError.message
              : String(responseError),
          );
        });
    };

    fetchData();
    const interval = setInterval(fetchData, 1000);
    return () => clearInterval(interval);
  }, []);

  const triggerBackendError = () => {
    void req({
      method: "post",
      url: "/noop/error",
      schema: z.any(),
    }).catch(() => undefined);
  };

  if (!data && !error) return <main>Loading...</main>;

  if (error) {
    return (
      <main>
        <strong>ERROR</strong>
        <div>{error}</div>
      </main>
    );
  }

  return (
    <main>
      <strong>{import.meta.env.VITE_TITLE}</strong>
      <div>Frontend = {data?.frontendTime}</div>
      <div>Backend = {data?.backendTime}</div>
      <div>Database = {data?.databaseTime}</div>
      <div>Jobs = {data?.hcJobFinishedAt}</div>
      <button onClick={triggerBackendError}>Trigger backend error</button>
    </main>
  );
};

ReactDOM.createRoot(document.getElementById("root")!).render(<Hc />);
