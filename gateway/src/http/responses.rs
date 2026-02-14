use std::time::{SystemTime, UNIX_EPOCH};

use async_stream::try_stream;
use bytes::Bytes;
use futures_util::StreamExt;
use serde_json::{Value, json};

use crate::error::GatewayError;
use crate::sdk::ProviderStream;

pub fn build_chat_request(payload: &Value) -> Result<Value, GatewayError> {
    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            GatewayError::BadRequest("The request body must include a model".to_string())
        })?;

    let stream = payload
        .get("stream")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let messages = if let Some(messages) = payload.get("messages").and_then(Value::as_array) {
        Value::Array(messages.clone())
    } else {
        let input = payload.get("input").ok_or_else(|| {
            GatewayError::BadRequest("The request body must include input or messages".to_string())
        })?;
        to_messages_from_input(input)?
    };

    let mut request = json!({
        "model": model,
        "messages": messages,
        "stream": stream,
    });

    if let Some(value) = payload.get("temperature") {
        request["temperature"] = value.clone();
    }

    if let Some(value) = payload.get("top_p") {
        request["top_p"] = value.clone();
    }

    if let Some(value) = payload.get("max_output_tokens") {
        request["max_tokens"] = value.clone();
    }

    if let Some(value) = payload.get("max_tokens") {
        request["max_tokens"] = value.clone();
    }

    if let Some(value) = payload.get("max_completion_tokens") {
        request["max_completion_tokens"] = value.clone();
    }

    Ok(request)
}

pub fn response_from_chat_completion(chat_completion: &Value) -> Value {
    let chat_id = chat_completion
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or("chatcmpl-gateway");
    let response_id = format!("resp_{chat_id}");
    let created = chat_completion
        .get("created")
        .and_then(Value::as_u64)
        .unwrap_or_else(now_unix);
    let model = chat_completion
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or("unknown");

    let text = chat_completion
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
        .and_then(|choice| choice.get("message"))
        .and_then(|message| message.get("content"))
        .map(extract_text)
        .unwrap_or_default();

    json!({
        "id": response_id,
        "object": "response",
        "created_at": created,
        "status": "completed",
        "model": model,
        "output": [
            {
                "id": format!("msg_{chat_id}"),
                "type": "message",
                "role": "assistant",
                "content": [
                    {
                        "type": "output_text",
                        "text": text,
                        "annotations": []
                    }
                ]
            }
        ],
        "output_text": text,
        "usage": chat_completion.get("usage").cloned().unwrap_or_else(|| json!({})),
    })
}

pub fn stream_responses_from_chat_stream(chat_stream: ProviderStream) -> ProviderStream {
    let stream = try_stream! {
        let mut buffer = String::new();
        let mut response_id = "resp_gateway".to_string();
        let mut model = "unknown".to_string();
        let mut created = now_unix();
        let mut emitted_created = false;
        let mut emitted_completed = false;
        let mut full_text = String::new();

        futures_util::pin_mut!(chat_stream);

        while let Some(chunk) = chat_stream.next().await {
            let chunk = chunk?;
            buffer.push_str(&String::from_utf8_lossy(&chunk));

            while let Some(position) = buffer.find('\n') {
                let mut line = buffer[..position].to_string();
                buffer.drain(..=position);

                if line.ends_with('\r') {
                    line.pop();
                }

                let Some(data_line) = line.strip_prefix("data:") else {
                    continue;
                };

                let data_line = data_line.trim();
                if data_line.is_empty() {
                    continue;
                }

                if data_line == "[DONE]" {
                    if !emitted_completed {
                        let completed = response_completed_event(&response_id, created, &model, &full_text);
                        yield Bytes::from(format!("data: {}\\n\\n", completed));
                        yield Bytes::from_static(b"data: [DONE]\\n\\n");
                        emitted_completed = true;
                    }
                    continue;
                }

                let Ok(value) = serde_json::from_str::<Value>(data_line) else {
                    continue;
                };

                if let Some(id) = value.get("id").and_then(Value::as_str) {
                    response_id = format!("resp_{id}");
                }

                if let Some(model_name) = value.get("model").and_then(Value::as_str) {
                    model = model_name.to_string();
                }

                if let Some(created_value) = value.get("created").and_then(Value::as_u64) {
                    created = created_value;
                }

                if !emitted_created {
                    let created_event = json!({
                        "type": "response.created",
                        "response": {
                            "id": response_id,
                            "object": "response",
                            "created_at": created,
                            "status": "in_progress",
                            "model": model,
                        }
                    });
                    yield Bytes::from(format!("data: {}\\n\\n", created_event));
                    emitted_created = true;
                }

                let delta_text = value
                    .get("choices")
                    .and_then(Value::as_array)
                    .and_then(|choices| choices.first())
                    .and_then(|choice| choice.get("delta"))
                    .and_then(|delta| delta.get("content"))
                    .and_then(Value::as_str)
                    .unwrap_or_default();

                if !delta_text.is_empty() {
                    full_text.push_str(delta_text);
                    let delta_event = json!({
                        "type": "response.output_text.delta",
                        "response_id": response_id,
                        "delta": delta_text,
                    });
                    yield Bytes::from(format!("data: {}\\n\\n", delta_event));
                }

                let finish_reason = value
                    .get("choices")
                    .and_then(Value::as_array)
                    .and_then(|choices| choices.first())
                    .and_then(|choice| choice.get("finish_reason"));

                if finish_reason.is_some() && !finish_reason.is_some_and(Value::is_null) && !emitted_completed {
                    let completed = response_completed_event(&response_id, created, &model, &full_text);
                    yield Bytes::from(format!("data: {}\\n\\n", completed));
                    yield Bytes::from_static(b"data: [DONE]\\n\\n");
                    emitted_completed = true;
                }
            }
        }

        if !emitted_completed {
            if !emitted_created {
                let created_event = json!({
                    "type": "response.created",
                    "response": {
                        "id": response_id,
                        "object": "response",
                        "created_at": created,
                        "status": "in_progress",
                        "model": model,
                    }
                });
                yield Bytes::from(format!("data: {}\\n\\n", created_event));
            }

            let completed = response_completed_event(&response_id, created, &model, &full_text);
            yield Bytes::from(format!("data: {}\\n\\n", completed));
            yield Bytes::from_static(b"data: [DONE]\\n\\n");
        }
    };

    Box::pin(stream)
}

fn response_completed_event(response_id: &str, created: u64, model: &str, text: &str) -> Value {
    json!({
        "type": "response.completed",
        "response": {
            "id": response_id,
            "object": "response",
            "created_at": created,
            "status": "completed",
            "model": model,
            "output": [
                {
                    "id": format!("msg_{response_id}"),
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        {
                            "type": "output_text",
                            "text": text,
                            "annotations": []
                        }
                    ]
                }
            ],
            "output_text": text,
        }
    })
}

fn to_messages_from_input(input: &Value) -> Result<Value, GatewayError> {
    match input {
        Value::String(text) => Ok(json!([
            {
                "role": "user",
                "content": text,
            }
        ])),
        Value::Array(entries) => {
            if entries.is_empty() {
                return Err(GatewayError::BadRequest(
                    "input array must contain at least one entry".to_string(),
                ));
            }

            let mut messages = Vec::new();

            for entry in entries {
                if let Some(role) = entry.get("role").and_then(Value::as_str) {
                    let content = entry.get("content").map(extract_text).unwrap_or_default();

                    if content.is_empty() {
                        continue;
                    }

                    messages.push(json!({
                        "role": role,
                        "content": content,
                    }));
                    continue;
                }

                if let Some(text) = entry.get("text").and_then(Value::as_str) {
                    messages.push(json!({
                        "role": "user",
                        "content": text,
                    }));
                }
            }

            if messages.is_empty() {
                return Err(GatewayError::BadRequest(
                    "Unable to extract messages from input".to_string(),
                ));
            }

            Ok(Value::Array(messages))
        }
        _ => Err(GatewayError::BadRequest(
            "input must be a string or array".to_string(),
        )),
    }
}

fn extract_text(value: &Value) -> String {
    match value {
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

                if item.get("type").and_then(Value::as_str) == Some("output_text") {
                    return item.get("text").and_then(Value::as_str).map(str::to_string);
                }

                item.get("text").and_then(Value::as_str).map(str::to_string)
            })
            .collect::<Vec<_>>()
            .join("\n"),
        _ => String::new(),
    }
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}
