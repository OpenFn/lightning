import React, { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import App from "./App";

new EventSource('/esbuild').addEventListener('change', () => location.reload())

const root = createRoot(document.getElementById("root"));
root.render(
  <StrictMode>
    <App />
  </StrictMode>
);