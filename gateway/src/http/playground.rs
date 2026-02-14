use axum::response::Html;

pub async fn playground() -> Html<&'static str> {
    Html(PLAYGROUND_HTML)
}

const PLAYGROUND_HTML: &str = r#"<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Gateway Playground</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #0b1020;
      --panel: #131a2e;
      --line: #253050;
      --text: #edf2ff;
      --muted: #9aa7c7;
      --accent: #4c8dff;
      --good: #26b38f;
      --bad: #ff6b6b;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      font: 14px/1.4 ui-monospace, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
      background: radial-gradient(1200px 700px at 10% -20%, #1c2750 0%, var(--bg) 55%);
      color: var(--text);
    }

    .wrap {
      max-width: 1120px;
      margin: 0 auto;
      padding: 20px;
      display: grid;
      gap: 14px;
    }

    .card {
      background: color-mix(in srgb, var(--panel) 92%, transparent);
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 14px;
      backdrop-filter: blur(6px);
    }

    h1 {
      margin: 0 0 4px 0;
      font-size: 20px;
    }

    .muted { color: var(--muted); }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 10px;
    }

    label { display: grid; gap: 6px; }

    input, select, textarea, button {
      width: 100%;
      border-radius: 8px;
      border: 1px solid var(--line);
      background: #0f1730;
      color: var(--text);
      padding: 9px 10px;
      font: inherit;
    }

    textarea { min-height: 120px; resize: vertical; }

    .actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }

    button {
      width: auto;
      cursor: pointer;
      background: linear-gradient(180deg, #5a98ff, var(--accent));
      color: #ffffff;
      border: 0;
      font-weight: 600;
    }

    button.secondary {
      background: #1a274a;
      border: 1px solid #30457f;
      color: #e8eeff;
      font-weight: 500;
    }

    .status {
      white-space: pre-wrap;
      color: var(--muted);
      min-height: 22px;
    }

    .status.ok { color: var(--good); }
    .status.err { color: var(--bad); }

    pre {
      margin: 0;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 12px;
      background: #0a1228;
      max-height: 420px;
      overflow: auto;
      white-space: pre-wrap;
      word-break: break-word;
    }

    .split {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }

    @media (max-width: 900px) {
      .split { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h1>Gateway Playground</h1>
      <div class="muted">Test /providers, /v1/models, /v1/chat/completions, and /v1/responses.</div>
    </div>

    <div class="card">
      <div class="grid">
        <label>
          Gateway URL
          <input id="baseUrl" type="text" />
        </label>
        <label>
          API Key (Bearer)
          <input id="apiKey" type="password" placeholder="sk-..." />
        </label>
        <label>
          Provider
          <select id="provider">
            <option value="auto">auto</option>
          </select>
        </label>
        <label>
          Model
          <input id="model" type="text" value="gpt-4o-mini" />
        </label>
      </div>
      <div class="grid" style="margin-top: 10px;">
        <label>
          Message
          <textarea id="message">Write a tiny Rust function that parses CSV lines.</textarea>
        </label>
        <label>
          Request Body (override optional)
          <textarea id="bodyOverride" placeholder="Leave empty to auto-build JSON body"></textarea>
        </label>
      </div>
      <div class="grid" style="margin-top: 10px;">
        <label>
          Endpoint
          <select id="endpoint">
            <option value="chat">/v1/chat/completions</option>
            <option value="responses">/v1/responses</option>
            <option value="models">/v1/models</option>
            <option value="providers">/providers</option>
          </select>
        </label>
        <label>
          <span>Streaming</span>
          <select id="stream">
            <option value="true">true</option>
            <option value="false">false</option>
          </select>
        </label>
      </div>
      <div class="actions" style="margin-top: 12px;">
        <button id="send">Send</button>
        <button id="loadProviders" class="secondary">Load Providers</button>
        <button id="loadModels" class="secondary">Load Models</button>
        <button id="clear" class="secondary">Clear Output</button>
      </div>
      <div id="status" class="status" style="margin-top: 10px;"></div>
    </div>

    <div class="split">
      <div class="card">
        <div class="muted" style="margin-bottom: 8px;">Request</div>
        <pre id="requestView">{}</pre>
      </div>
      <div class="card">
        <div class="muted" style="margin-bottom: 8px;">Response</div>
        <pre id="responseView"></pre>
      </div>
    </div>
  </div>

  <script>
    const baseUrlEl = document.getElementById("baseUrl");
    const apiKeyEl = document.getElementById("apiKey");
    const providerEl = document.getElementById("provider");
    const modelEl = document.getElementById("model");
    const messageEl = document.getElementById("message");
    const bodyOverrideEl = document.getElementById("bodyOverride");
    const endpointEl = document.getElementById("endpoint");
    const streamEl = document.getElementById("stream");
    const requestViewEl = document.getElementById("requestView");
    const responseViewEl = document.getElementById("responseView");
    const statusEl = document.getElementById("status");

    baseUrlEl.value = window.location.origin;

    function setStatus(text, kind) {
      statusEl.textContent = text;
      statusEl.className = "status" + (kind ? " " + kind : "");
    }

    function getHeaders() {
      const headers = { "Content-Type": "application/json" };
      const key = apiKeyEl.value.trim();
      if (key) {
        headers["Authorization"] = "Bearer " + key;
      }
      return headers;
    }

    function normalizeBaseUrl() {
      return baseUrlEl.value.trim().replace(/\/$/, "");
    }

    function resolveModel() {
      const provider = providerEl.value;
      const model = modelEl.value.trim();
      if (!model) {
        return "";
      }
      if (provider === "auto" || provider === "openai") {
        return model;
      }
      if (model.includes("/")) {
        return model;
      }
      return provider + "/" + model;
    }

    function buildBody() {
      const override = bodyOverrideEl.value.trim();
      if (override) {
        return JSON.parse(override);
      }

      const endpoint = endpointEl.value;
      const stream = streamEl.value === "true";
      const model = resolveModel();
      const message = messageEl.value;

      if (endpoint === "chat") {
        return {
          model,
          stream,
          messages: [{ role: "user", content: message }],
        };
      }

      if (endpoint === "responses") {
        return {
          model,
          stream,
          input: message,
        };
      }

      return null;
    }

    async function sendRequest() {
      responseViewEl.textContent = "";
      setStatus("Sending...");

      const base = normalizeBaseUrl();
      const endpoint = endpointEl.value;
      const headers = getHeaders();
      const stream = streamEl.value === "true";
      const provider = providerEl.value;

      try {
        if (endpoint === "providers") {
          const url = base + "/providers";
          requestViewEl.textContent = "GET " + url;
          const res = await fetch(url, { headers });
          const text = await res.text();
          responseViewEl.textContent = formatJson(text);
          setStatus("Done: " + res.status, res.ok ? "ok" : "err");
          return;
        }

        if (endpoint === "models") {
          const query = provider !== "auto" ? "?provider=" + encodeURIComponent(provider) : "";
          const url = base + "/v1/models" + query;
          requestViewEl.textContent = "GET " + url;
          const res = await fetch(url, { headers });
          const text = await res.text();
          responseViewEl.textContent = formatJson(text);
          setStatus("Done: " + res.status, res.ok ? "ok" : "err");
          return;
        }

        const body = buildBody();
        const path = endpoint === "chat" ? "/v1/chat/completions" : "/v1/responses";
        const url = base + path;

        requestViewEl.textContent = JSON.stringify({
          method: "POST",
          url,
          headers,
          body,
        }, null, 2);

        const res = await fetch(url, {
          method: "POST",
          headers,
          body: JSON.stringify(body),
        });

        if (!res.ok) {
          const text = await res.text();
          responseViewEl.textContent = formatJson(text);
          setStatus("Error: " + res.status, "err");
          return;
        }

        if (stream) {
          await readSse(res);
          setStatus("Stream completed", "ok");
          return;
        }

        const text = await res.text();
        responseViewEl.textContent = formatJson(text);
        setStatus("Done: " + res.status, "ok");
      } catch (error) {
        setStatus("Request failed: " + error.message, "err");
      }
    }

    async function readSse(res) {
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }

        buffer += decoder.decode(value, { stream: true });

        while (true) {
          const idx = buffer.indexOf("\n");
          if (idx === -1) {
            break;
          }

          const line = buffer.slice(0, idx).trim();
          buffer = buffer.slice(idx + 1);

          if (!line.startsWith("data:")) {
            continue;
          }

          const data = line.slice(5).trim();
          if (!data) {
            continue;
          }

          responseViewEl.textContent += (data + "\n");
          responseViewEl.scrollTop = responseViewEl.scrollHeight;
        }
      }
    }

    function formatJson(text) {
      try {
        return JSON.stringify(JSON.parse(text), null, 2);
      } catch {
        return text;
      }
    }

    async function loadProviders() {
      const base = normalizeBaseUrl();
      const headers = getHeaders();
      try {
        const res = await fetch(base + "/providers", { headers });
        const payload = await res.json();
        const ids = (payload.data || []).map((item) => item.id).filter(Boolean);
        const options = ["auto", ...ids];
        providerEl.innerHTML = options
          .map((id) => `<option value="${id}">${id}</option>`)
          .join("");
        setStatus("Providers loaded", "ok");
      } catch (error) {
        setStatus("Failed loading providers: " + error.message, "err");
      }
    }

    async function loadModels() {
      endpointEl.value = "models";
      await sendRequest();
    }

    document.getElementById("send").addEventListener("click", sendRequest);
    document.getElementById("loadProviders").addEventListener("click", loadProviders);
    document.getElementById("loadModels").addEventListener("click", loadModels);
    document.getElementById("clear").addEventListener("click", () => {
      responseViewEl.textContent = "";
      setStatus("");
    });

    loadProviders();
  </script>
</body>
</html>
"#;
