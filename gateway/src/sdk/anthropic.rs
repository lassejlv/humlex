use std::time::{SystemTime, UNIX_EPOCH};

use async_stream::try_stream;
use async_trait::async_trait;
use bytes::Bytes;
use futures_util::StreamExt;
use reqwest::header::{CONTENT_TYPE, HeaderMap, HeaderValue};
use serde_json::{Value, json};

use crate::error::GatewayError;
use crate::sdk::retry::{RetryPolicy, send_with_retry};
use crate::sdk::{ProviderSdk, ProviderStream};

const ANTHROPIC_VERSION: &str = "2023-06-01";

#[derive(Clone)]
pub struct AnthropicProvider {
    client: reqwest::Client,
    base_url: String,
    retry_policy: RetryPolicy,
}

impl AnthropicProvider {
    pub fn new(client: reqwest::Client, base_url: String, retry_policy: RetryPolicy) -> Self {
        Self {
            client,
            base_url,
            retry_policy,
        }
    }

    fn endpoint(&self, path: &str) -> String {
        format!("{}/{}", self.base_url, path.trim_start_matches('/'))
    }

    fn headers(api_key: &str) -> Result<HeaderMap, GatewayError> {
        let mut headers = HeaderMap::new();
        headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
        headers.insert(
            "x-api-key",
            HeaderValue::from_str(api_key)
                .map_err(|_| GatewayError::Unauthorized("Invalid API key".to_string()))?,
        );
        headers.insert(
            "anthropic-version",
            HeaderValue::from_static(ANTHROPIC_VERSION),
        );
        Ok(headers)
    }

    fn now_unix() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_secs())
            .unwrap_or(0)
    }

    fn to_anthropic_request(request: &Value, stream: bool) -> Result<Value, GatewayError> {
        let model = request
            .get("model")
            .and_then(Value::as_str)
            .ok_or_else(|| GatewayError::BadRequest("Missing model".to_string()))?;

        let messages = request
            .get("messages")
            .and_then(Value::as_array)
            .ok_or_else(|| GatewayError::BadRequest("Missing messages".to_string()))?;

        let mut system_messages = Vec::new();
        let mut anthropic_messages = Vec::new();

        for message in messages {
            let role = message
                .get("role")
                .and_then(Value::as_str)
                .unwrap_or("user");
            let content = extract_text_content(message.get("content").unwrap_or(&Value::Null));

            if content.trim().is_empty() {
                continue;
            }

            if role == "system" {
                system_messages.push(content);
                continue;
            }

            if role != "user" && role != "assistant" {
                continue;
            }

            anthropic_messages.push(json!({
                "role": role,
                "content": [
                    {
                        "type": "text",
                        "text": content,
                    }
                ]
            }));
        }

        if anthropic_messages.is_empty() {
            return Err(GatewayError::BadRequest(
                "At least one user or assistant message is required".to_string(),
            ));
        }

        let max_tokens = request
            .get("max_tokens")
            .and_then(Value::as_u64)
            .or_else(|| request.get("max_completion_tokens").and_then(Value::as_u64))
            .unwrap_or(1024);

        let mut body = json!({
            "model": model,
            "messages": anthropic_messages,
            "max_tokens": max_tokens,
            "stream": stream,
        });

        if let Some(temperature) = request.get("temperature").and_then(Value::as_f64) {
            body["temperature"] = json!(temperature);
        }

        if let Some(top_p) = request.get("top_p").and_then(Value::as_f64) {
            body["top_p"] = json!(top_p);
        }

        if !system_messages.is_empty() {
            body["system"] = json!(system_messages.join("\n\n"));
        }

        Ok(body)
    }

    fn to_openai_model_list(response: &Value) -> Value {
        let data = response
            .get("data")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();

        let mapped = data
            .into_iter()
            .filter_map(|item| item.get("id").and_then(Value::as_str).map(str::to_string))
            .map(|id| {
                json!({
                    "id": id,
                    "object": "model",
                    "created": 0,
                    "owned_by": "anthropic",
                })
            })
            .collect::<Vec<_>>();

        json!({
            "object": "list",
            "data": mapped,
        })
    }

    fn to_openai_completion(response: &Value, requested_model: &str) -> Value {
        let id = response
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or("chatcmpl-anthropic")
            .to_string();

        let model = response
            .get("model")
            .and_then(Value::as_str)
            .unwrap_or(requested_model)
            .to_string();

        let content = response
            .get("content")
            .and_then(Value::as_array)
            .map(|blocks| {
                blocks
                    .iter()
                    .filter(|block| block.get("type").and_then(Value::as_str) == Some("text"))
                    .filter_map(|block| block.get("text").and_then(Value::as_str))
                    .collect::<String>()
            })
            .unwrap_or_default();

        let prompt_tokens = response
            .get("usage")
            .and_then(|usage| usage.get("input_tokens"))
            .and_then(Value::as_u64)
            .unwrap_or(0);

        let completion_tokens = response
            .get("usage")
            .and_then(|usage| usage.get("output_tokens"))
            .and_then(Value::as_u64)
            .unwrap_or(0);

        let finish_reason = map_stop_reason(
            response
                .get("stop_reason")
                .and_then(Value::as_str)
                .unwrap_or("end_turn"),
        );

        json!({
            "id": id,
            "object": "chat.completion",
            "created": Self::now_unix(),
            "model": model,
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": content,
                    },
                    "finish_reason": finish_reason,
                    "logprobs": null,
                }
            ],
            "usage": {
                "prompt_tokens": prompt_tokens,
                "completion_tokens": completion_tokens,
                "total_tokens": prompt_tokens + completion_tokens,
            }
        })
    }

    async fn parse_json_response(response: reqwest::Response) -> Result<Value, GatewayError> {
        let status = response.status();
        let text = response.text().await?;

        if !status.is_success() {
            return Err(GatewayError::upstream(status, text));
        }

        serde_json::from_str(&text)
            .map_err(|_| GatewayError::Internal("Upstream returned invalid JSON".to_string()))
    }
}

#[async_trait]
impl ProviderSdk for AnthropicProvider {
    async fn fetch_models(&self, api_key: &str) -> Result<Value, GatewayError> {
        let headers = Self::headers(api_key)?;
        let response = send_with_retry(
            || {
                self.client
                    .get(self.endpoint("/v1/models"))
                    .headers(headers.clone())
            },
            self.retry_policy,
        )
        .await?;

        let parsed = Self::parse_json_response(response).await?;
        Ok(Self::to_openai_model_list(&parsed))
    }

    async fn generate_text(&self, api_key: &str, request: Value) -> Result<Value, GatewayError> {
        let requested_model = request
            .get("model")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();

        let body = Self::to_anthropic_request(&request, false)?;
        let headers = Self::headers(api_key)?;

        let response = send_with_retry(
            || {
                self.client
                    .post(self.endpoint("/v1/messages"))
                    .headers(headers.clone())
                    .json(&body)
            },
            self.retry_policy,
        )
        .await?;

        let parsed = Self::parse_json_response(response).await?;
        Ok(Self::to_openai_completion(&parsed, &requested_model))
    }

    async fn stream_text(
        &self,
        api_key: &str,
        request: Value,
    ) -> Result<ProviderStream, GatewayError> {
        let requested_model = request
            .get("model")
            .and_then(Value::as_str)
            .unwrap_or("claude")
            .to_string();
        let body = Self::to_anthropic_request(&request, true)?;
        let headers = Self::headers(api_key)?;

        let response = send_with_retry(
            || {
                self.client
                    .post(self.endpoint("/v1/messages"))
                    .headers(headers.clone())
                    .json(&body)
            },
            self.retry_policy,
        )
        .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(GatewayError::upstream(status, body));
        }

        let created = Self::now_unix();
        let upstream = response
            .bytes_stream()
            .map(|chunk| chunk.map_err(GatewayError::from));

        let stream = try_stream! {
            let mut buffer = String::new();
            let mut current_event = String::new();
            let mut message_id = "chatcmpl-anthropic".to_string();
            let mut model = requested_model;
            let mut sent_role = false;
            let mut sent_done = false;
            let mut finish_reason = "stop".to_string();

            futures_util::pin_mut!(upstream);

            while let Some(chunk) = upstream.next().await {
                let chunk = chunk?;
                buffer.push_str(&String::from_utf8_lossy(&chunk));

                while let Some(position) = buffer.find('\n') {
                    let mut line = buffer[..position].to_string();
                    buffer.drain(..=position);

                    if line.ends_with('\r') {
                        line.pop();
                    }

                    if line.is_empty() {
                        continue;
                    }

                    if let Some(value) = line.strip_prefix("event:") {
                        current_event = value.trim().to_string();
                        continue;
                    }

                    let Some(data_line) = line.strip_prefix("data:") else {
                        continue;
                    };

                    let data_line = data_line.trim();
                    if data_line == "[DONE]" {
                        if !sent_done {
                            yield Bytes::from_static(b"data: [DONE]\\n\\n");
                            sent_done = true;
                        }
                        continue;
                    }

                    let Ok(data) = serde_json::from_str::<Value>(data_line) else {
                        continue;
                    };

                    if current_event == "message_start" {
                        if let Some(value) = data
                            .get("message")
                            .and_then(|message| message.get("id"))
                            .and_then(Value::as_str)
                        {
                            message_id = value.to_string();
                        }

                        if let Some(value) = data
                            .get("message")
                            .and_then(|message| message.get("model"))
                            .and_then(Value::as_str)
                        {
                            model = value.to_string();
                        }
                    }

                    if current_event == "message_delta" {
                        if let Some(value) = data
                            .get("delta")
                            .and_then(|delta| delta.get("stop_reason"))
                            .and_then(Value::as_str)
                        {
                            finish_reason = map_stop_reason(value).to_string();
                        }
                    }

                    if current_event == "content_block_delta" {
                        let delta_text = data
                            .get("delta")
                            .and_then(|delta| delta.get("text"))
                            .and_then(Value::as_str)
                            .unwrap_or_default();

                        if delta_text.is_empty() {
                            continue;
                        }

                        if !sent_role {
                            let role_chunk = json!({
                                "id": message_id,
                                "object": "chat.completion.chunk",
                                "created": created,
                                "model": model,
                                "choices": [
                                    {
                                        "index": 0,
                                        "delta": {"role": "assistant"},
                                        "finish_reason": null,
                                    }
                                ]
                            });

                            yield Bytes::from(format!("data: {}\\n\\n", role_chunk));
                            sent_role = true;
                        }

                        let content_chunk = json!({
                            "id": message_id,
                            "object": "chat.completion.chunk",
                            "created": created,
                            "model": model,
                            "choices": [
                                {
                                    "index": 0,
                                    "delta": {"content": delta_text},
                                    "finish_reason": null,
                                }
                            ]
                        });

                        yield Bytes::from(format!("data: {}\\n\\n", content_chunk));
                    }

                    if current_event == "message_stop" {
                        let final_chunk = json!({
                            "id": message_id,
                            "object": "chat.completion.chunk",
                            "created": created,
                            "model": model,
                            "choices": [
                                {
                                    "index": 0,
                                    "delta": {},
                                    "finish_reason": finish_reason,
                                }
                            ]
                        });

                        yield Bytes::from(format!("data: {}\\n\\n", final_chunk));
                        yield Bytes::from_static(b"data: [DONE]\\n\\n");
                        sent_done = true;
                    }
                }
            }

            if !sent_done {
                let final_chunk = json!({
                    "id": message_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [
                        {
                            "index": 0,
                            "delta": {},
                            "finish_reason": finish_reason,
                        }
                    ]
                });

                yield Bytes::from(format!("data: {}\\n\\n", final_chunk));
                yield Bytes::from_static(b"data: [DONE]\\n\\n");
            }
        };

        Ok(Box::pin(stream))
    }
}

fn extract_text_content(content: &Value) -> String {
    match content {
        Value::String(text) => text.to_string(),
        Value::Array(items) => items
            .iter()
            .filter_map(|item| {
                if let Some(text) = item.as_str() {
                    return Some(text.to_string());
                }

                if item.get("type").and_then(Value::as_str) == Some("text") {
                    return item.get("text").and_then(Value::as_str).map(str::to_string);
                }

                item.get("text").and_then(Value::as_str).map(str::to_string)
            })
            .collect::<Vec<_>>()
            .join("\n"),
        _ => String::new(),
    }
}

fn map_stop_reason(value: &str) -> &'static str {
    match value {
        "max_tokens" => "length",
        "tool_use" => "tool_calls",
        _ => "stop",
    }
}
