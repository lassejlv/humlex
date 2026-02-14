# AI Gateway Docs

Small OpenAI-compatible gateway with provider adapters for OpenAI, Anthropic, Gemini, Kimi, OpenRouter, and Vercel AI Gateway.

## Run

```bash
cargo run
```

Default bind: `0.0.0.0:3000`

## Endpoints

- `GET /healthz`
- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/responses`

By default, provider keys come from incoming bearer auth:

`Authorization: Bearer <provider-api-key>`

If `GATEWAY_API_KEYS` is set, bearer auth is treated as a gateway key instead. In that mode,
configure provider API keys with `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `KIMI_API_KEY`,
`OPENROUTER_API_KEY`, and `VERCEL_AI_GATEWAY_API_KEY`.

## Provider Routing

`POST /v1/chat/completions` routes by `model`:

- `claude*` -> Anthropic
- `gemini*` -> Gemini
- `kimi*` -> Kimi
- `openrouter/<model>` -> OpenRouter
- `vercel/<model>` -> Vercel AI Gateway
- everything else -> OpenAI

You can also force provider with model prefixes:

- `openai/<model>`
- `anthropic/<model>`
- `gemini/<model>`
- `kimi/<model>`
- `openrouter/<model>`
- `vercel/<model>`

## Models Endpoint

- `GET /v1/models` aggregates all providers
- `GET /v1/models?provider=openai|anthropic|gemini|kimi|openrouter|vercel` fetches a single provider

## Kimi Notes

- Base URL: `https://api.kimi.com/coding/v1`
- Model: `kimi-for-coding` (only model)
- User-Agent is always set to `KimiCLI/1.3`

The Kimi adapter forces the upstream model to `kimi-for-coding`.

## Streaming Example

```bash
curl -N http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KIMI_API_KEY" \
  -d '{
    "model": "kimi-for-coding",
    "stream": true,
    "messages": [
      {"role": "user", "content": "Write a Rust function to parse CSV lines."}
    ]
  }'
```

## Responses API Example

```bash
curl -N http://localhost:3000/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "stream": true,
    "input": "Write a Rust function to parse CSV lines."
  }'
```

## Non-Streaming Example

```bash
curl http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "user", "content": "Hello"}
    ]
  }'
```

## Environment Variables

- `HOST` (default: `0.0.0.0`)
- `PORT` (default: `3000`)
- `REQUEST_TIMEOUT_SECS` (default: `120`)
- `UPSTREAM_MAX_RETRIES` (default: `2`)
- `UPSTREAM_RETRY_BASE_DELAY_MS` (default: `150`)
- `OPENAI_BASE_URL` (default: `https://api.openai.com`)
- `ANTHROPIC_BASE_URL` (default: `https://api.anthropic.com`)
- `GEMINI_BASE_URL` (default: `https://generativelanguage.googleapis.com/v1beta/openai`)
- `KIMI_BASE_URL` (default: `https://api.kimi.com/coding/v1`)
- `OPENROUTER_BASE_URL` (default: `https://openrouter.ai/api/v1`)
- `VERCEL_AI_GATEWAY_BASE_URL` (default: `https://ai-gateway.vercel.sh/v1`)
- `GATEWAY_API_KEYS` (optional comma-separated list)
- `OPENAI_API_KEY` (optional)
- `ANTHROPIC_API_KEY` (optional)
- `GEMINI_API_KEY` (optional)
- `KIMI_API_KEY` (optional)
- `OPENROUTER_API_KEY` (optional)
- `VERCEL_AI_GATEWAY_API_KEY` (optional)
